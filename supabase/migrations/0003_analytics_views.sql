-- 0003_analytics_views.sql
-- All statistics live in Postgres VIEWS. The client renders these verbatim and
-- performs NO math of its own. Every view exposes sample sizes.
--
-- Data-quality gate: aggregate views (#2-#5) EXCLUDE sessions whose response
-- rate is below 40% (too few raters to trust the mean). v_session_summary keeps
-- every session but flags the weak ones via is_low_response.

-- ---------------------------------------------------------------------------
-- 1) v_session_summary  — one row per session. Drives the Sessions list.
--    headcount is DERIVED from appearance rows (never stored).
--    stddev_overall uses stddev_samp -> null when fewer than 2 ratings.
-- ---------------------------------------------------------------------------
create or replace view v_session_summary as
with hc as (
  select session_id, count(*) as headcount
  from appearance
  group by session_id
),
r as (
  select
    session_id,
    count(*)                 as response_count,
    avg(overall)::numeric    as mean_overall,
    stddev_samp(overall)     as stddev_overall,   -- null when < 2 ratings
    avg(balance)::numeric    as mean_balance
  from rating
  group by session_id
)
select
  s.id,
  s.played_at,
  s.location,
  s.notes,
  s.ratings_close_at,
  coalesce(hc.headcount, 0)      as headcount,
  coalesce(r.response_count, 0)  as response_count,
  (coalesce(r.response_count, 0)::numeric / nullif(hc.headcount, 0)) as response_rate,
  r.mean_overall,
  r.stddev_overall,
  r.mean_balance,
  ((coalesce(r.response_count, 0)::numeric / nullif(hc.headcount, 0)) < 0.40) as is_low_response
from session s
left join hc on hc.session_id = s.id
left join r  on r.session_id  = s.id;

comment on view v_session_summary is
  'One row per session with derived headcount, response rate, and rating stats. '
  'Keeps low-response sessions but flags them via is_low_response (response_rate < 0.40).';

-- ---------------------------------------------------------------------------
-- 2) v_headcount_effect  — does turnout affect perceived game quality?
--    Buckets QUALIFYING sessions (response_rate >= 0.40) by headcount.
-- ---------------------------------------------------------------------------
create or replace view v_headcount_effect as
with q as (
  select id as session_id, headcount
  from v_session_summary
  where response_rate >= 0.40
),
bucketed as (
  select
    q.session_id,
    case
      when q.headcount <= 10 then '≤10'
      when q.headcount between 11 and 13 then '11–13'
      when q.headcount between 14 and 16 then '14–16'
      else '17+'
    end as bucket,
    case
      when q.headcount <= 10 then 1
      when q.headcount between 11 and 13 then 2
      when q.headcount between 14 and 16 then 3
      else 4
    end as bucket_order
  from q
)
select
  b.bucket,
  b.bucket_order,
  count(distinct b.session_id) as session_count,
  avg(rt.overall)::numeric     as mean_rating,
  count(rt.id)                 as n_ratings
from bucketed b
join rating rt on rt.session_id = b.session_id
group by b.bucket, b.bucket_order
order by b.bucket_order;

comment on view v_headcount_effect is
  'Qualifying sessions (response_rate >= 0.40) bucketed by headcount, with mean '
  'raw rating and n_ratings per bucket. Buckets: ≤10 / 11–13 / 14–16 / 17+.';

-- ---------------------------------------------------------------------------
-- 3) v_player_presence  — is the game better/worse when a given player shows up?
--    Compares session mean_overall for sessions the player appeared in vs not,
--    over QUALIFYING sessions only. adjusted_with applies shrinkage toward the
--    global mean with pseudo-count k = 5. Includes ALL players (client splits on
--    has_enough_data = appearances >= 6).
-- ---------------------------------------------------------------------------
create or replace view v_player_presence as
with q as (
  select id as session_id, mean_overall
  from v_session_summary
  where response_rate >= 0.40
    and mean_overall is not null
),
g as (
  select avg(mean_overall) as global_mean
  from q
),
per as (
  select
    p.id   as player_id,
    p.name as name,
    count(*) filter (where ap.player_id is not null) as n_with,
    count(*) filter (where ap.player_id is null)     as n_without,
    avg(q.mean_overall) filter (where ap.player_id is not null) as mean_with,
    avg(q.mean_overall) filter (where ap.player_id is null)     as mean_without,
    sum(q.mean_overall) filter (where ap.player_id is not null) as sum_with
  from player p
  cross join q
  left join appearance ap
    on ap.session_id = q.session_id
   and ap.player_id  = p.id
  group by p.id, p.name
)
select
  per.player_id,
  per.name,
  per.n_with                              as appearances,
  per.mean_with,
  per.mean_without,
  per.n_with,
  per.n_without,
  g.global_mean,
  ((coalesce(per.sum_with, 0) + 5 * g.global_mean) / (per.n_with + 5)) as adjusted_with,
  (((coalesce(per.sum_with, 0) + 5 * g.global_mean) / (per.n_with + 5)) - per.mean_without) as delta_adjusted,
  (per.n_with >= 6) as has_enough_data
from per
cross join g;

comment on view v_player_presence is
  'Per player: mean session quality when present vs absent over qualifying '
  'sessions. adjusted_with = (sum_session_means_present + k*global_mean)/(n_with + k) '
  'with k = 5 (shrinkage toward the global mean). has_enough_data = appearances >= 6.';

-- Convenience splits (client can also derive these from has_enough_data).
create or replace view v_player_presence_qualified as
  select * from v_player_presence where has_enough_data;

comment on view v_player_presence_qualified is
  'v_player_presence rows with appearances >= 6 (enough data to trust delta).';

create or replace view v_player_presence_insufficient as
  select * from v_player_presence where not has_enough_data;

comment on view v_player_presence_insufficient is
  'v_player_presence rows with appearances < 6 (insufficient data).';

-- ---------------------------------------------------------------------------
-- 4) v_disagreement  — do raters disagree more in unbalanced games?
--    One row per QUALIFYING session; client plots stddev_overall vs mean_balance.
-- ---------------------------------------------------------------------------
create or replace view v_disagreement as
select
  vs.id          as session_id,
  vs.played_at,
  vs.stddev_overall,
  vs.mean_balance,
  vs.response_count as n_ratings
from v_session_summary vs
where vs.response_rate >= 0.40;

comment on view v_disagreement is
  'Qualifying sessions with rating disagreement (stddev_overall) vs mean_balance. '
  'stddev_overall is null when a session has < 2 ratings.';

-- ---------------------------------------------------------------------------
-- 5) v_trend  — game quality over time with a 4-session rolling average.
--    QUALIFYING sessions ordered by played_at.
-- ---------------------------------------------------------------------------
create or replace view v_trend as
select
  vs.played_at,
  vs.mean_overall,
  vs.response_count as n_ratings,
  avg(vs.mean_overall) over (
    order by vs.played_at
    rows between 3 preceding and current row
  ) as rolling_avg_4
from v_session_summary vs
where vs.response_rate >= 0.40
order by vs.played_at;

comment on view v_trend is
  'Qualifying sessions over time: mean_overall plus rolling_avg_4 (avg over the '
  'current and 3 preceding qualifying sessions by played_at).';

-- ---------------------------------------------------------------------------
-- Hardening: make views honor the base tables' RLS and keep anon locked out.
--
-- By default a Postgres view runs with the view owner's privileges and does NOT
-- enforce RLS on its underlying tables. Supabase's default grants also hand
-- `anon`/`authenticated` SELECT on new objects in `public`. Setting
-- security_invoker = on makes each view evaluate base-table RLS as the querying
-- role, so `anon` (which has no table policy) sees nothing. We also revoke anon
-- explicitly and grant only `authenticated`, belt-and-suspenders.
-- Requires Postgres 15+ (Supabase). Safe to re-run.
-- ---------------------------------------------------------------------------
do $$
declare v text;
begin
  foreach v in array array[
    'v_session_summary',
    'v_headcount_effect',
    'v_player_presence',
    'v_player_presence_qualified',
    'v_player_presence_insufficient',
    'v_disagreement',
    'v_trend'
  ] loop
    execute format('alter view %I set (security_invoker = on);', v);
    execute format('revoke all on %I from anon;', v);
    execute format('grant select on %I to authenticated;', v);
  end loop;
end $$;
