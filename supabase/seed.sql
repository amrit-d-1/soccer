-- seed.sql
-- Deterministic, idempotent-ish seed data for local/dev use.
-- Runnable top-to-bottom. Re-running is safe: rows use explicit deterministic
-- ids (players/sessions) or natural unique keys (appearance/rating/rating_link)
-- with ON CONFLICT DO NOTHING.
--
-- Deterministic id scheme (no randomness needed):
--   player  i in 1..25 -> '00000000-0000-0000-0000-<hex(i) padded to 12>'
--   session j in 1..10 -> '00000000-0000-0000-0001-<hex(j) padded to 12>'
--
-- Insert order: players -> sessions -> appearances -> rating_link -> ratings.
-- Appearances are inserted BEFORE ratings so the rating->appearance trigger passes.

begin;

-- ---------------------------------------------------------------------------
-- 25 players  (~20 with +1 E.164 phones, 5 without, 2 opted out)
-- ---------------------------------------------------------------------------
insert into player (id, name, phone, sms_opt_out, is_active)
select
  ('00000000-0000-0000-0000-' || lpad(to_hex(v.i), 12, '0'))::uuid,
  v.name, v.phone, v.opt_out, true
from (values
  (1,  'Alex',    '+15550100101', false),
  (2,  'Ben',     '+15550100102', false),
  (3,  'Carlos',  '+15550100103', false),
  (4,  'David',   '+15550100104', false),
  (5,  'Ethan',   '+15550100105', false),
  (6,  'Farid',   '+15550100106', true),   -- opted out
  (7,  'George',  '+15550100107', false),
  (8,  'Hassan',  '+15550100108', false),
  (9,  'Ivan',    '+15550100109', false),
  (10, 'Jack',    '+15550100110', false),
  (11, 'Kevin',   '+15550100111', false),
  (12, 'Liam',    '+15550100112', false),
  (13, 'Marco',   '+15550100113', false),
  (14, 'Nate',    '+15550100114', false),
  (15, 'Omar',    '+15550100115', true),   -- opted out
  (16, 'Paul',    '+15550100116', false),
  (17, 'Quentin', '+15550100117', false),
  (18, 'Raj',     '+15550100118', false),
  (19, 'Sam',     '+15550100119', false),
  (20, 'Tom',     '+15550100120', false),
  (21, 'Umar',    null,           false),
  (22, 'Victor',  null,           false),
  (23, 'Will',    null,           false),
  (24, 'Xavier',  null,           false),
  (25, 'Yusuf',   null,           false)
) as v(i, name, phone, opt_out)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 10 sessions across the last ~10 Fridays (relative to 2026-07-24).
-- ratings_close_at is intentionally omitted -> BEFORE INSERT trigger sets it
-- to played_at + 48h.
-- ---------------------------------------------------------------------------
insert into session (id, played_at, location, notes)
select
  ('00000000-0000-0000-0001-' || lpad(to_hex(j), 12, '0'))::uuid,
  date '2026-07-24' - (10 - j) * 7,
  'Riverside Park — Pitch ' || ((j % 2) + 1),
  case when j = 4 then 'Rainy evening; light turnout on ratings' else null end
from generate_series(1, 10) as j
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Appearances: 12–18 players per session.
-- For session j, players are ranked by ((i*3 + j*7) % 25) ascending and the
-- first `hc` are marked present. Deterministic and gives varied rosters.
-- ---------------------------------------------------------------------------
insert into appearance (session_id, player_id)
select
  ('00000000-0000-0000-0001-' || lpad(to_hex(sj.j), 12, '0'))::uuid,
  pl.id
from (values
  (1, 12), (2, 18), (3, 14), (4, 16), (5, 13),
  (6, 17), (7, 15), (8, 12), (9, 18), (10, 14)
) as sj(j, hc)
join lateral (
  select ('00000000-0000-0000-0000-' || lpad(to_hex(gs.i), 12, '0'))::uuid as id
  from generate_series(1, 25) as gs(i)
  order by ((gs.i * 3 + sj.j * 7) % 25)
  limit sj.hc
) pl on true
on conflict (session_id, player_id) do nothing;

-- ---------------------------------------------------------------------------
-- Rating links: one per appearer per session (what the SMS function would send).
-- token defaults to gen_random_uuid(); expires_at = played_at + 48h.
-- ---------------------------------------------------------------------------
insert into rating_link (session_id, player_id, expires_at)
select
  ('00000000-0000-0000-0001-' || lpad(to_hex(sj.j), 12, '0'))::uuid,
  pl.id,
  ((date '2026-07-24' - (10 - sj.j) * 7)::timestamptz + interval '48 hours')
from (values
  (1, 12), (2, 18), (3, 14), (4, 16), (5, 13),
  (6, 17), (7, 15), (8, 12), (9, 18), (10, 14)
) as sj(j, hc)
join lateral (
  select ('00000000-0000-0000-0000-' || lpad(to_hex(gs.i), 12, '0'))::uuid as id
  from generate_series(1, 25) as gs(i)
  order by ((gs.i * 3 + sj.j * 7) % 25)
  limit sj.hc
) pl on true
on conflict (session_id, player_id) do nothing;

-- ---------------------------------------------------------------------------
-- Ratings: the first `rc` appearers of each session submit a rating.
-- Because raters are drawn from the same ranked appearance set, every rater has
-- a matching appearance row (satisfies the rating->appearance trigger).
--
-- overall is weighted toward 3–4 (with occasional 2/5 and rare 1).
-- Response rates: mostly 65–80%, EXCEPT session 4 = 5/16 = 31% (< 40%) to
-- exercise the low-response flag / data-quality gate.
-- ---------------------------------------------------------------------------
insert into rating (session_id, rater_id, overall, balance, comment)
select
  ('00000000-0000-0000-0001-' || lpad(to_hex(sj.j), 12, '0'))::uuid,
  pl.id,
  case (pl.i + sj.j * 2) % 10
    when 0 then 3 when 1 then 4 when 2 then 3 when 3 then 4 when 4 then 4
    when 5 then 3 when 6 then 5 when 7 then 2 when 8 then 4 else 1
  end,
  case when (pl.i + sj.j) % 2 = 0 then ((pl.i * 3 + sj.j) % 5) + 1 else null end,
  case when (pl.i * sj.j) % 6 = 0
    then (array['Great game','Even teams','Bit lopsided','Good runs','Short-handed today','Fun match'])[((pl.i + sj.j) % 6) + 1]
    else null
  end
from (values
  (1, 8), (2, 13), (3, 10), (4, 5), (5, 9),
  (6, 12), (7, 11), (8, 8), (9, 14), (10, 10)
) as sj(j, rc)
join lateral (
  select
    ('00000000-0000-0000-0000-' || lpad(to_hex(gs.i), 12, '0'))::uuid as id,
    gs.i
  from generate_series(1, 25) as gs(i)
  order by ((gs.i * 3 + sj.j * 7) % 25)
  limit sj.rc
) pl on true
on conflict (session_id, rater_id) do nothing;

commit;
