// Spec 041 — per-drop custom instruction field (FR-001/011/013/014/015).
//
// T001 frontend-design decisions (recorded per the design gate):
// - A "half-zone": borrows the zones' dashed-border DNA (border-dashed
//   border-border, rounded-lg, bg-transparent) flattened to one ~44 px
//   row, so it reads as part of the drop ritual — optional steering —
//   without competing with the 3×4 grid. Sits between WelcomeCard and
//   the grid.
// - Dashed → SOLID accent border on focus-within: the input-affordance
//   inverse of the zones' dragover pulse (dashed+pulse = "drop here",
//   solid+calm = "type here").
// - Counter in font-mono text-[10px] tracking-[0.32em] — the zones'
//   micro-label voice — visible only when the field has content.
// - Clear (×) appears only when non-empty; 150 ms color transitions
//   only (MASTER.md motion budget); system font; tokens only, no new
//   colors beyond the established #007aff/#0a84ff accent pair.
// - Always enabled (FR-015): steering can be staged while zones are
//   disabled or busy; the value is pinned per-drop at dispatch time.

import { useId } from 'react';
import { X } from 'lucide-react';
import { MAX_INSTRUCTION_CHARS, useInstructionStore } from '@/lib/instruction-store';

export function InstructionField() {
  const instruction = useInstructionStore((s) => s.instruction);
  const setInstruction = useInstructionStore((s) => s.setInstruction);
  const clear = useInstructionStore((s) => s.clear);
  const inputId = useId();
  const hasText = instruction.length > 0;

  return (
    <div
      data-instruction-field
      className={[
        'flex w-full items-center gap-2',
        'rounded-lg border-2 border-dashed border-border bg-transparent px-4 py-2',
        'transition-[border-color] duration-150 ease-out',
        'focus-within:border-solid focus-within:border-[#007aff] dark:focus-within:border-[#0a84ff]',
      ].join(' ')}
    >
      <label htmlFor={inputId} className="sr-only">
        Egna instruktioner för nästa dokument
      </label>
      <input
        id={inputId}
        type="text"
        value={instruction}
        onChange={(e) => setInstruction(e.target.value)}
        maxLength={MAX_INSTRUCTION_CHARS}
        placeholder="Egna instruktioner för nästa dokument – t.ex. ”behåll citaten på svenska” (valfritt)"
        autoComplete="off"
        autoCorrect="off"
        spellCheck={false}
        className={[
          'min-w-0 flex-1 bg-transparent text-sm text-foreground',
          'placeholder:text-muted-foreground',
          'focus:outline-none',
        ].join(' ')}
      />
      {hasText && (
        <span
          aria-hidden="true"
          data-instruction-counter
          className="shrink-0 font-mono text-[10px] tracking-[0.32em] text-muted-foreground tabular-nums"
        >
          {instruction.length}/{MAX_INSTRUCTION_CHARS}
        </span>
      )}
      {hasText && (
        <button
          type="button"
          onClick={clear}
          aria-label="Rensa instruktionen"
          data-instruction-clear
          className={[
            'shrink-0 cursor-pointer rounded p-0.5 text-muted-foreground',
            'transition-colors duration-150',
            'hover:text-foreground',
            'focus-visible:text-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-[#007aff] dark:focus-visible:ring-[#0a84ff]',
          ].join(' ')}
        >
          <X aria-hidden="true" className="h-3.5 w-3.5" strokeWidth={2.25} />
        </button>
      )}
    </div>
  );
}
