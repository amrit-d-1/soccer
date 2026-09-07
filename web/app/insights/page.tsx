import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getCurrentPlayer, isOrganizer } from '@/lib/data';
import { AppShell } from '@/components/AppShell';
import { InsightsClient } from './InsightsClient';

export const dynamic = 'force-dynamic';

export default async function InsightsPage() {
  const player = await getCurrentPlayer();
  if (!player) redirect('/login?next=/insights');
  if (!isOrganizer(player)) redirect('/');

  const supabase = await createClient();

  const [headcount, daytime, presence, trend, summary] = await Promise.all([
    supabase.from('v_headcount_effect').select('*'),
    supabase.from('v_daytime_effect').select('*'),
    supabase.from('v_player_presence').select('*'),
    supabase.from('v_trend').select('*'),
    supabase.from('v_game_summary').select('*'),
  ]);

  return (
    <AppShell isOrganizer>
      <InsightsClient
        headcount={(headcount.data as any[]) ?? []}
        daytime={(daytime.data as any[]) ?? []}
        presence={(presence.data as any[]) ?? []}
        trend={(trend.data as any[]) ?? []}
        summary={(summary.data as any[]) ?? []}
      />
    </AppShell>
  );
}
