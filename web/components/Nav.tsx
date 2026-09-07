'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

export function TopBar({ isOrganizer }: { isOrganizer: boolean }) {
  const pathname = usePathname();
  const router = useRouter();

  async function signOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push('/login');
    router.refresh();
  }

  return (
    <header className="topbar">
      <Link href="/" className="brand">
        Soccer<span>.</span>
      </Link>
      <nav className="topbar-links">
        {isOrganizer && (
          <>
            <Link
              href="/admin"
              className={pathname.startsWith('/admin') ? 'active' : ''}
            >
              Admin
            </Link>
            <Link
              href="/insights"
              className={pathname.startsWith('/insights') ? 'active' : ''}
            >
              Insights
            </Link>
          </>
        )}
        <button onClick={signOut}>Sign out</button>
      </nav>
    </header>
  );
}

export function TabBar({ isOrganizer }: { isOrganizer: boolean }) {
  const pathname = usePathname();
  const active = (href: string) =>
    href === '/' ? pathname === '/' : pathname.startsWith(href);

  return (
    <nav className="tabbar">
      <Link href="/" className={`tab ${active('/') ? 'active' : ''}`}>
        <span className="tab-icon" aria-hidden>
          ⚽️
        </span>
        Home
      </Link>
      {isOrganizer && (
        <>
          <Link
            href="/admin"
            className={`tab ${active('/admin') ? 'active' : ''}`}
          >
            <span className="tab-icon" aria-hidden>
              🛠
            </span>
            Admin
          </Link>
          <Link
            href="/insights"
            className={`tab ${active('/insights') ? 'active' : ''}`}
          >
            <span className="tab-icon" aria-hidden>
              📊
            </span>
            Insights
          </Link>
        </>
      )}
    </nav>
  );
}
