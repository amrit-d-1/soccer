import { getSupabaseAdmin } from '@/lib/supabase-admin';
import RatingForm from './RatingForm';

// Always render fresh; a rating link's validity is time-sensitive.
export const dynamic = 'force-dynamic';

function formatPlayedAt(playedAt: string): string {
  // playedAt is a `date` (YYYY-MM-DD). Parse as local to avoid TZ drift.
  const [y, m, d] = playedAt.split('-').map(Number);
  const date = new Date(y, (m ?? 1) - 1, d ?? 1);
  return date.toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });
}

function Expired() {
  return (
    <main className="centered">
      <div className="big-emoji" aria-hidden>
        ⚽️
      </div>
      <h1>This link has expired or isn’t valid</h1>
      <p>
        No worries — grab a fresh link from your latest game text and try again.
      </p>
    </main>
  );
}

export default async function RatingPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const supabase = getSupabaseAdmin();

  // 1) Look up the rating link.
  const { data: link } = await supabase
    .from('rating_link')
    .select('token, session_id, player_id, expires_at, used_at')
    .eq('token', token)
    .maybeSingle();

  const now = Date.now();
  if (
    !link ||
    (link.expires_at && new Date(link.expires_at).getTime() < now)
  ) {
    return <Expired />;
  }

  // 2) Load the session so the rater knows which game this is.
  const { data: session } = await supabase
    .from('session')
    .select('id, played_at, location, ratings_close_at')
    .eq('id', link.session_id)
    .maybeSingle();

  if (!session) {
    return <Expired />;
  }

  // Roster: appearance -> player names for this session.
  const { data: appearances } = await supabase
    .from('appearance')
    .select('player:player_id ( name )')
    .eq('session_id', link.session_id);

  const rosterNames: string[] = (appearances ?? [])
    .map((a: any) => a?.player?.name)
    .filter((n: unknown): n is string => typeof n === 'string' && n.length > 0)
    .sort((a: string, b: string) => a.localeCompare(b));

  // 3) Editability.
  const editable =
    !session.ratings_close_at ||
    new Date(session.ratings_close_at).getTime() > now;

  // 4) This rater's existing rating ONLY. Never anyone else's.
  const { data: existing } = await supabase
    .from('rating')
    .select('overall, balance, comment')
    .eq('session_id', link.session_id)
    .eq('rater_id', link.player_id)
    .maybeSingle();

  return (
    <RatingForm
      token={token}
      playedAtLabel={formatPlayedAt(session.played_at)}
      location={session.location ?? null}
      rosterNames={rosterNames}
      editable={editable}
      existing={
        existing
          ? {
              overall: existing.overall,
              balance: existing.balance ?? null,
              comment: existing.comment ?? null,
            }
          : null
      }
    />
  );
}
