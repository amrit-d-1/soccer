import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getCurrentPlayer, isOrganizer, needsName } from '@/lib/data';
import { AppShell } from '@/components/AppShell';
import { NameGate } from '@/components/NameGate';
import { RsvpButtons } from '@/components/RsvpButtons';
import { formatGameDate, formatGameTime, formatGameShortDate } from '@/lib/format';
import type { Game, Rsvp, Rating, RsvpStatus } from '@/lib/types';

export const dynamic = 'force-dynamic';

const PLAYED = new Set(['played', 'completed']);

export default async function HomePage() {
  const player = await getCurrentPlayer();
  if (!player) redirect('/login');

  const org = isOrganizer(player);

  if (needsName(player)) {
    return (
      <AppShell isOrganizer={org}>
        <NameGate />
      </AppShell>
    );
  }

  const supabase = await createClient();

  // Next upcoming scheduled game.
  const { data: nextGame } = await supabase
    .from('game')
    .select('*')
    .eq('status', 'scheduled')
    .order('starts_at', { ascending: true })
    .limit(1)
    .maybeSingle<Game>();

  // The user's RSVP for that game.
  let myRsvp: RsvpStatus | null = null;
  if (nextGame) {
    const { data } = await supabase
      .from('rsvp')
      .select('status')
      .eq('game_id', nextGame.id)
      .eq('player_id', player.id)
      .maybeSingle<Pick<Rsvp, 'status'>>();
    myRsvp = data?.status ?? null;
  }

  // Recent played games the user appeared in.
  const { data: appearances } = await supabase
    .from('appearance')
    .select('game:game_id(*)')
    .eq('player_id', player.id);

  const playedGames: Game[] = (
    (appearances ?? []) as unknown as { game: Game | null }[]
  )
    .map((a) => a.game)
    .filter((g): g is Game => !!g && PLAYED.has(g.status))
    .sort(
      (a, b) =>
        new Date(b.starts_at).getTime() - new Date(a.starts_at).getTime()
    )
    .slice(0, 10);

  // Which of those the user has already rated.
  const rated = new Set<string>();
  if (playedGames.length) {
    const { data: myRatings } = await supabase
      .from('rating')
      .select('game_id')
      .eq('rater_id', player.id)
      .in(
        'game_id',
        playedGames.map((g) => g.id)
      );
    (myRatings as Pick<Rating, 'game_id'>[] | null)?.forEach((r) =>
      rated.add(r.game_id)
    );
  }

  const rsvpClosed =
    !!nextGame?.rsvp_close_at &&
    new Date(nextGame.rsvp_close_at).getTime() < Date.now();

  return (
    <AppShell isOrganizer={org}>
      <div className="stack" style={{ gap: 2 }}>
        <p className="eyebrow">You</p>
        <h1 className="page-title">{player.name}</h1>
      </div>

      {/* Next game */}
      {nextGame ? (
        <section className="card">
          <div className="row">
            <div className="stack" style={{ gap: 2 }}>
              <p className="section-label">Next game</p>
              <p className="title">{formatGameDate(nextGame.starts_at)}</p>
              <p className="subtitle">
                {formatGameTime(nextGame.starts_at)}
                {nextGame.location ? ` · ${nextGame.location}` : ''}
              </p>
            </div>
          </div>
          <RsvpButtons
            gameId={nextGame.id}
            playerId={player.id}
            initial={myRsvp}
            closed={rsvpClosed}
          />
          <Link href={`/game/${nextGame.id}`} className="btn-link">
            View details &amp; who&apos;s coming →
          </Link>
        </section>
      ) : (
        <section className="card">
          <p className="section-label">Next game</p>
          <p className="subtitle">No game scheduled yet. Check back soon.</p>
        </section>
      )}

      {/* Rate recent games */}
      <section className="stack" style={{ gap: 10 }}>
        <p className="section-label">Rate recent games</p>
        {playedGames.length === 0 ? (
          <div className="card">
            <p className="subtitle">
              Once you play a game, you can rate it here.
            </p>
          </div>
        ) : (
          playedGames.map((g) => {
            const isRated = rated.has(g.id);
            const closed =
              !!g.ratings_close_at &&
              new Date(g.ratings_close_at).getTime() < Date.now();
            return (
              <Link key={g.id} href={`/rate/${g.id}`} className="card tap row">
                <div className="stack" style={{ gap: 2 }}>
                  <span style={{ fontWeight: 700 }}>
                    {formatGameShortDate(g.starts_at)}
                  </span>
                  <span className="subtitle">{g.location ?? 'Pickup game'}</span>
                </div>
                <span className={`badge ${isRated ? 'in' : ''}`}>
                  {isRated ? 'Rated' : closed ? 'View' : 'Rate'}
                </span>
              </Link>
            );
          })
        )}
      </section>
    </AppShell>
  );
}
