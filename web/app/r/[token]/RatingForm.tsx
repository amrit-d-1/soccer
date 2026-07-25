'use client';

import { useActionState, useEffect, useMemo, useState } from 'react';
import { useFormStatus } from 'react-dom';
import { submitRating, type SubmitState } from './actions';

type Existing = {
  overall: number;
  balance: number | null;
  comment: string | null;
};

type Props = {
  token: string;
  playedAtLabel: string;
  location: string | null;
  rosterNames: string[];
  editable: boolean;
  existing: Existing | null;
};

function Header({
  playedAtLabel,
  location,
  rosterNames,
}: Pick<Props, 'playedAtLabel' | 'location' | 'rosterNames'>) {
  return (
    <header className="header">
      <p className="eyebrow">Rate the game</p>
      <h1 className="title">{playedAtLabel}</h1>
      {location ? <p className="subtitle">{location}</p> : null}
      {rosterNames.length > 0 ? (
        <p className="roster">
          <strong>{rosterNames.length} played:</strong>{' '}
          {rosterNames.join(', ')}
        </p>
      ) : null}
    </header>
  );
}

function Scale({
  name,
  value,
  onChange,
  lowLabel,
  highLabel,
}: {
  name: string;
  value: number | null;
  onChange: (v: number) => void;
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
            aria-label={`${n}`}
            onClick={() => onChange(n)}
          >
            {n}
          </button>
        ))}
      </div>
      <div className="scale-ends">
        <span>1 · {lowLabel}</span>
        <span>{highLabel} · 5</span>
      </div>
      <input type="hidden" name={name} value={value ?? ''} />
    </div>
  );
}

function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <button type="submit" className="submit" disabled={pending}>
      {pending ? 'Saving…' : label}
    </button>
  );
}

function ReadOnlyAnswer({ existing }: { existing: Existing | null }) {
  if (!existing) {
    return <p className="hint">You didn’t rate this game.</p>;
  }
  return (
    <div className="body" style={{ gap: 22 }}>
      <div>
        <p className="q-label">How was the game?</p>
        <div className="answer-row">
          <span className="chip">{existing.overall}</span>
        </div>
      </div>
      <div>
        <p className="q-label">Were the teams even?</p>
        <div className="answer-row">
          {existing.balance != null ? (
            <span className="chip">{existing.balance}</span>
          ) : (
            <span className="chip empty">—</span>
          )}
        </div>
      </div>
      {existing.comment ? (
        <p className="answer-comment">“{existing.comment}”</p>
      ) : null}
    </div>
  );
}

export default function RatingForm(props: Props) {
  const { token, editable, existing } = props;

  const [state, formAction] = useActionState<SubmitState, FormData>(
    submitRating,
    { ok: false },
  );

  // Form field state, pre-filled from any existing rating.
  const [overall, setOverall] = useState<number | null>(
    existing?.overall ?? null,
  );
  const [balance, setBalance] = useState<number | null>(
    existing?.balance ?? null,
  );
  const [comment, setComment] = useState<string>(existing?.comment ?? '');

  // Whether we're actively showing the editable form vs. a read-only summary.
  // Start in "view" mode if they've already submitted; the form otherwise.
  const [editing, setEditing] = useState<boolean>(!existing);

  const justSubmitted = state.ok;

  // The values to display in the read-only summary after a successful submit.
  const submittedSnapshot: Existing | null = useMemo(() => {
    if (justSubmitted) {
      return { overall: overall as number, balance, comment: comment || null };
    }
    return existing;
  }, [justSubmitted, overall, balance, comment, existing]);

  useEffect(() => {
    if (justSubmitted) setEditing(false);
  }, [justSubmitted]);

  // ---------- READ-ONLY: ratings are closed ----------
  if (!editable) {
    return (
      <main className="screen">
        <Header {...props} />
        <div className="closed-banner">Ratings are closed</div>
        <ReadOnlyAnswer existing={existing} />
      </main>
    );
  }

  // ---------- THANK-YOU / already-submitted summary (still open) ----------
  if (!editing && submittedSnapshot) {
    return (
      <main className="screen">
        <Header {...props} />
        <div className="body">
          {justSubmitted ? (
            <p className="eyebrow" style={{ textAlign: 'center' }}>
              Thanks — saved! ✓
            </p>
          ) : null}
          <ReadOnlyAnswer existing={submittedSnapshot} />
        </div>
        <div className="footer">
          <button
            type="button"
            className="edit-link"
            onClick={() => setEditing(true)}
          >
            Edit my answer
          </button>
          <p className="hint">You can change this until ratings close.</p>
        </div>
      </main>
    );
  }

  // ---------- EDITABLE FORM ----------
  return (
    <main className="screen">
      <Header {...props} />
      <form action={formAction} className="body">
        <input type="hidden" name="token" value={token} />

        <div>
          <p className="q-label">How was the game?</p>
          <Scale
            name="overall"
            value={overall}
            onChange={setOverall}
            lowLabel="Bad"
            highLabel="Great"
          />
        </div>

        <div>
          <p className="q-label">
            Were the teams even?{' '}
            <span className="q-optional">(optional)</span>
          </p>
          <Scale
            name="balance"
            value={balance}
            onChange={setBalance}
            lowLabel="Lopsided"
            highLabel="Even"
          />
        </div>

        <div>
          <input
            className="comment"
            type="text"
            name="comment"
            placeholder="One quick comment (optional)"
            maxLength={280}
            value={comment}
            onChange={(e) => setComment(e.target.value)}
            autoComplete="off"
          />
        </div>

        <div className="footer">
          <p className="error" role="alert">
            {state.error ?? ''}
          </p>
          <SubmitButton label={existing ? 'Save changes' : 'Submit'} />
        </div>
      </form>
    </main>
  );
}
