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
- Never store secrets in code — use appsettings.json (local) or environment variables (production).
