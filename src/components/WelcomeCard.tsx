import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';

// Placeholder welcome card for spec 001-tauri-bootstrap.
// Renders the title "JuraDrop", the Swedish subtitle, and one disabled shadcn
// Button — enough to verify React + Tailwind + shadcn/ui all render. The real
// 2×3 drop-zone grid arrives in specs 003 and 004.
export function WelcomeCard() {
  return (
    <Card className="w-full max-w-md">
      <CardHeader className="space-y-2">
        <CardTitle className="text-2xl font-semibold tracking-tight">JuraDrop</CardTitle>
        <CardDescription className="text-sm text-muted-foreground">
          Lokal AI för svenska juriststudenter
        </CardDescription>
      </CardHeader>
      <CardContent>
        <p className="text-sm text-muted-foreground">
          Det här fönstret är en första genomgång. Riktiga droppzoner kommer i nästa version.
        </p>
      </CardContent>
      <CardFooter>
        <Button type="button" disabled aria-disabled="true">
          Kom igång
        </Button>
      </CardFooter>
    </Card>
  );
}
