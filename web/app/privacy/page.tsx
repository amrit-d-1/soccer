import Link from 'next/link';

export const metadata = { title: 'Privacy Policy · Soccer Game' };

export default function PrivacyPage() {
  return (
    <main className="prose">
      <h1>Privacy Policy</h1>
      <p className="updated">Last updated: 2026-09-07</p>

      <p>
        Soccer Game is a private tool used by our pickup soccer group to
        coordinate games over SMS. This policy explains what we collect and how
        we use it.
      </p>

      <h2>What we collect</h2>
      <p>
        We collect your name and mobile phone number, your RSVPs (whether
        you&apos;re in, out, or maybe for a game), and any game ratings and
        comments you submit.
      </p>

      <h2>How we use it</h2>
      <p>
        Your information is used only to coordinate our group — scheduling
        games, tracking who&apos;s coming, sending game-related text messages,
        and summarizing game ratings. We do not use it for advertising.
      </p>

      <h2>SMS messaging</h2>
      <p>
        By providing your mobile number you consent to receive text messages
        about our group&apos;s games (invites, reminders, and rating requests).
        Message frequency varies. Msg &amp; data rates may apply. Reply STOP at
        any time to opt out, or HELP for help.
      </p>

      <h2>Sharing</h2>
      <p>
        We do not sell or share your information. No mobile information is shared
        with third parties or affiliates for marketing or promotional purposes.
      </p>
      <p>
        We use the following service providers only to operate this tool: Twilio
        (to send SMS) and Supabase (to store data). They process your
        information solely on our behalf.
      </p>

      <h2>Retention</h2>
      <p>
        We keep your information for as long as you&apos;re part of the group. If
        you leave, or if you&apos;d like your information deleted, email us and
        we&apos;ll remove it.
      </p>

      <h2>Contact</h2>
      <p>
        Questions or deletion requests:{' '}
        <a href="mailto:amritpal.dhangal@gmail.com">
          amritpal.dhangal@gmail.com
        </a>
        .
      </p>

      <hr className="divider" />
      <p>
        <Link href="/terms">Terms of Service</Link> ·{' '}
        <Link href="/login">Back to sign in</Link>
      </p>
    </main>
  );
}
