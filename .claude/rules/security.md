---
paths:
  - "**/*.cs"
  - "**/*.cshtml"
  - "**/*.razor"
---

# Security rules for C# code

- ALWAYS use parameterized queries — never string concatenation for SQL.
- Validate all user input at API boundaries.
- Never expose stack traces in production — use ProblemDetails.
- Verify that all API endpoints have [Authorize] or explicit [AllowAnonymous].
- Never store secrets in code or committed config. Values live in 1Password (`op run` locally). Production reads Swarm secret files via `AddKeyPerFile`, not environment variables. See `.claude/docs/security.md` § Secrets.
