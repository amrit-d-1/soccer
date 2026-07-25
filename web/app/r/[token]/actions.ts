'use server';

import { getSupabaseAdmin } from '@/lib/supabase-admin';

export type SubmitState = {
  ok: boolean;
  error?: string;
};

/**
 * Server Action to save a rating.
 *
 * Security: the ONLY trusted client input is the token plus the answers. The
 * session_id and rater_id are ALWAYS derived server-side from the token — we
 * never accept them from the client. The token is fully re-validated here
 * (exists, not expired, session not past ratings_close_at) so this action is
 * safe on its own regardless of what the page rendered.
 */
export async function submitRating(
  _prev: SubmitState,
  formData: FormData,
): Promise<SubmitState> {
  const token = String(formData.get('token') ?? '').trim();
  if (!token) {
    return { ok: false, error: 'Missing link token.' };
  }

  // ---- Parse + validate the answers ----
  const overallRaw = formData.get('overall');
  const overall = overallRaw != null ? Number(overallRaw) : NaN;
  if (!Number.isInteger(overall) || overall < 1 || overall > 5) {
    return { ok: false, error: 'Please tap a rating for how the game was.' };
  }

  const balanceRaw = formData.get('balance');
  let balance: number | null = null;
  if (balanceRaw != null && String(balanceRaw) !== '') {
    const b = Number(balanceRaw);
    if (!Number.isInteger(b) || b < 1 || b > 5) {
      return { ok: false, error: 'That teams-even rating looks off.' };
    }
    balance = b;
  }

  const commentRaw = String(formData.get('comment') ?? '').trim();
  const comment = commentRaw.length > 0 ? commentRaw.slice(0, 280) : null;

  const supabase = getSupabaseAdmin();

  // ---- Re-validate token server-side ----
  const { data: link, error: linkErr } = await supabase
    .from('rating_link')
    .select('token, session_id, player_id, expires_at, used_at')
    .eq('token', token)
    .maybeSingle();

  if (linkErr) {
    return { ok: false, error: 'Something went wrong. Please try again.' };
  }
  if (!link) {
    return { ok: false, error: 'This link isn’t valid.' };
  }

  const now = Date.now();
  if (link.expires_at && new Date(link.expires_at).getTime() < now) {
    return { ok: false, error: 'This link has expired.' };
  }

  const { data: session, error: sessionErr } = await supabase
    .from('session')
    .select('id, ratings_close_at')
    .eq('id', link.session_id)
    .maybeSingle();

  if (sessionErr || !session) {
    return { ok: false, error: 'Something went wrong. Please try again.' };
  }
  if (
    session.ratings_close_at &&
    new Date(session.ratings_close_at).getTime() < now
  ) {
    return { ok: false, error: 'Ratings are closed for this game.' };
  }

  // ---- Upsert the rating (session_id + rater_id derived from the token) ----
  const { error: upsertErr } = await supabase
    .from('rating')
    .upsert(
      {
        session_id: link.session_id,
        rater_id: link.player_id,
        overall,
        balance,
        comment,
      },
      { onConflict: 'session_id,rater_id' },
    );

  if (upsertErr) {
    return { ok: false, error: 'Could not save your rating. Please try again.' };
  }

  // ---- Mark the link used on first submit ----
  if (!link.used_at) {
    await supabase
      .from('rating_link')
      .update({ used_at: new Date().toISOString() })
      .eq('token', token);
  }

  return { ok: true };
}
