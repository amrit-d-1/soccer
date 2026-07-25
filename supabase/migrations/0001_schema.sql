-- 0001_schema.sql
-- Weekly pickup-soccer game-quality tracker: core schema.
-- Postgres + Supabase. Tables are created in dependency order.

-- gen_random_uuid() lives in pgcrypto on some Postgres builds; ensure it exists.
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- player
-- ---------------------------------------------------------------------------
create table if not exists player (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  phone       text,
  contact_id  text,
  is_active   boolean default true,
  sms_opt_out boolean default false,
  created_at  timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- session
-- ---------------------------------------------------------------------------
create table if not exists session (
  id               uuid primary key default gen_random_uuid(),
  played_at        date not null,
  location         text,
  notes            text,
  ratings_close_at timestamptz,
  created_at       timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- appearance  (who showed up to a session; headcount is derived from this)
-- ---------------------------------------------------------------------------
create table if not exists appearance (
  id         uuid primary key default gen_random_uuid(),
  session_id uuid not null references session(id) on delete cascade,
  player_id  uuid not null references player(id),
  unique (session_id, player_id)
);

-- ---------------------------------------------------------------------------
-- rating  (one rating per rater per session; rater must have appeared)
-- ---------------------------------------------------------------------------
create table if not exists rating (
  id         uuid primary key default gen_random_uuid(),
  session_id uuid not null references session(id) on delete cascade,
  rater_id   uuid not null references player(id),
  overall    smallint not null check (overall between 1 and 5),
  balance    smallint check (balance between 1 and 5),
  comment    text,
  created_at timestamptz default now(),
  unique (session_id, rater_id)
);

-- ---------------------------------------------------------------------------
-- rating_link  (per-player magic link token to submit a rating)
-- ---------------------------------------------------------------------------
create table if not exists rating_link (
  token      uuid primary key default gen_random_uuid(),
  session_id uuid not null references session(id) on delete cascade,
  player_id  uuid not null references player(id),
  expires_at timestamptz,
  used_at    timestamptz,
  unique (session_id, player_id)
);

-- ---------------------------------------------------------------------------
-- sms_log  (every outbound/inbound SMS attempt, for auditing/debugging)
-- ---------------------------------------------------------------------------
create table if not exists sms_log (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid references player(id),
  session_id uuid references session(id),
  body       text,
  provider   text,
  ok         boolean,
  error      text,
  created_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- 1) Default ratings_close_at to played_at + 48h when not supplied.
create or replace function set_ratings_close_at()
returns trigger
language plpgsql
as $$
begin
  if new.ratings_close_at is null then
    new.ratings_close_at := (new.played_at::timestamptz + interval '48 hours');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_session_set_ratings_close_at on session;
create trigger trg_session_set_ratings_close_at
  before insert on session
  for each row
  execute function set_ratings_close_at();

-- 2) A rating is valid only if the rater actually appeared in that session.
create or replace function enforce_rating_appearance()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1
    from appearance a
    where a.session_id = new.session_id
      and a.player_id  = new.rater_id
  ) then
    raise exception
      'rater % has no appearance in session % — cannot submit a rating',
      new.rater_id, new.session_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_rating_require_appearance on rating;
create trigger trg_rating_require_appearance
  before insert or update on rating
  for each row
  execute function enforce_rating_appearance();

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index if not exists idx_appearance_session on appearance (session_id);
create index if not exists idx_appearance_player  on appearance (player_id);   -- most-recent-appearance sorting
create index if not exists idx_rating_session     on rating (session_id);
create index if not exists idx_rating_link_session on rating_link (session_id);
