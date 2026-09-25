# Tasks — 052 release-tooling-docs

- [x] T001 [FR-001] scripts/bump-version.sh + scripts/test-bump-version.sh
- [x] T002 [FR-002] release-prep.sh truthful next steps
- [x] T003 [FR-003/004] release-gate.test.ts (notes for version + guide names all zones)
- [x] T004 [FR-004] docs/anvandarguide.md, README, runbook, deployment.md
- [x] T005 [FR-005] npm update + @types/react 18 + cargo update + Node 22 in release.yml; full re-verify
- [ ] T006 [FR-006] Cut v0.5.0 with the script; commit + local tag
- [x] T007 @testing-library/dom declared explicitly (RTL 16 peer; was silently dropped by --legacy-peer-deps); `npm ci` verified from the lockfile
