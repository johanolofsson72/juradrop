import { WelcomeCard } from '@/components/WelcomeCard';

// Root screen for spec 001-tauri-bootstrap.
// Centers a single placeholder welcome card on a full-viewport background that
// follows macOS appearance via Tailwind's `darkMode: 'media'`. No interactive
// surface beyond the disabled button in WelcomeCard — drop zones land in
// specs 003 and 004.
export function App() {
  return (
    <main className="grid min-h-screen place-items-center bg-background p-6 text-foreground">
      <WelcomeCard />
    </main>
  );
}
