-- 0001_schema.sql
-- Soccer RSVP + game-rating app: core schema.
--
-- Data model:
--   player      - the ROSTER. Organizer can pre-create players (name + phone)
--                 who have no auth account yet (user_id null). On phone-OTP
--                 sign-in, the auth user is linked to the matching roster row
--                 by phone (see ensure_player in 0002).
--   game        - a scheduled/played/cancelled soccer game.
--   rsvp        - a player's in/out/maybe response to a game.
--   appearance  - a player who actually showed up (drives eligibility to rate).
--   rating      - a rater's multi-dimension rating of a game they appeared in.
--   sms_log     - a record of every SMS send attempt.

-- gen_random_uuid() lives in pgcrypto (available by default on Supabase).
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- player: the roster
-- ---------------------------------------------------------------------------
create table player (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  phone       text unique,
  user_id     uuid unique references auth.users(id) on delete set null,
  role        text not null default 'player' check (role in ('player','organizer')),
  is_active   boolean not null default true,
  sms_opt_out boolean not null default false,
  created_at  timestamptz default now()
);

comment on table player is
  'Roster of players. Rows may exist with user_id null (pre-created by organizer). '
  'Phones are private: only the owner and organizers can read a player row (see RLS).';

-- ---------------------------------------------------------------------------
-- game
-- ---------------------------------------------------------------------------
create table game (
  id               uuid primary key default gen_random_uuid(),
  starts_at        timestamptz not null,
  location         text,
  capacity         int,
  status           text not null default 'scheduled'
                     check (status in ('scheduled','played','cancelled')),
  notes            text,
  rsvp_close_at    timestamptz,
  ratings_close_at timestamptz,
  created_at       timestamptz default now()
);

comment on table game is 'A soccer game (scheduled/played/cancelled).';

-- When ratings_close_at is not supplied on insert, default it to 48h after start.
create or replace function set_default_ratings_close_at()
returns trigger
language plpgsql
as $$
begin
  if new.ratings_close_at is null then
    new.ratings_close_at := new.starts_at + interval '48 hours';
  end if;
  return new;
end;
$$;

create trigger trg_game_default_ratings_close
  before insert on game
  for each row
  execute function set_default_ratings_close_at();

-- ---------------------------------------------------------------------------
-- rsvp
-- ---------------------------------------------------------------------------
create table rsvp (
  id           uuid primary key default gen_random_uuid(),
  game_id      uuid not null references game(id) on delete cascade,
  player_id    uuid not null references player(id) on delete cascade,
  status       text not null check (status in ('in','out','maybe')),
  responded_at timestamptz default now(),
  unique (game_id, player_id)
);

comment on table rsvp is 'A player''s in/out/maybe response to a game.';

-- ---------------------------------------------------------------------------
-- appearance
-- ---------------------------------------------------------------------------
create table appearance (
  id        uuid primary key default gen_random_uuid(),
  game_id   uuid not null references game(id) on delete cascade,
  player_id uuid not null references player(id) on delete cascade,
  unique (game_id, player_id)
);

comment on table appearance is
  'A player who actually attended a game. Presence here is required to submit a rating.';

-- ---------------------------------------------------------------------------
-- rating
-- ---------------------------------------------------------------------------
create table rating (
  id         uuid primary key default gen_random_uuid(),
  game_id    uuid not null references game(id) on delete cascade,
  rater_id   uuid not null references player(id) on delete cascade,
  overall    smallint not null check (overall between 1 and 5),
  speed      smallint check (speed between 1 and 5),
  intensity  smallint check (intensity between 1 and 5),
  comment    text,
  created_at timestamptz default now(),
  unique (game_id, rater_id)
);

comment on table rating is
  'A rater''s rating of a game they appeared in (enforced by trigger below).';

-- Reject a rating unless the rater has an appearance for that game.
create or replace function enforce_rating_appearance()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from appearance a
    where a.game_id = new.game_id
      and a.player_id = new.rater_id
  ) then
    raise exception
      'rater % has no appearance for game % and cannot submit a rating',
      new.rater_id, new.game_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger trg_rating_requires_appearance
  before insert or update on rating
  for each row
  execute function enforce_rating_appearance();

-- ---------------------------------------------------------------------------
-- sms_log
-- ---------------------------------------------------------------------------
create table sms_log (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid references player(id),
  game_id    uuid references game(id),
  kind       text check (kind in ('invite','reminder','rate')),
  body       text,
  provider   text,
  ok         boolean,
  error      text,
  created_at timestamptz default now()
);

comment on table sms_log is 'One row per SMS send attempt (success or failure).';

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index idx_rsvp_game_id        on rsvp (game_id);
create index idx_appearance_game_id  on appearance (game_id);
create index idx_appearance_player_id on appearance (player_id);
create index idx_rating_game_id      on rating (game_id);
create index idx_player_phone        on player (phone);
create index idx_player_user_id      on player (user_id);
