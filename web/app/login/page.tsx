import { Suspense } from 'react';
import Link from 'next/link';
import { LoginForm } from './LoginForm';

export const metadata = { title: 'Sign in · Soccer Game' };

export default function LoginPage() {
  return (
    <div className="auth-screen">
      <div className="stack" style={{ gap: 6 }}>
        <p className="eyebrow">Soccer Game</p>
        <h1 className="page-title">Sign in</h1>
        <p className="subtitle">
          RSVP for pickup soccer and rate the games. We use your phone number to
          text you a code — no password.
        </p>
      </div>

      <Suspense fallback={<p className="hint">Loading…</p>}>
        <LoginForm />
      </Suspense>

      <p className="auth-footer">
        By continuing you agree to our{' '}
        <Link href="/terms">Terms</Link> and{' '}
        <Link href="/privacy">Privacy Policy</Link>.
        <br />
        Msg &amp; data rates may apply. Reply STOP to opt out, HELP for help.
      </p>
    </div>
  );
}
