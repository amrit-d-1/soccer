'use client';

import { useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import type { RsvpStatus } from '@/lib/types';

const OPTIONS: { status: RsvpStatus; label: string; emoji: string }[] = [
  { status: 'in', label: 'In', emoji: '✅' },
  { status: 'maybe', label: 'Maybe', emoji: '🤔' },
  { status: 'out', label: 'Out', emoji: '❌' },
];

export function RsvpButtons({
  gameId,
  playerId,
  initial,
  closed,
}: {
  gameId: string;
  playerId: string;
  initial: RsvpStatus | null;
  closed?: boolean;
}) {
  const [status, setStatus] = useState<RsvpStatus | null>(initial);
  const [saving, setSaving] = useState<RsvpStatus | null>(null);
  const [error, setError] = useState('');

  async function choose(next: RsvpStatus) {
    if (closed || saving) return;
    const prev = status;
    setStatus(next); // optimistic
    setSaving(next);
    setError('');
    const supabase = createClient();
    const { error: err } = await supabase.from('rsvp').upsert(
      {
        game_id: gameId,
        player_id: playerId,
        status: next,
        responded_at: new Date().toISOString(),
      },
      { onConflict: 'game_id,player_id' }
    );
    setSaving(null);
    if (err) {
      setStatus(prev);
      setError('Could not save — tap to try again.');
    }
  }

  return (
    <div>
      {closed && <p className="closed-banner">RSVPs are closed</p>}
      <div className="rsvp" role="group" aria-label="Your RSVP">
        {OPTIONS.map((o) => (
          <button
            key={o.status}
            type="button"
            className="rsvp-btn"
            data-status={o.status}
            aria-pressed={status === o.status}
            disabled={closed || saving !== null}
            onClick={() => choose(o.status)}
          >
            <span className="rsvp-emoji" aria-hidden>
              {o.emoji}
            </span>
            {o.label}
          </button>
        ))}
      </div>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
