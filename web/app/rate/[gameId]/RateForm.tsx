'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

type Existing = {
  overall: number | null;
  speed: number | null;
  intensity: number | null;
  comment: string | null;
};

function Scale({
  value,
  onChange,
  disabled,
  lowLabel,
  highLabel,
}: {
  value: number | null;
  onChange: (v: number) => void;
  disabled?: boolean;
  lowLabel: string;
  highLabel: string;
}) {
  return (
    <div>
      <div className="scale" role="group">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            type="button"
            className="scale-btn"
            aria-pressed={value === n}
            disabled={disabled}
            onClick={() => onChange(n)}
          >
            {n}
          </button>
        ))}
      </div>
      <div className="scale-ends">
        <span>{lowLabel}</span>
        <span>{highLabel}</span>
      </div>
    </div>
  );
}

export function RateForm({
  gameId,
  raterId,
  editable,
  existing,
}: {
  gameId: string;
  raterId: string;
  editable: boolean;
  existing: Existing | null;
}) {
  const router = useRouter();
  const [overall, setOverall] = useState<number | null>(
    existing?.overall ?? null
  );
  const [speed, setSpeed] = useState<number | null>(existing?.speed ?? null);
  const [intensity, setIntensity] = useState<number | null>(
    existing?.intensity ?? null
  );
  const [comment, setComment] = useState(existing?.comment ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (!overall) {
      setError('Please give an overall rating.');
      return;
    }
    setBusy(true);
    const supabase = createClient();
    const { error: err } = await supabase.from('rating').upsert(
      {
        game_id: gameId,
        rater_id: raterId,
        overall,
        speed,
        intensity,
        comment: comment.trim() || null,
      },
      { onConflict: 'game_id,rater_id' }
    );
    setBusy(false);
    if (err) {
      const msg = (err.message || '').toLowerCase();
      if (msg.includes('appearance') || msg.includes('roster')) {
        setError("You're not on this game's roster, so you can't rate it.");
      } else {
        setError('Could not save your rating. Try again.');
      }
      return;
    }
    setSaved(true);
    router.refresh();
    setTimeout(() => setSaved(false), 2500);
  }

  if (!editable) {
    return (
      <div className="stack" style={{ gap: 18 }}>
        <p className="closed-banner">Ratings are closed — read only</p>
        <ReadOnlyRow label="Overall" value={existing?.overall ?? null} />
        <ReadOnlyRow label="Speed" value={existing?.speed ?? null} />
        <ReadOnlyRow label="Intensity" value={existing?.intensity ?? null} />
        {existing?.comment && (
          <p className="answer-comment" style={{ fontStyle: 'italic' }}>
            “{existing.comment}”
          </p>
        )}
        {!existing?.overall && (
          <p className="subtitle">You didn&apos;t rate this game.</p>
        )}
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="stack" style={{ gap: 20 }}>
      <div>
        <p className="q-label">Overall</p>
        <Scale
          value={overall}
          onChange={setOverall}
          lowLabel="Bad"
          highLabel="Great"
        />
      </div>
      <div>
        <p className="q-label">
          Speed <span className="q-optional">(optional)</span>
        </p>
        <Scale
          value={speed}
          onChange={setSpeed}
          lowLabel="Slow"
          highLabel="Fast"
        />
      </div>
      <div>
        <p className="q-label">
          Intensity <span className="q-optional">(optional)</span>
        </p>
        <Scale
          value={intensity}
          onChange={setIntensity}
          lowLabel="Chill"
          highLabel="Intense"
        />
      </div>
      <input
        className="comment"
        type="text"
        maxLength={140}
        placeholder="One-line comment (optional)"
        value={comment}
        onChange={(e) => setComment(e.target.value)}
      />
      <button className="btn" disabled={busy}>
        {busy ? 'Saving…' : existing?.overall ? 'Update rating' : 'Submit rating'}
      </button>
      {saved && <p className="hint" style={{ color: 'var(--green)' }}>Saved ✓</p>}
      {error && <p className="error">{error}</p>}
    </form>
  );
}

function ReadOnlyRow({
  label,
  value,
}: {
  label: string;
  value: number | null;
}) {
  return (
    <div className="row">
      <span className="q-label" style={{ margin: 0 }}>
        {label}
      </span>
      <span className="stat-big" style={{ fontSize: 22 }}>
        {value ?? '—'}
      </span>
    </div>
  );
}
