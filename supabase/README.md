# Soccer — Supabase backend

Backend for a weekly pickup-soccer game-quality tracker: Postgres schema +
analytics views, RLS, seed data, and two Deno Edge Functions.

## Layout

```
supabase/
  migrations/
    0001_schema.sql          -- tables, triggers, indexes
    0002_rls.sql             -- RLS: authenticated = full access, anon = none
    0003_analytics_views.sql -- all stats live in views (client does no math)
  seed.sql                   -- deterministic dev data (25 players, 10 sessions)
  functions/
    send-rating-requests/    -- outbound rating-request SMS
    twilio-inbound/          -- inbound STOP-keyword webhook
  config.toml
```

## Applying migrations

With the Supabase CLI (linked project):

```bash
supabase db push          # applies migrations/ in order
psql "$DATABASE_URL" -f supabase/seed.sql   # optional: load dev data
```

Or apply by hand against any Postgres/Supabase database:

```bash
psql "$DATABASE_URL" -f supabase/migrations/0001_schema.sql
psql "$DATABASE_URL" -f supabase/migrations/0002_rls.sql
psql "$DATABASE_URL" -f supabase/migrations/0003_analytics_views.sql
psql "$DATABASE_URL" -f supabase/seed.sql
```

The seed is idempotent-ish: players/sessions use deterministic ids and
appearances/ratings/links use natural unique keys, all with
`ON CONFLICT DO NOTHING`, so re-running does not duplicate rows.

## Data model notes

- **Headcount is derived** — always `count(appearance)`, never stored.
- **`ratings_close_at`** defaults to `played_at + 48h` via a BEFORE INSERT
  trigger on `session` when left null.
- **Ratings require an appearance** — a BEFORE INSERT/UPDATE trigger on `rating`
  rejects any rating whose `(session_id, rater_id)` has no matching appearance.
- **All statistics live in views** (`v_session_summary`, `v_headcount_effect`,
  `v_player_presence`, `v_disagreement`, `v_trend`). The client renders them and
  does no math. Aggregate views exclude low-response sessions
  (`response_rate < 0.40`); `v_session_summary` keeps them but flags
  `is_low_response`.

## Running functions locally

```bash
supabase functions serve send-rating-requests --env-file supabase/.env.local
supabase functions serve twilio-inbound       --env-file supabase/.env.local
```

Invoke `send-rating-requests` (requires a JWT — `verify_jwt = true`):

```bash
curl -X POST http://localhost:54321/functions/v1/send-rating-requests \
  -H "Authorization: Bearer <SUPABASE_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"session_id":"<uuid>","mode":"initial"}'
```

`twilio-inbound` is public (`verify_jwt = false`) and expects Twilio's
`application/x-www-form-urlencoded` POST (`Body`, `From`).

## Required environment variables

### `send-rating-requests`

| Var | Required | Purpose |
| --- | --- | --- |
| `SUPABASE_URL` | yes | Service-role client target |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | Service-role key (bypasses RLS) |
| `PUBLIC_RATING_BASE_URL` | yes | Base for links: `${BASE}/r/${token}` |
| `SMS_PROVIDER` | no (default `console`) | `console` or `twilio` |
| `TWILIO_ACCOUNT_SID` | if `twilio` | Twilio auth |
| `TWILIO_AUTH_TOKEN` | if `twilio` | Twilio auth |
| `TWILIO_FROM_NUMBER` | if `twilio` | Sending number (E.164) |

### `twilio-inbound`

| Var | Required | Purpose |
| --- | --- | --- |
| `SUPABASE_URL` | yes | Service-role client target |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | Service-role key |

## SMS provider posture

`SMS_PROVIDER` defaults to **`console`** — the function logs the message and the
`sms_log` row but sends nothing. This is the intended state until A2P 10DLC
registration clears. The app stays **fully usable** in the meantime via
**Copy Links**: `send-rating-requests` still generates one `rating_link` per
player, and the admin can copy/share those links manually. Flip
`SMS_PROVIDER=twilio` (with the Twilio vars set) once registration is approved.

## Security

- **RLS:** `authenticated` (the single admin) has full access to every table;
  `anon` has **no policies** and therefore no access. The public rating page runs
  server-side with the **service-role key** — the anon key is never used against
  these tables directly.
- **The service-role key must never reach the iOS app.** It lives only in Edge
  Function / server env. The app authenticates as the admin user and calls
  functions with the user's JWT.
