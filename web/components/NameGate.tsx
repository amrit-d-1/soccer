'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

// Shown on first sign-in when the profile has no real name yet.
export function NameGate() {
  const router = useRouter();
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function save(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) {
      setError('Please enter your name.');
      return;
    }
    setBusy(true);
    const supabase = createClient();
    const { error: err } = await supabase.rpc('ensure_player', {
      p_name: trimmed,
    });
    setBusy(false);
    if (err) {
      setError('Could not save your name. Try again.');
      return;
    }
    router.refresh();
  }

  return (
    <div className="card">
      <div className="stack" style={{ gap: 4 }}>
        <p className="eyebrow">Welcome</p>
        <h1 className="title">What&apos;s your name?</h1>
        <p className="subtitle">This is how you&apos;ll show on the roster.</p>
      </div>
      <form onSubmit={save} className="stack" style={{ gap: 12 }}>
        <input
          className="input"
          type="text"
          autoComplete="name"
          placeholder="e.g. Sam Rivera"
          value={name}
          onChange={(e) => setName(e.target.value)}
          autoFocus
        />
        <button className="btn" disabled={busy}>
          {busy ? 'Saving…' : 'Continue'}
        </button>
        {error && <p className="error">{error}</p>}
      </form>
    </div>
  );
}
