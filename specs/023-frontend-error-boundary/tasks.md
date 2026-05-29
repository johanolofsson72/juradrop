# Tasks: Frontend error boundary (Spec 023)

- [ ] T001 [frontend-design FIRST] Create `src/components/ErrorBoundary.tsx`: class component (getDerivedStateFromError + componentDidCatch→console.error); Swedish fallback (message + "Starta om"→window.location.reload()); never render the error/stack. Humanizer the copy.
- [ ] T002 Wrap `<App/>` in `<ErrorBoundary>` in `src/main.tsx`.
- [ ] T003 [P] vitest `src/__tests__/ErrorBoundary.test.tsx`: throwing child → Swedish fallback + restart button (suppress console.error); raw error/stack absent; non-throwing child transparent.
- [ ] T004 Gate: typecheck + lint + vitest.
- [ ] T005 Commit + push; tick 023 in `specs/INDEX.md`.

## Dependencies
T001→T002. T003 after T001. T004/T005 last.
