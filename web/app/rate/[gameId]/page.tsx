import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getCurrentPlayer, isOrganizer } from '@/lib/data';
import { AppShell } from '@/components/AppShell';
import { RateForm } from './RateForm';
import { formatGameDate, formatGameTime } from '@/lib/format';
import type { Game, Rating } from '@/lib/types';

export const dynamic = 'force-dynamic';

export default async function RatePage({
  params,
}: {
  params: Promise<{ gameId: string }>;
}) {
  const { gameId } = await params;
  const player = await getCurrentPlayer();
  if (!player) redirect(`/login?next=/rate/${gameId}`);
  const org = isOrganizer(player);

  const supabase = await createClient();

  const { data: game } = await supabase
    .from('game')
    .select('*')
    .eq('id', gameId)
    .maybeSingle<Game>();

  if (!game) {
    return (
      <AppShell isOrganizer={org}>
        <div className="card">
          <h1 className="title">Game not found</h1>
          <p className="subtitle">
            <Link href="/">Go home</Link>.
          </p>
        </div>
      </AppShell>
    );
  }

  // Is the viewer on this game's roster (did they play)?
  const { data: appearance } = await supabase
    .from('appearance')
    .select('id')
    .eq('game_id', gameId)
    .eq('player_id', player.id)
    .maybeSingle();

  if (!appearance) {
    return (
      <AppShell isOrganizer={org}>
        <div className="card" style={{ textAlign: 'center' }}>
          <div className="big-emoji" aria-hidden>
            ⚽️
          </div>
          <h1 className="title">You&apos;re not on this game&apos;s roster</h1>
          <p className="subtitle">
            Only players who appeared in the game can rate it. If you think this
            is a mistake, let the organizer know.
          </p>
          <Link href="/" className="btn-link">
            Go home
          </Link>
        </div>
      </AppShell>
    );
  }

  const { data: existing } = await supabase
    .from('rating')
    .select('overall, speed, intensity, comment')
    .eq('game_id', gameId)
    .eq('rater_id', player.id)
    .maybeSingle<Pick<Rating, 'overall' | 'speed' | 'intensity' | 'comment'>>();

  const editable =
    !game.ratings_close_at ||
    new Date(game.ratings_close_at).getTime() > Date.now();

  return (
    <AppShell isOrganizer={org}>
      <div className="stack" style={{ gap: 2 }}>
        <p className="eyebrow">Rate the game</p>
        <h1 className="title">{formatGameDate(game.starts_at)}</h1>
        <p className="subtitle">
          {formatGameTime(game.starts_at)}
          {game.location ? ` · ${game.location}` : ''}
        </p>
      </div>

      <RateForm
        gameId={gameId}
        raterId={player.id}
        editable={editable}
        existing={existing ?? null}
      />

      <p className="hint">
        Only you can see your rating. It stays editable until ratings close.
      </p>
    </AppShell>
  );
}
