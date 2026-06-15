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

**Design tooling — what's automated vs human-in-the-loop:**
- **`frontend-design` skill** is the **automated, in-session design gate** (the BLOCKING step above). It runs inside Claude Code with no manual handoff — this is the mechanism CLAUDE.md enforces. `ui-ux-pro-max` is the in-session design-system reference alongside it.
- **Claude Design** (Anthropic Labs, `claude.ai/design`, research preview since 2026-04-17) is a separate **web canvas** product — describe a screen, refine it visually, then **Export → "Handoff to Claude Code"** packages it as a bundle the agent builds from. Use it as an optional **upstream, human-in-the-loop** step when you want to shape the design visually first; it can read the repo to match the existing design system. It is **not** a Claude Code skill/CLI/MCP, so it cannot be an automated pre-UI gate — there is no in-session trigger. Flow is one-way: web canvas → export bundle → Claude Code. Keep `design-system/MASTER.md` as the source of truth either way; a Claude Design handoff should conform to it, not replace it.
- (Don't confuse the three: **Claude Design** = the canvas product; the **`frontend-design` skill** = our automated gate; the **`design` plugin** = a Claude Cowork plugin, not used here.)

**Web (HTML / CSS / JS / Razor):**
- Use `const`/`let` in JavaScript — never `var`.
- Use strict equality (`===`) in JavaScript.
- Semantic HTML5 — choose the right element (nav, article, section, aside).
- Use CSS classes or CSS files — never inline `style="..."`.
- Mobile-first responsive design.

**Native mobile (React Native / Flutter):**
- The JS/HTML/CSS specifics above do not apply, but the design discipline does. React Native: centralize styles in `StyleSheet.create` / a theme — never scatter literal style objects; respect safe-area insets; use the platform type scale. Flutter: drive visuals from `ThemeData` / design tokens — never hardcode `Color(0x...)`/`EdgeInsets` per widget; use `MediaQuery`/`LayoutBuilder` for adaptivity.
- Accessibility is not optional: RN `accessibilityLabel`/`accessibilityRole`, Flutter `Semantics`. The screen must be reachable by VoiceOver/TalkBack and survive the largest system font scale.
