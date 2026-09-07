# Soccer Game — Web App

One Next.js (App Router) app for **both** the organizer and players of a pickup
soccer group. Players RSVP to games and rate the ones they played; the organizer
schedules games, manages the roster, confirms attendance, triggers SMS, and
views insights.

- **Auth:** Supabase **phone OTP** (SMS one-time code, no passwords).
- **Data access:** the app talks to Postgres as the **logged-in user** (anon key
  + user JWT). **Row-Level Security** enforces who can read/write what. There is
  **no service-role key** in this app — privileged work lives in Supabase edge
  functions.
- **Charts:** Recharts (on `/insights`).

## Environment variables

Copy `.env.example` to `.env.local` and fill in:

| Variable | What |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Your Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Your Supabase anon (public) key |

Both are public and safe to ship to the browser. **Do not** add a service-role
key here.

## Supabase setup (required)

**Phone OTP must be enabled in the Supabase dashboard** for sign-in to work:
Dashboard → **Authentication → Providers → Phone** → enable it and configure an
SMS provider (e.g. Twilio). Without this, `signInWithOtp`/`verifyOtp` will fail.

This app depends on the backend contract (built separately): tables `player`,
`game`, `rsvp`, `appearance`, `rating`, `sms_log`; RPCs `ensure_player`,
`game_roster`; views `v_game_summary`, `v_headcount_effect`, `v_daytime_effect`,
`v_player_presence`, `v_trend`; the `send-game-sms` edge function; and RLS
policies. Make sure those migrations/functions are deployed.

## Local development

```bash
npm install
npm run dev
```

Open http://localhost:3000 — you'll be redirected to `/login`.

## Build

```bash
npm run build
npm run start
```

## Deploy (Vercel)

1. Import the repo into Vercel; set the project **root directory** to `web/`.
2. Add the two `NEXT_PUBLIC_*` environment variables in Vercel project settings.
3. Deploy. Middleware refreshes the Supabase session on every request.

## Routes

- `/login` — phone OTP sign-in (supports `?next=` so texted links land right).
- `/` — home: your next game with In/Out/Maybe, and recent games to rate.
- `/game/[id]` — game details + your RSVP + roster (where invite links land).
- `/rate/[gameId]` — rate a game you played (Overall required; Speed, Intensity
  optional; one-line comment). Editable until ratings close.
- `/admin` — organizer only: create/edit games, roster management, per-game SMS,
  copy-links, and post-game attendance confirm.
- `/insights` — organizer only: charts from the analytics views.
- `/privacy`, `/terms` — static policy pages.

## Twilio A2P / 10DLC

The public policy URLs to paste into your Twilio A2P registration are:

- Privacy: `https://YOUR_DOMAIN/privacy`
- Terms: `https://YOUR_DOMAIN/terms`

Both are linked from the login page footer. Before Twilio/10DLC clears, use the
**Copy links** button in `/admin` to paste per-player game/rate links into a
group chat.
