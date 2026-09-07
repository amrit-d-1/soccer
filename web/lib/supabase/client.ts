'use client';

import { createBrowserClient } from '@supabase/ssr';

// Browser Supabase client. Uses the anon key + the signed-in user's JWT;
// every read/write is subject to Row-Level Security. The session is persisted
// to cookies so server components and middleware can read the same user.
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
