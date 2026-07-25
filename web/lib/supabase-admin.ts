import 'server-only';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/**
 * Service-role Supabase client. This bypasses Row Level Security and MUST only
 * ever run on the server. The `server-only` import above makes the build fail
 * if this module is ever pulled into a client component bundle.
 *
 * The service-role key is read from SUPABASE_SERVICE_ROLE_KEY (NOT a
 * NEXT_PUBLIC_* var) so it is never shipped to the browser.
 */

let cached: SupabaseClient | null = null;

export function getSupabaseAdmin(): SupabaseClient {
  if (cached) return cached;

  const url = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error(
      'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables.',
    );
  }

  cached = createClient(url, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  return cached;
}
