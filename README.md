# SoccerLog — weekly pickup-soccer game-quality tracker

Find out which roster compositions produce good games. Every week, capture two
things reliably: **who played**, and **how everyone felt it went**. Then look at
the aggregate signal — headcount effect, who-was-there deltas, disagreement,
trend.

## Architecture: two clients, one database

The split is deliberate.

| Client | Who | What | How it reaches the DB |
| --- | --- | --- | --- |
| **iOS app** (`ios/`) | Admin only — me | Create sessions, import contacts, send rating requests, view analytics | Supabase `authenticated` role (my single account), anon key in-app |
| **Rating web page** (`web/`) | Everyone else | Rate the game from an SMS magic link — no install, no account, no login | Server-side only, service-role key, keyed by token |

The iOS app is installed from Xcode onto my own device — never distributed. The
players never install anything. **Response rate is the whole product**, so we do
not ask a rotating cast of 25+ people to install an app to answer one question.

Backend is Supabase (Postgres + Auth + Edge Functions). SMS via Twilio, called
from an edge function. All statistics live in Postgres views — the clients do no
math.

## What's in the box

```
supabase/     Postgres schema, RLS, analytics views, seed data, edge functions
web/          Next.js single-route rating page  (/r/[token])
ios/          SwiftUI admin app (XcodeGen project)
```

Each directory has its own README with setup detail. Quick tour:

### `supabase/`
- `migrations/0001_schema.sql` — the six tables. Headcount is **derived** (count
  `appearance` rows), never stored. Triggers: `ratings_close_at` defaults to
  `played_at + 48h`; a rating is rejected unless a matching `appearance` exists.
- `migrations/0002_rls.sql` — RLS on every table. `authenticated` (me) gets full
  access; `anon` gets **no** policy, so the anon key can read/write nothing.
- `migrations/0003_analytics_views.sql` — all analytics as views, each exposing
  its sample size. Sessions below **40%** response rate are excluded from every
  aggregate and flagged (not hidden) in the session list. Views use
  `security_invoker` and are revoked from `anon`.
- `seed.sql` — 25 players, 10 Friday sessions with ratings, so Insights renders
  from day one. One session is intentionally sub-40% to exercise the flag.
- `functions/send-rating-requests/` — SMS sender. Provider switch on
  `SMS_PROVIDER` (`console` default, `twilio` for real sends). Logs every attempt
  to `sms_log`.
- `functions/twilio-inbound/` — inbound STOP handler; sets `sms_opt_out = true`.

### `web/`
Server-rendered `/r/[token]`. Q1 (required, 1–5 "Bad"…"Great"), Q2 (optional,
teams even?), Q3 (optional comment). Fits one phone screen, one-handed. A rater
**never** sees anyone else's answer. Re-opening the link edits their answer until
`ratings_close_at`, then read-only. Expired/invalid tokens get a friendly page.
The service-role key is server-only and never shipped to the browser.

### `ios/`
SwiftUI, iOS 17+, `supabase-swift`. Screens: **Sessions** (root list with
headcount / mean / response rate, low-response flag), **New session** (sub-60s
player picker: search, recency sort, pinned selections with a live count, inline
add-player; works **offline** by queuing writes and syncing when signal returns),
**Session detail** (stats, 1–5 distribution chart, comments, non-responders,
Send requests / Send reminder / Copy links), **Roster** (appearance counts, add /
edit / deactivate / opt-out, Contacts import with a dedupe-confirm screen),
**Insights** (the four analytics), **Settings** (weekly reminder day/time, sign
out). Warm cream `#FAF7F2`, amber `#C45621`, monospaced stats.

## Setup

### 1. Backend (Supabase)
```bash
supabase db push          # or run migrations/*.sql in order, then seed.sql
supabase functions deploy send-rating-requests
supabase functions deploy twilio-inbound
```
Set function env vars (see `supabase/README.md`): `PUBLIC_RATING_BASE_URL`,
`SMS_PROVIDER` (leave at `console` for now), and Twilio creds when ready.
The **service-role key lives only here and in Vercel** — never in the iOS app.

### 2. Web (Vercel)
```bash
cd web && npm install && npm run dev
```
Env: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (both server-only). Deploy to
Vercel; use that URL as `PUBLIC_RATING_BASE_URL` (edge function) and
`RATING_BASE_URL` (iOS `Copy links`).

### 3. iOS
```bash
cd ios
cp Secrets.xcconfig.example Secrets.xcconfig     # fill in URL, anon key, rating base URL
xcodegen generate
xcodebuild -scheme SoccerLog -destination 'platform=iOS Simulator,name=iPhone 15' build
```
Create your single admin user in Supabase Auth and sign in on first launch.

> **Build note:** the Swift code was authored in a Linux CI environment without
> Xcode, so it has **not** been compiled here. Run the `xcodebuild` step above on
> a Mac (and `xcodegen generate` first) to produce the project and verify. The
> `.xcodeproj` is gitignored on purpose — `project.yml` is the source of truth.

## SMS is off until 10DLC clears

US A2P 10DLC registration is pending (a week or two). Until then `SMS_PROVIDER`
stays `console`: nothing is texted, but every intended message is logged to
`sms_log`. The app is **fully usable** via **Copy links** — paste the
name-and-link list into the group chat by hand. When registration clears, flip
`SMS_PROVIDER=twilio`; that is the only change needed.

## Ship status

Steps **1–9 of the build order are implemented** (schema/RLS/seed, iOS scaffold +
auth, roster + contacts import, fast new-session flow with offline queue, rating
web page + token generation, session detail, the console edge function, insights,
local notifications). Step **10 (real Twilio sends)** is wired in the edge
function behind `SMS_PROVIDER=twilio` and ready to enable once 10DLC clears. You
can run this Friday and paste links by hand.

## Not built, on purpose

No player accounts/auth for raters (magic-link token only). No rating of
individual players — people rate the game, never each other. No RSVP, scheduling,
payments, chat, team generation, or A/B team tracking. No public leaderboard. No
App Store submission.

## A note on pair / lineup synergy

Deliberately **not** in v1. "Which specific combinations of players produce good
games" needs far more data than the presence-delta analysis — realistically
**~40+ sessions** before the sample can support pair/lineup synergy without
overfitting noise. Revisit once the session count gets there.
