# Soccer RSVP + Game-Rating — Supabase Backend

Backend for a pickup-soccer app: players sign in by phone, RSVP to games, get
marked present, and rate games they attended across multiple dimensions. An
organizer manages the roster, games, attendance, and SMS blasts, and sees
analytics.

## Data model

| Table        | Purpose |
|--------------|---------|
| `player`     | The **roster**. Rows can exist before anyone signs in (`user_id` null). Phone-OTP sign-in links an auth user to the matching roster row by phone. `role` is `player` or `organizer`. Holds `sms_opt_out`. |
| `game`       | A game: `scheduled` / `played` / `cancelled`, with `starts_at`, `location`, `capacity`, `rsvp_close_at`, `ratings_close_at`. |
| `rsvp`       | A player's `in` / `out` / `maybe` response to a game (one per player per game). |
| `appearance` | A player who actually showed up. **Required to submit a rating.** |
| `rating`     | A rater's rating of a game (`overall` 1-5 required; `speed`, `intensity` 1-5 optional; `comment`). One per rater per game. |
| `sms_log`    | One row per SMS send attempt. |

### Key behaviors (triggers)

- Inserting a `game` with `ratings_close_at` null sets it to `starts_at + 48h`.
- A `rating` insert/update is **rejected unless an `appearance` exists** for
  `(game_id, rater_id)`.

### Helper functions (SECURITY DEFINER)

- `current_player_id()` → the `player.id` for the current auth user, or null.
- `is_organizer()` → whether the current auth user is an organizer.
- `ensure_player(p_name text default null)` → called by the web app right after
  phone-OTP sign-in. Returns the caller's already-linked player; else claims the
  unlinked roster row whose phone matches (compared digits-only, stored E.164),
  updating its name; else creates a new player. Granted to `authenticated`.
- `game_roster(p_game_id uuid)` → names-only roster/RSVP list for a game
  (`player_id`, `name`, `rsvp_status`, `played`). **Never exposes phones**, so any
  signed-in player may call it. Granted to `authenticated`.

### Row-level security (RLS)

RLS is enabled on every table; `anon` has no policies (fully denied).

- **player** — you can read only your own row; organizers read all. Only the
  organizer can insert/delete/update arbitrary rows; a player may update their
  own row. Because non-organizers only ever read their own row, **phones never
  leak** through direct table reads.
- **game** — all signed-in players can read; organizer writes.
- **rsvp** — a player reads/writes only their own; organizer manages all.
- **appearance** — a player reads their own (organizer all); organizer writes.
- **rating** — a rater reads/writes only their own (a rater never sees another
  rater's rating); organizer reads all. Eligibility enforced by the trigger.
- **sms_log** — organizer only.

### Analytics views (organizer-only)

All use `security_invoker = on`, so base-table RLS applies — in practice only an
organizer sees the underlying rows. `anon` is revoked; `authenticated` granted.
A **40% data-quality gate** (`response_rate >= 0.40`) filters the aggregate
views, and each view exposes its sample size.

- `v_game_summary` — one row per game: headcount, rating counts/means,
  `response_rate`, `stddev_overall`, `is_low_response`, `dow`, `hour`.
- `v_headcount_effect` — qualifying games bucketed by headcount
  (`≤10`, `11–13`, `14–16`, `17+`) with `session_count`, `mean_rating`, `n_ratings`.
- `v_daytime_effect` — qualifying games by day-of-week with `mean_rating`.
- `v_player_presence` — per player, mean game rating when present vs absent, with
  **k=5 shrinkage** toward the global mean (`adjusted_with`, `delta_adjusted`,
  `has_enough_data`). Includes all players.
- `v_trend` — qualifying games over time with a 4-game rolling average.

## Applying migrations + seed

Migrations live in `supabase/migrations/` and run in filename order:

```
0001_schema.sql          -- tables, triggers, indexes
0002_functions_rls.sql   -- helper functions + RLS policies
0003_analytics_views.sql -- organizer analytics views
```

With the Supabase CLI, from the repo root:

```bash
supabase db reset          # local: recreates the DB, runs migrations, then seed.sql
# or, against a linked project:
supabase db push           # apply migrations
psql "$DATABASE_URL" -f supabase/seed.sql   # load seed data (optional, dev/demo)
```

`supabase/seed.sql` is deterministic: ~20 roster players (no auth accounts), 10
past `played` games over the last ~10 weeks on varied weekdays/times,
appearances, RSVPs, and ratings. One game is intentionally under 40% response to
exercise `is_low_response`.

## Enabling Phone OTP auth (Twilio)

The app signs users in with a phone one-time password. In the Supabase
dashboard:

1. **Authentication → Providers → Phone** — toggle **Phone** on.
2. Under **SMS provider**, choose **Twilio**.
3. Fill in your Twilio **Account SID**, **Auth Token**, and **Message Service
   SID** (or From number), from the Twilio console.
4. Save. Optionally set the OTP length/expiry under the Phone provider settings.
5. (Recommended) In **Authentication → Rate Limits**, keep SMS send limits sane.

After a user completes phone-OTP sign-in, the web app calls
`ensure_player(name)`, which links their auth user to the matching roster row (by
phone) or creates a new one.

## Becoming the organizer

There is no organizer until you promote one. After **you** sign in for the first
time (so `ensure_player` has created/linked your row), run:

```sql
update player set role = 'organizer' where phone = '<your E.164 phone>';
```

(The same line is included, commented, at the bottom of `seed.sql`.)

## Edge functions

### `send-game-sms` (verify_jwt = true)

`POST { game_id, kind: 'invite' | 'reminder' | 'rate' }`. Invoked by the
organizer app with the user's JWT. Uses a service-role client to build the
recipient set, sends via the configured provider, logs **every** attempt to
`sms_log`, and returns `{ sent, skipped, failed }`.

Recipients:
- `invite` — all active players with a phone.
- `reminder` — players who are `in` or have not RSVP'd yet (excludes `out`/`maybe`).
- `rate` — players with an appearance for the game and no rating yet.

Always skips opted-out or phone-less players.

### `twilio-inbound` (verify_jwt = false)

Public webhook for inbound SMS. On a STOP-family keyword it sets
`sms_opt_out = true` for the matching player and returns empty TwiML. Point your
Twilio number's inbound webhook at this function's URL.

### Function environment variables

Set these with `supabase secrets set KEY=value` (or in the dashboard under
Edge Functions → your function → Secrets):

| Var | Used by | Notes |
|-----|---------|-------|
| `SUPABASE_URL` | both | Provided automatically in the Supabase runtime. |
| `SUPABASE_SERVICE_ROLE_KEY` | both | **Secret.** See warning below. |
| `PUBLIC_APP_BASE_URL` | send-game-sms | Base URL for links in SMS bodies (e.g. `https://app.example.com`). |
| `SMS_PROVIDER` | send-game-sms | `console` (default, logs only — no SMS sent) or `twilio`. |
| `TWILIO_ACCOUNT_SID` | send-game-sms | Required when `SMS_PROVIDER=twilio`. |
| `TWILIO_AUTH_TOKEN` | send-game-sms | Required when `SMS_PROVIDER=twilio`. |
| `TWILIO_FROM_NUMBER` | send-game-sms | Sending number, E.164. |

`SMS_PROVIDER` defaults to **`console`**: the function logs each message and
records it in `sms_log` **without actually sending any SMS**. Set it to `twilio`
only when you want real messages to go out.

## Service-role key warning

`SUPABASE_SERVICE_ROLE_KEY` **bypasses all RLS**. Keep it server-side only:
store it as an Edge Function secret, never ship it to the browser or commit it to
the repo. Anyone with this key has full read/write to every table.
