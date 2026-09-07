-- 0002_functions_rls.sql
-- Helper functions (SECURITY DEFINER) and row-level security.

-- ===========================================================================
-- Helper functions
-- ===========================================================================
-- All are SECURITY DEFINER with a pinned search_path so they can read the
-- roster / auth.users regardless of the caller's RLS, without being hijacked
-- by a mutable search_path.

-- current_player_id(): the player.id linked to the current auth user, else null.
create or replace function current_player_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id
  from player p
  where p.user_id = auth.uid()
  limit 1;
$$;

comment on function current_player_id() is
  'The player.id whose user_id = auth.uid(), or null when unlinked/anon.';

-- is_organizer(): true when the current auth user maps to an organizer.
create or replace function is_organizer()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from player p
    where p.user_id = auth.uid()
      and p.role = 'organizer'
  );
$$;

comment on function is_organizer() is
  'True when the current auth user maps to a player with role = organizer.';

-- ensure_player(): called by the web app right after phone-OTP sign-in.
-- Links the auth user to an existing roster row by phone, or creates one.
create or replace function ensure_player(p_name text default null)
returns player
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_raw    text;
  v_digits text;
  v_e164   text;
  v_player player;
begin
  if v_uid is null then
    raise exception 'ensure_player must be called by an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  -- 1) Already linked? Return that row.
  select * into v_player from player where user_id = v_uid limit 1;
  if found then
    return v_player;
  end if;

  -- Read the auth user's phone and normalize to digits / E.164.
  select u.phone into v_raw from auth.users u where u.id = v_uid;
  v_digits := nullif(regexp_replace(coalesce(v_raw, ''), '\D', '', 'g'), '');
  if v_digits is not null then
    v_e164 := '+' || v_digits;
  end if;

  -- 2) Claim an unlinked roster row whose phone matches (compare on digits).
  if v_digits is not null then
    update player p
       set user_id = v_uid,
           name    = coalesce(nullif(p_name, ''), p.name)
     where p.user_id is null
       and regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') = v_digits
       and p.id = (
         select p2.id
         from player p2
         where p2.user_id is null
           and regexp_replace(coalesce(p2.phone, ''), '\D', '', 'g') = v_digits
         order by p2.created_at
         limit 1
       )
    returning * into v_player;
    if found then
      return v_player;
    end if;
  end if;

  -- 3) No match: create a fresh roster row for this auth user.
  insert into player (name, phone, user_id, role)
  values (coalesce(nullif(p_name, ''), 'Player'), v_e164, v_uid, 'player')
  returning * into v_player;

  return v_player;
end;
$$;

comment on function ensure_player(text) is
  'Post phone-OTP: return the caller''s linked player, else claim the unlinked '
  'roster row matching their phone, else create a new player. E.164 stored.';

grant execute on function ensure_player(text) to authenticated;

-- game_roster(): roster / RSVP list for a game, NAMES ONLY (never phone).
-- Every player with an rsvp OR appearance for the game.
create or replace function game_roster(p_game_id uuid)
returns table (
  player_id   uuid,
  name        text,
  rsvp_status text,
  played      boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id                       as player_id,
    p.name                     as name,
    r.status                   as rsvp_status,
    (a.id is not null)         as played
  from player p
  left join rsvp r
    on r.player_id = p.id and r.game_id = p_game_id
  left join appearance a
    on a.player_id = p.id and a.game_id = p_game_id
  where r.id is not null or a.id is not null
  order by p.name;
$$;

comment on function game_roster(uuid) is
  'Names-only roster/RSVP list for a game (phones never exposed). Any signed-in '
  'player may call it. Returns every player with an rsvp OR appearance.';

grant execute on function game_roster(uuid) to authenticated;

-- ===========================================================================
-- Row-level security
-- ===========================================================================
alter table player     enable row level security;
alter table game       enable row level security;
alter table rsvp       enable row level security;
alter table appearance enable row level security;
alter table rating     enable row level security;
alter table sms_log    enable row level security;

-- No policies are created for the anon role: with RLS enabled and no matching
-- policy, anon is denied on every table.

-- --------------------------------------------------------------------------
-- player
-- --------------------------------------------------------------------------
-- Read your own row, or everything if organizer. Non-organizers can only ever
-- read their OWN row, so phones never leak through direct reads.
create policy player_select on player
  for select to authenticated
  using (user_id = auth.uid() or is_organizer());

-- Organizer full write.
create policy player_insert_org on player
  for insert to authenticated
  with check (is_organizer());

create policy player_update_org on player
  for update to authenticated
  using (is_organizer())
  with check (is_organizer());

create policy player_delete_org on player
  for delete to authenticated
  using (is_organizer());

-- A player may update their own row (no column-level restriction per spec).
create policy player_update_self on player
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- --------------------------------------------------------------------------
-- game: all signed-in players can see games; organizer writes.
-- --------------------------------------------------------------------------
create policy game_select on game
  for select to authenticated
  using (true);

create policy game_insert_org on game
  for insert to authenticated
  with check (is_organizer());

create policy game_update_org on game
  for update to authenticated
  using (is_organizer())
  with check (is_organizer());

create policy game_delete_org on game
  for delete to authenticated
  using (is_organizer());

-- --------------------------------------------------------------------------
-- rsvp: a player manages only their own; organizer manages all.
-- --------------------------------------------------------------------------
create policy rsvp_select on rsvp
  for select to authenticated
  using (player_id = current_player_id() or is_organizer());

create policy rsvp_insert on rsvp
  for insert to authenticated
  with check (player_id = current_player_id() or is_organizer());

create policy rsvp_update on rsvp
  for update to authenticated
  using (player_id = current_player_id() or is_organizer())
  with check (player_id = current_player_id() or is_organizer());

create policy rsvp_delete on rsvp
  for delete to authenticated
  using (player_id = current_player_id() or is_organizer());

-- --------------------------------------------------------------------------
-- appearance: read own or organizer; write organizer only.
-- --------------------------------------------------------------------------
create policy appearance_select on appearance
  for select to authenticated
  using (player_id = current_player_id() or is_organizer());

create policy appearance_insert_org on appearance
  for insert to authenticated
  with check (is_organizer());

create policy appearance_update_org on appearance
  for update to authenticated
  using (is_organizer())
  with check (is_organizer());

create policy appearance_delete_org on appearance
  for delete to authenticated
  using (is_organizer());

-- --------------------------------------------------------------------------
-- rating: a rater reads only their own (organizer reads all); a rater writes
-- only their own. The appearance-exists trigger enforces eligibility.
-- --------------------------------------------------------------------------
create policy rating_select on rating
  for select to authenticated
  using (rater_id = current_player_id() or is_organizer());

create policy rating_insert on rating
  for insert to authenticated
  with check (rater_id = current_player_id());

create policy rating_update on rating
  for update to authenticated
  using (rater_id = current_player_id())
  with check (rater_id = current_player_id());

create policy rating_delete on rating
  for delete to authenticated
  using (rater_id = current_player_id() or is_organizer());

-- --------------------------------------------------------------------------
-- sms_log: organizer only, all commands.
-- --------------------------------------------------------------------------
create policy sms_log_select_org on sms_log
  for select to authenticated
  using (is_organizer());

create policy sms_log_insert_org on sms_log
  for insert to authenticated
  with check (is_organizer());

create policy sms_log_update_org on sms_log
  for update to authenticated
  using (is_organizer())
  with check (is_organizer());

create policy sms_log_delete_org on sms_log
  for delete to authenticated
  using (is_organizer());
