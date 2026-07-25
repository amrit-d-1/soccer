-- 0002_rls.sql
-- Row Level Security posture.
--
-- Security model:
--   * The single admin uses Supabase Auth and hits the DB as the `authenticated`
--     role. `authenticated` is granted FULL access to every table.
--   * `anon` is granted NO policies at all. With RLS enabled and no anon policy,
--     the anon key can read/write nothing. The public rating web page never uses
--     the anon key directly against these tables; instead it runs server-side
--     with the service-role key (which bypasses RLS entirely). This keeps the
--     rating-link flow off the client's anon credentials.

alter table player      enable row level security;
alter table session     enable row level security;
alter table appearance  enable row level security;
alter table rating      enable row level security;
alter table rating_link enable row level security;
alter table sms_log     enable row level security;

-- player -------------------------------------------------------------------
drop policy if exists player_authenticated_all on player;
create policy player_authenticated_all on player
  for all to authenticated using (true) with check (true);

-- session ------------------------------------------------------------------
drop policy if exists session_authenticated_all on session;
create policy session_authenticated_all on session
  for all to authenticated using (true) with check (true);

-- appearance ---------------------------------------------------------------
drop policy if exists appearance_authenticated_all on appearance;
create policy appearance_authenticated_all on appearance
  for all to authenticated using (true) with check (true);

-- rating -------------------------------------------------------------------
drop policy if exists rating_authenticated_all on rating;
create policy rating_authenticated_all on rating
  for all to authenticated using (true) with check (true);

-- rating_link --------------------------------------------------------------
drop policy if exists rating_link_authenticated_all on rating_link;
create policy rating_link_authenticated_all on rating_link
  for all to authenticated using (true) with check (true);

-- sms_log ------------------------------------------------------------------
drop policy if exists sms_log_authenticated_all on sms_log;
create policy sms_log_authenticated_all on sms_log
  for all to authenticated using (true) with check (true);
