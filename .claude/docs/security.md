# Security

## Fundamental rules

- ALWAYS use parameterized queries — never string concatenation for SQL.
- Sanitize all user input (XSS protection).
- Configure HTTPS, CSRF protection, and CORS correctly.
- Secrets never go in code or committed config. The real value lives in 1Password. Production reads it from a secret file (see § Secrets).
- Never commit `.env`, `appsettings.Development.json`, or similar.
- All API endpoints require authentication unless otherwise specified.
- Never use `eval()` or `extract()` — neither in PHP nor JavaScript.

## Secrets

The team's 1Password vault holds every real value. Code, committed config and images never do.
`appsettings*.json` and `.env.example` name the key with an empty placeholder.

**Why not environment variables in production.** `docker service inspect` and `docker inspect`
print a service's environment in plain text to anyone with Docker API access. Child processes
inherit it, and it shows up in crash dumps and diagnostics pages. A Swarm secret shows up as a name
and a file path only. teach spec 014 moved every production secret to secret files for this reason.
Environment variables are the fallback only on a platform with no file-mounted secret store.

**Locally.** Commit a `.env.op` that holds `op://` references (a reference is not a secret) and let
1Password resolve them into the process without writing a file:

```bash
# .env.op (committed)
ConnectionStrings__Default=op://<vault>/<project>-db/connection-string
Stripe__ApiKey=op://<vault>/<project>-stripe/api-key

op run --env-file=.env.op -- dotnet run --project src/<Project>
op run --env-file=.env.op -- docker compose up
```

`dotnet user-secrets` also works for a .NET-only value that nobody else needs. Locally, environment
variables are fine: `docker inspect` exposure is a production problem.

**Production (Docker Swarm).** Pipe the value from 1Password straight into a Swarm secret on the
manager. It goes through stdin, so it never lands on disk or in shell history:

```bash
op read "op://<vault>/<project>-db/connection-string" | ssh live4-mgr-01 docker secret create <project>_db_connection -
```

Mount it in the stack file. The `target` becomes the file name, and the configuration provider maps
`__` to `:`:

```yaml
services:
  app:
    secrets:
      - source: <project>_db_connection
        target: ConnectionStrings__Default
secrets:
  <project>_db_connection:
    external: true
```

Read it in .NET with KeyPerFile. It ships in the ASP.NET Core shared framework, so there is no
package to add. Add it last so it wins over everything else:

```csharp
builder.Configuration.AddKeyPerFile("/run/secrets", optional: true);
```

Third-party images use their `*_FILE` convention, for example
`POSTGRES_PASSWORD_FILE=/run/secrets/<project>_pg_password`.

- **Images:** never put a secret in `ENV` or `ARG`, because `docker history` shows both. A build-time
  secret uses `RUN --mount=type=secret,id=<name>`.
- **Rotation:** Swarm secrets are immutable. Create `<name>_v2`, point the stack's `secrets:` at it,
  run `docker stack deploy`, then `docker secret rm` the old one.
- **CI:** GitHub Secrets still hold CI credentials (`LIVE4_SSH_KEY`). A runtime value the deploy
  workflow has to set goes into a Swarm secret, not into the service's `environment:`.

## Claude Code permissions.deny — known bug

`permissions.deny` in `.claude/settings.json` has known bugs (GitHub issues #6699, #6631, #27040) where deny rules are not always enforced. Our settings.json therefore contains a **PreToolUse backup hook** that blocks access to sensitive files (`.ssh`, `.aws`, `.env`, credentials) via `hookSpecificOutput.permissionDecision: "deny"`. This hook is reliable — unlike `permissions.deny`.

If you add new deny rules for security-critical files, always create a matching PreToolUse hook as backup.

**March 2026 fix:** A bug where PreToolUse hooks returning "allow" could bypass deny rules (including enterprise managed settings) has been fixed. The backup hook above is still recommended as defense-in-depth.

## Subprocess credentials

Set `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` in your environment to automatically strip Anthropic and cloud provider credentials from subprocess environments. Prevents API keys and tokens from leaking to child processes.

## Dependencies and supply chain

Third-party packages are the largest attack surface a project has, and most of it arrives transitively.
See `.claude/docs/supply-chain.md` for the defaults: npm 12's install-script approvals, release-age
cooldowns, NuGet audit as a build error, lockfile-only installs, SHA-pinned actions, and osv-scanner.
`bash scripts/project-freshness.sh` runs the scans locally (trufflehog, a key-shape scan, npm audit,
osv-scanner, `dotnet list package --vulnerable`). trufflehog reports only credentials a provider can
verify. A Data Protection key ring, a `.pfx` or a private key matches no provider, so the key-shape
pass looks for them by name and content across all of git history. Silence a harmless fixture with a
`<path-glob>  # <reason>` line in `.secret-shapes-allow`, and the reason is required.
