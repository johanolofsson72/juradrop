# Supply chain — dependency defaults

What a fresh project gets, and why. Versions checked 2026-09-28. `/project-wizard` and `/project-update`
write the cooldown files below when they are absent and never overwrite an existing one;
`scripts/project-freshness.sh` runs the scanners.

The threat is a malicious version published to the registry and installed within hours, before anyone
notices. The August 2026 "ChainDrop" worm spread that way, through `preinstall` scripts. Three defences
cover most of it: don't run install scripts nobody approved, don't install versions that are hours old,
and install exactly what the lockfile says.

## npm 12: dependency install scripts are blocked by default

Since npm 12.0.0 (2026-07-08), `npm install` and `npm ci` skip `preinstall`/`install`/`postinstall` for
any dependency that has no entry in the root `package.json` `allowScripts` field. The skipped packages
are listed at the end of the install. Other npm 12 defaults: `allow-git` and `allow-remote` are `none`
(git and off-registry tarball dependencies are refused), and `npm-shrinkwrap.json` is no longer honoured.

What breaks on the first install is anything that compiles or downloads a native binary in a script:
esbuild, sharp, and some Expo/React Native native modules. Approve them
once and commit the result:

```bash
npm approve-scripts --allow-scripts-pending   # list what was skipped; changes nothing
npm approve-scripts esbuild sharp             # approve by name (pinned to the installed version by default)
npm rebuild                                   # run the scripts that were skipped during the install
git add package.json                          # the policy lives in package.json, so the other machine gets it
```

- Approve by name after reading what the script does. `--all` exists, but it approves everything that
  is pending, which is the same as having no policy.
- Pinned entries (`pkg@1.2.3`) have to be approved again when the package is upgraded. That is the
  point: a new version is new code.
- **Expo:** run the approval after `npx expo install` and before `npx expo prebuild`. A native module
  whose script was skipped fails at build time, not at install time, so the error shows up in EAS
  Build rather than on your machine. Check `--allow-scripts-pending` before the first EAS build.
- Reference: https://docs.npmjs.com/cli/v12/commands/npm-approve-scripts

## Cooldowns: don't install versions that are hours old

Most malicious versions are found and unpublished within a day or two. A cooldown means you never
resolve to them. Three days is the template default; security fixes you actually need can be
installed explicitly.

**npm** (`.npmrc` in the project root; the unit is **days**):

```ini
min-release-age=3
```

**pnpm** (`pnpm-workspace.yaml`; the unit is **minutes**; the default has been 1440 (one day) since pnpm 11):

```yaml
minimumReleaseAge: 4320
```

pnpm 12 rejects unknown keys in `pnpm-workspace.yaml`, so check the spelling.

**uv** (`pyproject.toml` under `[tool.uv]`, or `uv.toml`; relative durations need a recent uv):

```toml
[tool.uv]
exclude-newer = "3 days"
```

**Dependabot** (`.github/dependabot.yml`, per `updates:` entry; this applies to version updates only,
security updates are never delayed):

```yaml
    cooldown:
      default-days: 3
      semver-major-days: 7
```

NuGet has no cooldown setting. Its protection is the audit gate below plus a committed lock file.

## NuGet audit as a deploy gate

.NET 10 (`net10.0` and later) audits transitive packages by default (`NuGetAuditMode=all`). The audit
only warns, though, so a vulnerable package ships unless something turns the warning into an error. Put
this in `Directory.Build.props` so high and critical advisories fail restore and build, while low and
moderate stay warnings:

```xml
<Project>
  <PropertyGroup>
    <WarningsAsErrors>$(WarningsAsErrors);NU1903;NU1904</WarningsAsErrors>
  </PropertyGroup>
</Project>
```

Codes: NU1901 low, NU1902 moderate, NU1903 high, NU1904 critical, NU1905 audit source unavailable.
Suppress a specific advisory you have assessed with
`<NuGetAuditSuppress Include="https://github.com/advisories/GHSA-…" />`, never by dropping the codes.
Report on demand with `dotnet list package --vulnerable --include-transitive`; transitive packages are
not included unless you pass the flag.
Reference: https://learn.microsoft.com/en-us/nuget/concepts/auditing-packages

## Lockfile discipline

| Stack | Commit | Install in the deploy gate / Dockerfile |
|---|---|---|
| npm | `package-lock.json` | `npm ci` (never `npm install`; it can rewrite the lockfile) |
| pnpm | `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` |
| .NET | `packages.lock.json` (`<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>`) | `dotnet restore --locked-mode` |
| Flutter | `pubspec.lock` (apps, not packages) | `flutter pub get --enforce-lockfile` |
| uv | `uv.lock` | `uv sync --locked` |

A lockfile that the gate is allowed to rewrite is not a lockfile.

## GitHub Actions: pin by full commit SHA

A tag like `@v4` can be moved to point at other code. A 40-character SHA cannot. Keep the tag as a
comment so Dependabot can still update it:

```yaml
- uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
```

Resolve a tag to its SHA with `gh api repos/actions/checkout/commits/v4 --jq .sha`. This applies to the
one deploy workflow `.claude/rules/github-actions.md` allows.

## osv-scanner: one pass over every lockfile

`npm audit` reads npm lockfiles only. osv-scanner v2 (2.6.0, 2026-09-14) reads `package-lock.json`,
`pnpm-lock.yaml`, `yarn.lock`, NuGet `packages.lock.json`/`packages.config`/`deps.json` and Dart
`pubspec.lock` in one pass, and honours `.gitignore`:

```bash
osv-scanner scan source -r .
```

Exit codes: `0` clean, `1` vulnerabilities found, `128` no packages found (not a pass, just nothing to
scan), `127` general error. `project-freshness.sh` runs it when installed and tells you when it is not.

Install:

| OS | Command |
|---|---|
| macOS | `brew install osv-scanner` |
| Linux | `brew install osv-scanner`, `pacman -S osv-scanner`, or `go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest` (Go ≥ 1.26.2), or a release binary from https://github.com/google/osv-scanner/releases |
| Windows | `scoop install osv-scanner` or `winget install Google.OSVScanner` |

Do not adopt Trivy for this. Its own release pipeline was compromised in March 2026.

Reference: https://google.github.io/osv-scanner/
