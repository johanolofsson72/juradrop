#!/usr/bin/env bash
# Spec 052 — one command to cut a JuraDrop version.
#
#   scripts/bump-version.sh 0.5.0            # edit the files
#   scripts/bump-version.sh 0.5.0 --dry-run  # show what would change
#
# Bumps every place the version lives (package.json, package-lock.json,
# src-tauri/Cargo.toml, src-tauri/Cargo.lock, src-tauri/tauri.conf.json),
# turns CHANGELOG "## [Unreleased]" into "## [X.Y.Z] - <today>", and
# checks the in-app "Nytt i versionen" notes exist for X.Y.Z
# (src/lib/startup-strings.ts, spec 051).
#
# It never commits, tags, pushes or starts a build: those reach GitHub and
# are the developer's call. It prints the exact next steps instead.
#
# JURADROP_ROOT overrides the repo root (used by scripts/test-bump-version.sh).

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -ge 1 && $# -le 2 ]] || die "usage: $0 X.Y.Z [--dry-run]"
NEW="${1#v}"
DRY=0
[[ "${2:-}" == "" ]] || [[ "$2" == "--dry-run" ]] || die "unknown option '$2' (only --dry-run)"
[[ "${2:-}" == "--dry-run" ]] && DRY=1

[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "'$1' is not a version like 0.5.0"

ROOT="${JURADROP_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[[ -n "$ROOT" && -f "$ROOT/package.json" && -f "$ROOT/src-tauri/Cargo.toml" ]] \
    || die "run this inside the JuraDrop repo"
cd "$ROOT"

PKG=package.json
LOCK=package-lock.json
CARGO=src-tauri/Cargo.toml
CARGO_LOCK=src-tauri/Cargo.lock
TAURI=src-tauri/tauri.conf.json
CHANGELOG=CHANGELOG.md
NOTES=src/lib/startup-strings.ts

CUR="$(node -p "require('./$PKG').version")"

# Strictly greater, compared numerically per component.
version_gt() {
    local IFS=.
    local -a a=($1) b=($2)
    for i in 0 1 2; do
        (( a[i] > b[i] )) && return 0
        (( a[i] < b[i] )) && return 1
    done
    return 1
}
version_gt "$NEW" "$CUR" || die "$NEW is not greater than the current version $CUR"

if [[ -n "$(git status --porcelain -- "$PKG" "$LOCK" "$CARGO" "$CARGO_LOCK" "$TAURI" "$CHANGELOG" "$NOTES" 2>/dev/null)" ]]; then
    die "uncommitted changes in the release files; commit them first"
fi

# [Unreleased] must say something — an empty release has no changelog.
UNRELEASED_BODY="$(awk '
    /^## \[Unreleased\]/ { on = 1; next }
    on && /^## \[/        { exit }
    on && NF              { print }
' "$CHANGELOG")"
[[ -n "$UNRELEASED_BODY" ]] || die "CHANGELOG [Unreleased] is empty — write what changed first"

grep -q "'$NEW': \[" "$NOTES" \
    || die "no in-app release notes for $NEW — add '$NEW': [...] to RELEASE_NOTES in $NOTES"

TODAY="$(date +%Y-%m-%d)"

cat <<EOF
Bumping JuraDrop $CUR → $NEW
  $PKG, $LOCK          (npm version --no-git-tag-version)
  $CARGO               [package] version
  $CARGO_LOCK          juradrop entry
  $TAURI    "version"
  $CHANGELOG           [Unreleased] → [$NEW] - $TODAY
EOF

if (( DRY )); then
    echo "(dry run — nothing changed)"
    exit 0
fi

npm version "$NEW" --no-git-tag-version --allow-same-version >/dev/null

# Only the [package] table's version, never a dependency's.
awk -v v="$NEW" '
    /^\[package\]/                     { in_pkg = 1 }
    /^\[/ && !/^\[package\]/           { in_pkg = 0 }
    in_pkg && !done && /^version *= */ { print "version = \"" v "\""; done = 1; next }
    { print }
' "$CARGO" > "$CARGO.tmp" && mv "$CARGO.tmp" "$CARGO"

if [[ -f "$CARGO_LOCK" ]]; then
    awk -v v="$NEW" '
        /^name = "juradrop"$/          { hit = 1; print; next }
        hit && /^version = /           { print "version = \"" v "\""; hit = 0; next }
        { hit = hit && !/^\[\[package\]\]/; print }
    ' "$CARGO_LOCK" > "$CARGO_LOCK.tmp" && mv "$CARGO_LOCK.tmp" "$CARGO_LOCK"
fi

# Targeted replace of the top-level "version" (the first one in the file)
# so the file keeps its hand-written formatting; then prove it still parses.
node -e '
    const fs = require("fs");
    const [file, v] = process.argv.slice(1);
    const src = fs.readFileSync(file, "utf8");
    const out = src.replace(/("version"\s*:\s*")[^"]*(")/, `$1${v}$2`);
    if (JSON.parse(out).version !== v) throw new Error("tauri.conf.json top-level version not updated");
    fs.writeFileSync(file, out);
' "$TAURI" "$NEW"

awk -v v="$NEW" -v d="$TODAY" '
    !done && /^## \[Unreleased\]/ { print; print ""; print "## [" v "] - " d; done = 1; next }
    { print }
' "$CHANGELOG" > "$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"

# Verify every site now agrees — a partial bump must not look like success.
for got in \
    "$(node -p "require('./$PKG').version")" \
    "$(node -p "require('./$LOCK').version")" \
    "$(node -p "require('./$TAURI').version")" \
    "$(awk '/^\[package\]/{p=1} p&&/^version/{gsub(/[^0-9.]/,"");print;exit}' "$CARGO")"; do
    [[ "$got" == "$NEW" ]] || die "a version site still says '$got' — inspect git diff"
done

cat <<EOF

Done. Review with: git diff
Next steps (each one reaches GitHub, so they are yours to run):
  1. git commit -am "chore(release): v$NEW"
  2. git tag -a v$NEW -m "JuraDrop $NEW" && git push origin main v$NEW
  3. GitHub → Actions → release → Run workflow: tag = v$NEW, confirm_release = release
  4. Smoke-test the DMG from the DRAFT release, then press "Publish release".
     Installed apps pick the update up within 4 hours (or at next launch).
EOF
