# Soccer Game — RSVP + game-quality tracker

One web app for a weekly pickup soccer group. You schedule games, players RSVP
from a texted link, everyone gets reminders, and after each game players rate it.
Over time it shows **when** (day, time, headcount) and **with whom** the games
rate best — so you can invite the combinations that produce great games.

The whole thing lives or dies on **response rate**, so every choice — phone-code
login (no passwords), texted links, one-screen rating — is aimed at making it
trivial for a rotating cast to respond every week.

## Architecture

One Next.js app on Vercel serves **both** the organizer and the players. Supabase
is the backend (Postgres + Auth + Edge Functions). Twilio sends the texts — and
also sends the login codes.

| Piece | Tech | Notes |
| --- | --- | --- |
| Web app | Next.js (App Router) on Vercel | Organizer + players, one app. Talks to Postgres as the logged-in user (anon key + JWT); RLS enforces access. |
| Database / Auth | Supabase | Phone-OTP login. `player` roster, `game`, `rsvp`, `appearance`, `rating`, `sms_log`. All stats are Postgres views. |
| SMS | Twilio | Invite / reminder / rate texts + login codes. Provider switch `SMS_PROVIDER` (`console` default, `twilio` when 10DLC clears). |

```
supabase/   Postgres schema, RLS, analytics views, seed, edge functions
web/        the Next.js app (organizer + players)
ios/        SHELVED — the earlier iOS admin app, kept for reference, not used
```

## How it works

**You (organizer):** create a game → pick who to invite from your saved roster →
one tap texts them an RSVP link → watch RSVPs come in → after the game confirm
who actually played → send the "rate it" text → read Insights.

**A player:** get a text → tap the link → sign in once with a phone code (no
password) → RSVP In/Out → after the game, rate Overall / Speed / Intensity in ~10
seconds. Next week they're remembered.

Roster fills itself: text the invite link to your group chat once and each person
enters their own name the first time. You can also add players by hand in `/admin`.
(A browser can't read your phone's contacts — that's why it's self-serve.)

## Data model (Postgres)

- `player` — the roster. Rows can exist before a person ever logs in (organizer
  adds name+phone). On phone-OTP sign-in, `ensure_player()` links the auth user
  to their roster row by phone, or creates one.
- `game` — starts_at, location, capacity, status, `ratings_close_at` (defaults to
  start + 48h).
- `rsvp` — in / out / maybe, one per player per game.
- `appearance` — who actually played (drives the "who was there" analysis).
- `rating` — overall (required), speed, intensity, comment. Valid only if a
  matching appearance exists (enforced by trigger).
- `sms_log` — every text attempt and its result.

**RLS:** a player can read/write only their own RSVP + rating + profile and can
see games; the organizer sees and does everything; `anon` gets nothing. Player
phone numbers are never exposed to other players (`game_roster()` returns names
only). Analytics views apply a **40% response-rate gate** and flag weak games.

## Setup / go-live

1. **Supabase** — create a project. Apply `supabase/migrations/*.sql` in order,
   then `supabase/seed.sql`. Enable **Authentication → Providers → Phone** and
   connect your **Twilio** (this is what sends login codes). Deploy the edge
   functions. Set function env: `PUBLIC_APP_BASE_URL`, `SMS_PROVIDER=console` (for
   now), and the Twilio vars in Edge Functions → Secrets (the **service-role key
   and Twilio Auth Token live only here — never in the web app**).
2. **Web** — `cd web && npm install && npm run dev`. Env (both from Supabase →
   Settings → API): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
   Deploy to Vercel.
3. **Make yourself the organizer** — sign in once, then in Supabase SQL run
   `update player set role='organizer' where phone='<your E.164 phone>';`
4. **Twilio A2P 10DLC** — your `/privacy` and `/terms` pages (live once deployed:
   `https://<your-app>.vercel.app/privacy` and `/terms`) are the URLs to paste
   into the campaign registration.

## SMS is off until 10DLC clears

`SMS_PROVIDER` stays `console` until US A2P 10DLC registration is approved (~1–2
weeks). Until then nothing is texted, but every intended message is logged to
`sms_log`, and `/admin` has a **Copy links** button that dumps a name→link list
you paste into your group chat. Flip to `twilio` when approved — that's the only
change.

## Not built, on purpose

No rating of individual players (rate the game only). No team generation,
payments, or chat. No public leaderboard — player-level stats are organizer-only.
Pair/lineup synergy analysis needs ~40+ games before it's worth attempting.
