import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getCurrentPlayer, isOrganizer } from '@/lib/data';
import { AppShell } from '@/components/AppShell';
import { AdminClient } from './AdminClient';
import type { Game, Player } from '@/lib/types';

export const dynamic = 'force-dynamic';

export default async function AdminPage() {
  const player = await getCurrentPlayer();
  if (!player) redirect('/login?next=/admin');
  if (!isOrganizer(player)) redirect('/');

  const supabase = await createClient();

  const [{ data: games }, { data: summaries }, { data: players }, { data: apps }] =
    await Promise.all([
      supabase
        .from('game')
        .select('*')
        .order('starts_at', { ascending: false }),
      supabase.from('v_game_summary').select('*'),
      supabase.from('player').select('*').order('name', { ascending: true }),
      supabase.from('appearance').select('player_id'),
    ]);

  const counts: Record<string, number> = {};
  ((apps as { player_id: string }[] | null) ?? []).forEach((a) => {
    counts[a.player_id] = (counts[a.player_id] ?? 0) + 1;
  });

  return (
    <AppShell isOrganizer>
      <AdminClient
        games={(games as Game[]) ?? []}
        summaries={(summaries as any[]) ?? []}
        players={(players as Player[]) ?? []}
        appearanceCounts={counts}
      />
    </AppShell>
  );
}
