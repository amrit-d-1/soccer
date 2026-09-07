import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getCurrentPlayer, isOrganizer } from '@/lib/data';
import { AppShell } from '@/components/AppShell';
import { RsvpButtons } from '@/components/RsvpButtons';
import { formatGameDate, formatGameTime } from '@/lib/format';
import type { Game, RosterRow, RsvpStatus } from '@/lib/types';

export const dynamic = 'force-dynamic';

export default async function GamePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const player = await getCurrentPlayer();
  if (!player) redirect(`/login?next=/game/${id}`);
  const org = isOrganizer(player);

  const supabase = await createClient();

  const { data: game } = await supabase
    .from('game')
    .select('*')
    .eq('id', id)
    .maybeSingle<Game>();

  if (!game) {
    return (
      <AppShell isOrganizer={org}>
        <div className="card">
          <h1 className="title">Game not found</h1>
          <p className="subtitle">
            This game may have been removed. <Link href="/">Go home</Link>.
          </p>
        </div>
      </AppShell>
    );
  }

  const { data: rosterData } = await supabase.rpc('game_roster', {
    p_game_id: id,
  });
  const roster = (rosterData as RosterRow[] | null) ?? [];

  const inRows = roster.filter((r) => r.rsvp_status === 'in');
  const outCount = roster.filter((r) => r.rsvp_status === 'out').length;
  const maybeCount = roster.filter((r) => r.rsvp_status === 'maybe').length;

  const mine = roster.find((r) => r.player_id === player.id);
  let myStatus: RsvpStatus | null = mine?.rsvp_status ?? null;
  if (!mine) {
    // Roster may not include the viewer until they RSVP; check directly.
    const { data } = await supabase
      .from('rsvp')
      .select('status')
      .eq('game_id', id)
      .eq('player_id', player.id)
      .maybeSingle<{ status: RsvpStatus }>();
    myStatus = data?.status ?? null;
  }

  const rsvpClosed =
    !!game.rsvp_close_at && new Date(game.rsvp_close_at).getTime() < Date.now();

  return (
    <AppShell isOrganizer={org}>
      <section className="card">
        <div className="stack" style={{ gap: 2 }}>
          <p className="section-label">Game</p>
          <h1 className="title">{formatGameDate(game.starts_at)}</h1>
          <p className="subtitle">
            {formatGameTime(game.starts_at)}
            {game.location ? ` · ${game.location}` : ''}
          </p>
        </div>
        {game.notes && <p className="notice">{game.notes}</p>}
      </section>

      <section className="card">
        <p className="section-label">Your RSVP</p>
        <RsvpButtons
          gameId={game.id}
          playerId={player.id}
          initial={myStatus}
          closed={rsvpClosed}
        />
      </section>

      <section className="card">
        <div className="row">
          <p className="section-label">Who&apos;s coming</p>
          <p className="count-pill">
            <span style={{ color: 'var(--green)' }}>{inRows.length} in</span>
            {' · '}
            {maybeCount} maybe
            {' · '}
            {outCount} out
          </p>
        </div>

        {org && game.capacity != null && (
          <p className="subtitle">
            {inRows.length} / {game.capacity} spots filled
            {inRows.length >= game.capacity ? ' — full' : ''}
          </p>
        )}

        {inRows.length === 0 ? (
          <p className="subtitle">No one has said yes yet. Be the first!</p>
        ) : (
          <ul className="name-list">
            {inRows
              .slice()
              .sort((a, b) => a.name.localeCompare(b.name))
              .map((r) => (
                <li key={r.player_id}>
                  <span>{r.name}</span>
                  <span className="badge in">In</span>
                </li>
              ))}
          </ul>
        )}
      </section>
    </AppShell>
  );
}
