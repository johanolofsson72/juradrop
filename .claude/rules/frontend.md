---
paths:
  - "**/*.html"
  - "**/*.css"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.tsx"
  - "**/*.razor"
  - "**/*.cshtml"
  - "**/*.dart"
---

# Frontend / UI rules

**Universal (web AND native mobile):**
- ALWAYS invoke the `frontend-design` skill via the Skill tool BEFORE writing ANY UI code — web markup, React Native components, or Flutter widgets. "UI code" is not just HTML/CSS; a screen built from RN `<View>`s or Flutter `Widget`s is UI code and gets the same design pass.
- Follow the project `design-system/MASTER.md` (or design tokens) for every screen — no ad-hoc colors, spacing, or type. Visual drift is the same sin on a phone as on the web.
- No magic style values scattered inline — centralize (see per-stack rule below).

**Brand/vibe references — decompile before you build:**
- A reference like "the feeling of Spotify" / "like Linear" / "Apple-clean" is an *undecompiled* instruction. Do NOT pass it to `frontend-design` raw — it reverts to generic slop and the reference evaporates. First compile it into concrete `design-system/MASTER.md` primitives (color/type/layout/motion/mood/anti-patterns) via `.claude/rules/design-references.md`: library lookup (`.claude/docs/design-reference-library.md`) → WebFetch the live brand for unknowns → ambiguity interview when the vibe is multi-faceted. `frontend-design` then executes hex values and named fonts, not a feeling.

**Design tooling — three distinct things, all of them real and all in-session:**
- **`frontend-design` skill** is the **automated, in-session design gate** (the BLOCKING step above). It runs inside Claude Code with no manual handoff — this is the mechanism CLAUDE.md enforces. `ui-ux-pro-max` is the in-session design-system reference alongside it.
- **`/design`** (bundled skill, research preview since 2026-08-17) draws the screen *before* the code exists. One line of intent produces several editable artboards (`.dc.html`) laid out on a single pan/zoom canvas, published as an Artifact and refined by click-to-select. It reads the repo's existing components and tokens, so a new screen inherits the project's colors, fonts, radii and spacing instead of inventing them. **Optional and upstream** — reach for it when the layout is genuinely undecided and you want options side by side. It does not replace the `frontend-design` gate: pick an artboard, then build it *through* the gate.
- **`/design-sync`** (and the `DesignSync` tool behind it) keeps a local component library and a Claude Design **design-system project** in step, in **both** directions — pull the real design system into the repo so generated screens use real components, or push the repo's components back to the canvas. It is incremental and plan-gated (`list_files` → `finalize_plan` → `write_files`): one component at a time, never a wholesale replace. It does **not** watch the repo, so re-run it after tokens or components move.
- **Claude Design** (`claude.ai/design`) is the web canvas those two skills talk to. Shaping a design there by hand first is still a fine human-in-the-loop step; it is no longer the only way in, and the flow is no longer one-way.
- **`design-system/MASTER.md` stays authoritative.** An artboard pick or a `/design-sync` pull is an *input* to MASTER.md, never a replacement for it. Anything that contradicts MASTER.md is a drift to reconcile, not a new source of truth.

**Web (HTML / CSS / JS / Razor):**
- Use `const`/`let` in JavaScript — never `var`.
- Use strict equality (`===`) in JavaScript.
- Semantic HTML5 — choose the right element (nav, article, section, aside).
- Use CSS classes or CSS files — never inline `style="..."`.
- Mobile-first responsive design.

**Native mobile (React Native / Flutter):**
- The JS/HTML/CSS specifics above do not apply, but the design discipline does. React Native: centralize styles in `StyleSheet.create` / a theme — never scatter literal style objects; respect safe-area insets; use the platform type scale. Flutter: drive visuals from `ThemeData` / design tokens — never hardcode `Color(0x...)`/`EdgeInsets` per widget; use `MediaQuery`/`LayoutBuilder` for adaptivity.
- Accessibility is not optional: RN `accessibilityLabel`/`accessibilityRole`, Flutter `Semantics`. The screen must be reachable by VoiceOver/TalkBack and survive the largest system font scale.
