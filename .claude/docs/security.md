# Security

## Fundamental rules

- ALWAYS use parameterized queries — never string concatenation for SQL.
- Sanitize all user input (XSS protection).
- Configure HTTPS, CSRF protection, and CORS correctly.
- Store secrets in `appsettings.json` (local) or environment variables (production) — never in code.
- Never commit `.env`, `appsettings.Development.json`, or similar.
- All API endpoints require authentication unless otherwise specified.
- Never use `eval()` or `extract()` — neither in PHP nor JavaScript.

## Claude Code permissions.deny — known bug

`permissions.deny` in `.claude/settings.json` has known bugs (GitHub issues #6699, #6631, #27040) where deny rules are not always enforced. Our settings.json therefore contains a **PreToolUse backup hook** that blocks access to sensitive files (`.ssh`, `.aws`, `.env`, credentials) via `hookSpecificOutput.permissionDecision: "deny"`. This hook is reliable — unlike `permissions.deny`.

If you add new deny rules for security-critical files, always create a matching PreToolUse hook as backup.

**March 2026 fix:** A bug where PreToolUse hooks returning "allow" could bypass deny rules (including enterprise managed settings) has been fixed. The backup hook above is still recommended as defense-in-depth.

## Subprocess credentials

Set `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` in your environment to automatically strip Anthropic and cloud provider credentials from subprocess environments. Prevents API keys and tokens from leaking to child processes.
