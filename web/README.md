# Soccer rating web page

Player-facing, magic-link rating page for the weekly pickup-soccer
game-quality tracker. Next.js (App Router) + TypeScript, deployed to Vercel.

There is **no login and no player accounts**. Access is by per-player magic-link
token only: `https://<host>/r/<token>`. Each token maps to one player + one
session via the `rating_link` table.

## How it works

- Single server-rendered route: `app/r/[token]/page.tsx`.
- The page (and its Server Action) reach Postgres **only** through the Supabase
  **service-role** key, held server-side in `lib/supabase-admin.ts`
  (`import 'server-only'` guarantees it never enters a client bundle).
- The browser never talks to Supabase. There is no anon key in this app; the
  `anon` role has zero DB access by design (see `supabase/migrations/0002_rls.sql`).
- The token is fully re-validated inside the Server Action, so submits are safe
  regardless of what the page rendered. `session_id` and `rater_id` are always
  derived from the token server-side — never trusted from the client.

### Flow

1. Look up `rating_link` by token. Missing or expired → friendly "link expired"
   screen (HTTP 200, warm styling — not an error page).
2. Load the session (date, location) and the roster (`appearance` → `player`
   names) so the rater knows which game this is.
3. Editable while `now < session.ratings_close_at`; read-only after.
4. Pre-fill the form from this rater's own existing rating only. No averages,
   counts, or anyone else's answers are ever loaded or shown.

### The form (one phone screen, no scroll)

- **Q1 (required)** — "How was the game?" 1–5, ends labelled Bad … Great.
- **Q2 (optional)** — "Were the teams even?" 1–5, Lopsided … Even.
- **Q3 (optional)** — one-line comment.
- Submit → thank-you summary with an **Edit** affordance until close time.
  After close time: read-only "Ratings are closed" with the submitted answer.

## Environment variables

Copy `.env.example` to `.env.local` and fill in:

| Var | Purpose |
| --- | --- |
| `SUPABASE_URL` | Your project URL, e.g. `https://xxxx.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key. **Server-side only.** |

> ⚠️ Never prefix these with `NEXT_PUBLIC_`. The service-role key bypasses Row
> Level Security and must never reach the browser.

## Develop

```bash
npm install
npm run dev
# open http://localhost:3000/r/<token>
```

## Build

```bash
npm run build
npm start
```

## Deploy to Vercel

1. Import the `web/` directory as the project root in Vercel.
2. Add the two env vars above under **Project → Settings → Environment
   Variables** (Production + Preview). Do **not** expose them to the browser —
   plain (non-`NEXT_PUBLIC_`) server env vars are correct here.
3. Deploy. The route `/r/<token>` is `force-dynamic`, so each visit re-checks
   token validity and close time.
```
