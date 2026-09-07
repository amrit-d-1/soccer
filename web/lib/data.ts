import { createClient } from '@/lib/supabase/server';
import type { Player } from '@/lib/types';

// Load the signed-in user's player row (RLS lets a user read their own row).
// Returns null when not signed in or no player row exists yet.
export async function getCurrentPlayer(): Promise<Player | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data } = await supabase
    .from('player')
    .select('*')
    .eq('user_id', user.id)
    .maybeSingle();

  return (data as Player) ?? null;
}

export function isOrganizer(player: Player | null): boolean {
  return player?.role === 'organizer';
}

// A profile still needs a name if it's empty or the placeholder 'Player'.
export function needsName(player: Player | null): boolean {
  const n = player?.name?.trim();
  return !n || n.toLowerCase() === 'player';
}
