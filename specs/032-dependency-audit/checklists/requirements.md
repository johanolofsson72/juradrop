# Specification Quality Checklist: Dependency vulnerability auditing

**Created**: 2026-06-02 · **Feature**: [spec.md](../spec.md) · **Track**: spec-only

## Content Quality
- [x] Focused on supply-chain/security value
- [x] All mandatory sections completed
- [x] No [NEEDS CLARIFICATION] markers remain

## Requirement Completeness
- [x] Requirements testable and unambiguous
- [x] Success criteria measurable
- [x] Edge cases identified (no-fix advisory, dev-only vulns, lockfile-only/no-compile)
- [x] Scope bounded (audit + Dependabot only; no auto-merge of bump PRs)
- [x] Dependencies + assumptions identified (Cargo.lock + package-lock.json present)

## Notes
- Spec-only track: no `.allium`, no `/tla`, no browser tests.
- Baseline MUST be clean before this ships (else audit.yml goes red on first run): npm audit --omit=dev --audit-level=high verified 0 vulnerabilities; cargo audit baseline verified before commit.
- cargo audit uses `-f src-tauri/Cargo.lock` because the lockfile is not at repo root; runs on ubuntu-latest (lockfile audits are platform-independent).
- All items pass iteration 1.
