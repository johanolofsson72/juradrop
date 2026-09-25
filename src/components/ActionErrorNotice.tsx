import { useStatusStore } from '@/lib/status-store';

// Spec 050 FR-009 — the visible half of "never silent": a failed consent
// save or drop dispatch shows its fixed Swedish message here, announced to
// assistive tech via role="alert". Renders nothing when there is no error.
export function ActionErrorNotice({ className = '' }: { className?: string }) {
  const message = useStatusStore((s) => s.actionFailure);
  if (!message) return null;
  return (
    <p role="alert" className={`text-sm font-medium text-destructive ${className}`}>
      {message}
    </p>
  );
}
