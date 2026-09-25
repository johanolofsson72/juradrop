# Findings

Things the pipeline found that are NOT yet register rows, and may never be.

A spec records what it found here and keeps going. Every 5 ticked specs these are presented as one
batch and the developer decides per finding: fix it now, make it a row, or drop it. That review is
the only thing that grows the register — see `.claude/rules/carve-budget.md`.

This file is git-tracked on purpose: a finding one lane records is one the other must see.

Status: `[ ]` open · `[x]` decided (the decision is on the line)

## Open

- [ ] F001 — gap — 2026-09-25 · from spec 050 — Ollama v0.34.x no longer embeds the runner: it needs llama-server + libllama/libggml/MLX dylibs beside the binary; fetch-ollama.sh copies only 'ollama'. Bump needs bundling rework + Mac runtime test (050 FR-012 deferred)
- [ ] F002 — test — 2026-09-25 · from spec 050 — status-store.ts mutation score 76% (<80): survivors are pre-existing seed literals (initialStatus/seedSnapshot) + console.error strings
- [ ] F003 — ux — 2026-09-25 · from spec 050 — Every idle zone shows a '[ docx ]' badge although output mirrors the input format (txt/md stay txt/md)
- [ ] F004 — debt — 2026-09-25 · from spec 052 — Deferred major upgrades (safe-only per Johan): React 19, Vite 8 + plugin-react 6, Tailwind 4, TypeScript 7, ESLint 10, vitest 5, jsdom 30, Stryker 10, thiserror 2, zip/quick-xml majors. Each needs its own spec + visual check on a Mac
- [ ] F005 — tooling — 2026-09-25 · from spec 052 — npm update hits an arborist bug ('edgesOut' of null) around vitest's peer set; @testing-library/dom is now an explicit devDependency so --legacy-peer-deps can't silently drop it again
