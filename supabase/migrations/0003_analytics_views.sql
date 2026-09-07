-- 0003_analytics_views.sql
-- Organizer-only analytics views. All stats computed in SQL; each view exposes
-- its sample size. A 40% data-quality gate (response_rate >= 0.40) filters the
-- aggregate views so sparsely-rated games do not skew results.
--
-- Every view uses security_invoker = on: it runs with the caller's privileges,
-- so the base-table RLS policies (which restrict rating/appearance rows to the
-- owner or an organizer) apply. In practice only an organizer can see the full
-- set of underlying rows, which is what makes these effectively organizer-only.
-- We also revoke from anon and grant select to authenticated explicitly.

-- ===========================================================================
-- v_game_summary : one row per game (admin game list + several charts)
-- ===========================================================================
create view v_game_summary
with (security_invoker = on) as
with app as (
  select game_id, count(*) as headcount
  from appearance
  group by game_id
),
rat as (
  select
    game_id,
    count(*)                     as response_count,
    avg(overall)                 as mean_overall,
    stddev_samp(overall)         as stddev_overall,  -- null when n < 2
    avg(speed)                   as mean_speed,
    avg(intensity)               as mean_intensity
  from rating
  group by game_id
)
select
  g.id,
  g.starts_at,
  g.location,
  g.status,
  coalesce(app.headcount, 0)                                      as headcount,
  coalesce(rat.response_count, 0)                                 as response_count,
  rat.response_count::numeric / nullif(app.headcount, 0)          as response_rate,
  rat.mean_overall,
  rat.stddev_overall,
  rat.mean_speed,
  rat.mean_intensity,
  (rat.response_count::numeric / nullif(app.headcount, 0)) < 0.40 as is_low_response,
  extract(dow  from g.starts_at)                                  as dow,
  extract(hour from g.starts_at)                                  as hour
from game g
left join app on app.game_id = g.id
left join rat on rat.game_id = g.id;

comment on view v_game_summary is
  'One row per game with headcount, rating counts/means, response_rate, '
  'low-response flag, and day-of-week/hour. Base for the other analytics views.';

-- ===========================================================================
-- v_headcount_effect : does crowd size affect game quality?
-- Qualifying games (response_rate >= 0.40) bucketed by headcount.
-- ===========================================================================
create view v_headcount_effect
with (security_invoker = on) as
with qual as (
  select id as game_id, headcount
  from v_game_summary
  where response_rate >= 0.40
),
bucketed as (
  select
    q.game_id,
    case
      when q.headcount <= 10 then '≤10'
      when q.headcount <= 13 then '11–13'
      when q.headcount <= 16 then '14–16'
      else '17+'
    end as bucket,
    case
      when q.headcount <= 10 then 1
      when q.headcount <= 13 then 2
      when q.headcount <= 16 then 3
      else 4
    end as bucket_order
  from qual q
)
select
  b.bucket,
  b.bucket_order,
  count(distinct b.game_id) as session_count,
  avg(r.overall)            as mean_rating,
  count(*)                  as n_ratings
from bucketed b
join rating r on r.game_id = b.game_id
group by b.bucket, b.bucket_order
order by b.bucket_order;

comment on view v_headcount_effect is
  'Qualifying games (response_rate >= 0.40) bucketed by headcount, with '
  'session_count, mean rating over ratings in the bucket, and n_ratings.';

-- ===========================================================================
-- v_daytime_effect : which day of week gives the best games?
-- Qualifying games grouped by day-of-week.
-- ===========================================================================
create view v_daytime_effect
with (security_invoker = on) as
with qual as (
  select id as game_id, dow
  from v_game_summary
  where response_rate >= 0.40
)
select
  q.dow::int as dow,
  case q.dow::int
    when 0 then 'Sun'
    when 1 then 'Mon'
    when 2 then 'Tue'
    when 3 then 'Wed'
    when 4 then 'Thu'
    when 5 then 'Fri'
    when 6 then 'Sat'
  end                       as dow_label,
  count(distinct q.game_id) as game_count,
  avg(r.overall)            as mean_rating,
  count(*)                  as n_ratings
from qual q
join rating r on r.game_id = q.game_id
group by q.dow
order by q.dow;

comment on view v_daytime_effect is
  'Qualifying games grouped by day-of-week (0=Sun..6=Sat) with game_count, '
  'mean rating, and n_ratings. Answers which day yields the best games.';

-- ===========================================================================
-- v_player_presence : does a player''s presence lift game quality?
-- Over qualifying games, compares mean game rating when a player is present vs
-- absent, with k=5 shrinkage of the "present" mean toward the global mean.
-- Includes ALL players.
-- ===========================================================================
create view v_player_presence
with (security_invoker = on) as
with qual as (
  select id as game_id, mean_overall
  from v_game_summary
  where response_rate >= 0.40
),
gm as (
  select avg(mean_overall) as global_mean
  from qual
),
per_player as (
  select
    p.id   as player_id,
    p.name as name,
    count(*) filter (where a.id is not null)                as n_with,
    count(*) filter (where a.id is null)                    as n_without,
    avg(q.mean_overall) filter (where a.id is not null)     as mean_with,
    avg(q.mean_overall) filter (where a.id is null)         as mean_without,
    coalesce(sum(q.mean_overall) filter (where a.id is not null), 0) as sum_present
  from player p
  cross join qual q
  left join appearance a
    on a.player_id = p.id and a.game_id = q.game_id
  group by p.id, p.name
)
select
  pp.player_id,
  pp.name,
  pp.n_with                                                    as appearances,
  pp.mean_with,
  pp.mean_without,
  pp.n_with,
  pp.n_without,
  gm.global_mean,
  (pp.sum_present + 5 * gm.global_mean) / (pp.n_with + 5)      as adjusted_with,
  (pp.sum_present + 5 * gm.global_mean) / (pp.n_with + 5)
    - pp.mean_without                                          as delta_adjusted,
  (pp.n_with >= 6)                                             as has_enough_data
from per_player pp
cross join gm
order by delta_adjusted desc nulls last;

comment on view v_player_presence is
  'Per player over qualifying games: mean game rating present vs absent, with '
  'k=5 shrinkage of the present mean toward the global mean. adjusted_with = '
  '(sum_present + 5*global_mean)/(n_with+5); has_enough_data = appearances>=6. '
  'Includes all players (requires at least one qualifying game to populate).';

-- ===========================================================================
-- v_trend : game quality over time with a 4-game rolling average.
-- ===========================================================================
create view v_trend
with (security_invoker = on) as
select
  gs.starts_at,
  gs.mean_overall,
  gs.response_count as n_ratings,
  avg(gs.mean_overall) over (
    order by gs.starts_at
    rows between 3 preceding and current row
  ) as rolling_avg_4
from v_game_summary gs
where gs.response_rate >= 0.40
order by gs.starts_at;

comment on view v_trend is
  'Qualifying games over time: game mean_overall, n_ratings, and a 4-game '
  'rolling average of mean_overall (3 preceding rows + current).';

-- ===========================================================================
-- Grants: no anon access; authenticated only (base-table RLS still applies).
-- ===========================================================================
revoke all on v_game_summary    from anon;
revoke all on v_headcount_effect from anon;
revoke all on v_daytime_effect  from anon;
revoke all on v_player_presence from anon;
revoke all on v_trend           from anon;

grant select on v_game_summary    to authenticated;
grant select on v_headcount_effect to authenticated;
grant select on v_daytime_effect  to authenticated;
grant select on v_player_presence to authenticated;
grant select on v_trend           to authenticated;
