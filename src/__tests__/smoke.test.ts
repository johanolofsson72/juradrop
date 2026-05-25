import { describe, expect, it } from 'vitest';

describe('vitest smoke', () => {
  it('runs at least one test green', () => {
    // FC-007 + FR-011: vitest must run and at least one assertion passes.
    expect(true).toBe(true);
  });
});
