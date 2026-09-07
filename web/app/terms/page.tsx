import Link from 'next/link';

export const metadata = { title: 'Terms of Service · Soccer Game' };

export default function TermsPage() {
  return (
    <main className="prose">
      <h1>Terms of Service</h1>
      <p className="updated">Last updated: 2026-09-07</p>

      <p>
        Soccer Game is a private tool for our pickup soccer group to organize
        games and rate them. By using it, you agree to these terms.
      </p>

      <h2>Messaging</h2>
      <p>
        We use SMS to coordinate games. Message frequency varies. Msg &amp; data
        rates may apply. Reply STOP at any time to opt out, or HELP for help.
      </p>

      <h2>Acceptable use</h2>
      <p>
        This tool is for members of our group only. Please keep it to
        coordinating games and giving honest, respectful ratings. Don&apos;t
        misuse the service, attempt to access others&apos; private ratings, or
        share access with people outside the group.
      </p>

      <h2>No warranty</h2>
      <p>
        The service is provided &quot;as is,&quot; without warranties of any
        kind. Games, schedules, and data may change or be unavailable, and we
        aren&apos;t liable for any issues arising from use of the tool.
      </p>

      <h2>Contact</h2>
      <p>
        Questions:{' '}
        <a href="mailto:amritpal.dhangal@gmail.com">
          amritpal.dhangal@gmail.com
        </a>
        .
      </p>

      <hr className="divider" />
      <p>
        <Link href="/privacy">Privacy Policy</Link> ·{' '}
        <Link href="/login">Back to sign in</Link>
      </p>
    </main>
  );
}
