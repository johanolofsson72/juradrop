// Spec 008 / T010 — wizard parent. Branches on useWizardState() +
// useMinVisibleHold() and renders WelcomeWizard, FirstRunProgress, or
// nothing (when phase is 'hidden'). The minimum-visible-hold prevents
// flicker on instant-completion paths (cached install, fiber link).

import { FirstRunProgress } from './FirstRunProgress';
import { WelcomeWizard } from './WelcomeWizard';
import { useMinVisibleHold, useWizardState } from '@/lib/use-wizard-state';

export function Wizard() {
  const actual = useWizardState();
  const phase = useMinVisibleHold(actual, 300);

  if (phase === 'welcome') return <WelcomeWizard />;
  if (phase === 'progress') return <FirstRunProgress />;
  if (phase === 'error') return <FirstRunProgress />;
  return null;
}
