import { TopBar, TabBar } from './Nav';

// Standard authenticated shell: sticky top bar + content + bottom tab bar.
export function AppShell({
  isOrganizer,
  children,
}: {
  isOrganizer: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="app">
      <TopBar isOrganizer={isOrganizer} />
      <main className="content">{children}</main>
      <TabBar isOrganizer={isOrganizer} />
    </div>
  );
}
