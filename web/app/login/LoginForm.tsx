'use client';

import { useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { normalizePhone } from '@/lib/format';

type Step = 'phone' | 'code' | 'name';

export function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get('next') || '/';

  const [step, setStep] = useState<Step>('phone');
  const [phoneInput, setPhoneInput] = useState('');
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const supabase = createClient();

  async function sendCode(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    const e164 = normalizePhone(phoneInput);
    if (!e164) {
      setError('Enter a valid phone number.');
      return;
    }
    setBusy(true);
    const { error: err } = await supabase.auth.signInWithOtp({ phone: e164 });
    setBusy(false);
    if (err) {
      setError(err.message || 'Could not send the code. Try again.');
      return;
    }
    setPhone(e164);
    setStep('code');
  }

  async function verify(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    const token = code.replace(/\D/g, '');
    if (token.length !== 6) {
      setError('Enter the 6-digit code.');
      return;
    }
    setBusy(true);
    const { error: err } = await supabase.auth.verifyOtp({
      phone,
      token,
      type: 'sms',
    });
    if (err) {
      setBusy(false);
      setError(err.message || 'That code did not work. Try again.');
      return;
    }
    // Link/create this user's player row.
    const { data, error: rpcErr } = await supabase.rpc('ensure_player');
    setBusy(false);
    if (rpcErr) {
      // Session is valid; let them proceed even if profile linking hiccups.
      finish();
      return;
    }
    const player = Array.isArray(data) ? data[0] : data;
    const currentName: string = (player?.name || '').trim();
    if (!currentName || currentName.toLowerCase() === 'player') {
      setStep('name');
      return;
    }
    finish();
  }

  async function saveName(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    const trimmed = name.trim();
    if (!trimmed) {
      setError('Please enter your name.');
      return;
    }
    setBusy(true);
    const { error: err } = await supabase.rpc('ensure_player', {
      p_name: trimmed,
    });
    setBusy(false);
    if (err) {
      setError('Could not save your name. Try again.');
      return;
    }
    finish();
  }

  function finish() {
    router.push(next);
    router.refresh();
  }

  return (
    <div className="stack" style={{ gap: 16 }}>
      {step === 'phone' && (
        <form onSubmit={sendCode} className="stack" style={{ gap: 16 }}>
          <div className="field">
            <label htmlFor="phone">Phone number</label>
            <input
              id="phone"
              className="input"
              type="tel"
              inputMode="tel"
              autoComplete="tel"
              placeholder="(555) 123-4567"
              value={phoneInput}
              onChange={(e) => setPhoneInput(e.target.value)}
              autoFocus
            />
            <p className="hint">
              We&apos;ll text you a one-time code. US numbers can skip the +1.
            </p>
          </div>
          <button className="btn" disabled={busy}>
            {busy ? 'Sending…' : 'Send code'}
          </button>
          {error && <p className="error">{error}</p>}
        </form>
      )}

      {step === 'code' && (
        <form onSubmit={verify} className="stack" style={{ gap: 16 }}>
          <div className="field">
            <label htmlFor="code">Enter the 6-digit code</label>
            <input
              id="code"
              className="input code"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              placeholder="••••••"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
              autoFocus
            />
            <p className="hint">Sent to {phone}</p>
          </div>
          <button className="btn" disabled={busy}>
            {busy ? 'Checking…' : 'Verify'}
          </button>
          <button
            type="button"
            className="btn-link"
            onClick={() => {
              setStep('phone');
              setCode('');
              setError('');
            }}
          >
            Use a different number
          </button>
          {error && <p className="error">{error}</p>}
        </form>
      )}

      {step === 'name' && (
        <form onSubmit={saveName} className="stack" style={{ gap: 16 }}>
          <div className="field">
            <label htmlFor="name">Your name</label>
            <input
              id="name"
              className="input"
              type="text"
              autoComplete="name"
              placeholder="e.g. Sam Rivera"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
            />
            <p className="hint">This is how you&apos;ll show on the roster.</p>
          </div>
          <button className="btn" disabled={busy}>
            {busy ? 'Saving…' : 'Continue'}
          </button>
          {error && <p className="error">{error}</p>}
        </form>
      )}
    </div>
  );
}
