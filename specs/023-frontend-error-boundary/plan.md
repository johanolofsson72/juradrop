# Implementation Plan: Frontend error boundary (Spec 023)

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: light

## Summary

A top-level `ErrorBoundary` class component catches render crashes and shows a calm Swedish fallback + "Starta om" (reload) button instead of a blank WKWebView. Wrap `<App/>` in main.tsx. No deps. Trivial 2-state → skip `/tla`.

## Constitution Check
- **VIII. Honest failure:** PASS — this is the frontend half of honest failure.
- **I. Privacy:** PASS — console-only logging, no telemetry.
- **V. Swedish-first:** PASS — fallback copy Swedish, humanizer.
- Gate: PASS.

## Approach

- `src/components/ErrorBoundary.tsx`: class component, `state={hasError:false}`, `static getDerivedStateFromError()` → `{hasError:true}`, `componentDidCatch(e,info)` → `console.error`. Render: if `hasError`, the fallback (Swedish message + "Starta om"-button → `window.location.reload()`); else `this.props.children`.
- frontend-design FIRST: fallback matches the calm Nordic minimal aesthetic (centered card, muted text, a single button styled like the existing primary button).
- `src/main.tsx`: wrap `<App/>` in `<ErrorBoundary>`.
- humanizer the fallback copy.
- vitest `src/__tests__/ErrorBoundary.test.tsx`: throwing child → fallback (suppress console.error), no stack in DOM, non-throwing child transparent, restart button present.

## Phases
1. ErrorBoundary component (frontend-design first) + humanizer copy.
2. Wrap App in main.tsx.
3. vitest coverage.
4. Gate: typecheck + lint + vitest.
