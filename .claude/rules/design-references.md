---
paths:
  - "**/design-system/**"
  - "**/*.html"
  - "**/*.css"
  - "**/*.jsx"
  - "**/*.tsx"
  - "**/*.razor"
  - "**/*.cshtml"
  - "**/*.dart"
  - "**/MASTER.md"
---

# Design reference rule (decompile the vibe before it reaches the skill)

A brand/vibe reference — "the feeling of Spotify", "make it like Linear", "Apple-clean", "brutalist" — is an **undecompiled instruction**. If it reaches the `frontend-design` skill raw, the model reverts to on-distribution slop (white bg, purple gradient, Inter, 8px radius) and the reference evaporates. The fix is not to teach the skill about Spotify; it is to **compile the vibe into concrete primitives in `design-system/MASTER.md` first**, so the skill executes deterministic tokens, not a feeling.

## The contract (BLOCKING — before invoking `frontend-design`)

Whenever a design request carries a brand/vibe/aesthetic reference, decompile it into the six MASTER.md primitive groups **before** writing any UI code or invoking `frontend-design`:

**color · typography · layout · motion · mood · anti-patterns**

`frontend-design` is invoked only *after* MASTER.md holds those primitives. It must never receive "feeling of Spotify" as the brief — it receives the compiled hex values, named fonts, radii, and anti-patterns.

## The decompile procedure (three tiers, in order)

1. **Library lookup (instant).** Check `.claude/docs/design-reference-library.md` for the reference. If present, copy its decompiled primitives into MASTER.md as the starting point. ~12 well-known aesthetics are seeded (Spotify, Linear, Stripe, Notion, Vercel, Apple HIG, Discord, Airbnb, Netflix, Material 3, brutalist, Duolingo).
2. **WebFetch decompile (unknown reference).** Not in the library? `WebFetch` the live site / brand guidelines and extract the six groups yourself — palette (sample real hex), type (identify the face, pick a free analog if proprietary), layout patterns, motion character, mood words, and what the vibe is NOT. Append the result to `design-reference-library.md` so the next project inherits it. WebFetch (not the seed file) is the source of truth for currency — brands redesign.
3. **Ambiguity interview (vague or multi-faceted reference).** A brand has several extractable "feelings" — Spotify is dark immersion *and* green energy *and* dense browse layout. If the reference is ambiguous, run a short `AskUserQuestion` to pin which facets matter ("Spotify's dark immersion, its green accent energy, or its card-dense browse layout — or all three?"), with a recommended default. Do not guess silently; the wrong facet ships the wrong app. (Same gap→interview pattern as the scenario map.)

After decompiling, also feed the keywords into `ui-ux-pro-max` (its palette/font-pairing/style datasets) where available, then let the brand decomposition override any conflicting automated pick.

### Optional fourth tier — draw it before you build it (`/design`)

Decompiling settles *what the primitives are*; it does not settle *what the screen looks like*. When the layout is genuinely
undecided and comparing options beats arguing about them, `/design` (bundled skill, research preview since 2026-08-17) renders
several editable artboards on one canvas, published as an Artifact. It reads the repo's existing components and tokens, so the
artboards come back already speaking MASTER.md's colors, fonts, radii and spacing rather than inventing a parallel language.

Order matters, and it is the same order this rule already enforces: **decompile → MASTER.md → `/design` → pick → `frontend-design`
→ code.** Running `/design` on an empty MASTER.md just moves the slop upstream — the artboards inherit nothing, and you end up
decompiling a canvas instead of a brand.

`/design-sync` (and the `DesignSync` tool behind it) closes the loop the other way: it keeps a local component library and a
Claude Design **design-system project** in step in both directions, incrementally and plan-gated, one component at a time. Use it
when the project has a real component library worth pushing to the canvas — and re-run it after tokens move, because it does not
watch the repo.

Neither is a gate. `frontend-design` remains the only BLOCKING design step (`.claude/rules/frontend.md`); these two are upstream
conveniences that feed it.

## Write it down, then build

- The decompiled primitives go into `design-system/MASTER.md` (the single source of truth `frontend-design` reads). Note the source reference in MASTER.md so future edits know where the values came from.
- Every screen then inherits hex values and named fonts — the brand can no longer drift to slop between components.
- If the design is shaped upstream on the canvas — `/design` in-session, or `claude.ai/design` by hand — the result is reconciled **into** MASTER.md. The canvas is an input; MASTER.md stays authoritative.

## What this rule forbids

- Passing a raw vibe/brand reference to `frontend-design` without decompiling it into MASTER.md first.
- Inventing primitives for a known brand instead of using the library (or the live site) — guesswork is how "Spotify" becomes generic.
- Treating an ambiguous reference as unambiguous — if the brand has multiple feelings, ask which one.
- Running `/design` before MASTER.md holds the decompiled primitives — the artboards then inherit nothing and the vibe evaporates one stage earlier.
- Treating a `/design` artboard or a `/design-sync` pull as the new source of truth. They are inputs to MASTER.md; anything that contradicts it is drift to reconcile.
