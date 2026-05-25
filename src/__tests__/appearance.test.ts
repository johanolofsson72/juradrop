import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// FC-006: System appearance respected.
// jsdom does not compute styles or simulate prefers-color-scheme reliably, so
// the next-best automated check is a structural assertion: confirm that
// globals.css declares the dark-mode media query and overrides the
// background/foreground CSS variables for dark mode. This is what makes the
// Tailwind dark variant + shadcn variables react to the OS appearance per
// research.md R-001 ("both layers, CSS as source of truth").
const cssPath = resolve(__dirname, '../styles/globals.css');
const css = readFileSync(cssPath, 'utf-8');

describe('System appearance / dark mode CSS wiring', () => {
  it('declares the prefers-color-scheme dark media query', () => {
    expect(css).toMatch(/@media\s*\(\s*prefers-color-scheme:\s*dark\s*\)/);
  });

  it('overrides the --background variable for dark mode', () => {
    const darkBlock = css.match(
      /@media\s*\(\s*prefers-color-scheme:\s*dark\s*\)\s*{[\s\S]*?--background:[\s\S]*?}/,
    );
    expect(darkBlock).not.toBeNull();
  });

  it('overrides the --foreground variable for dark mode', () => {
    const darkBlock = css.match(
      /@media\s*\(\s*prefers-color-scheme:\s*dark\s*\)\s*{[\s\S]*?--foreground:[\s\S]*?}/,
    );
    expect(darkBlock).not.toBeNull();
  });

  it('applies the SF Pro system font stack to html', () => {
    // FR-009: SF Pro is the default font everywhere.
    expect(css).toMatch(/-apple-system/);
    expect(css).toMatch(/BlinkMacSystemFont/);
    expect(css).toMatch(/SF Pro Text/);
  });
});
