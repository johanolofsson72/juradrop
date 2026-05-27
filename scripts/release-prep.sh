#!/bin/sh
# Spec 006 — local release-prep helper.
#
# Run this BEFORE pushing a release tag. It verifies six preconditions
# and, on success, prints the exact `git tag … && git push …` command
# the developer should copy-paste. Refuses to auto-push.
#
# Usage:
#   scripts/release-prep.sh vX.Y.Z
#
# Example:
#   scripts/release-prep.sh v0.1.0
#
# POSIX-sh compatible (no bashisms). Matches the convention set by
# scripts/fetch-ollama.sh.

set -eu

# ---- Argument parsing --------------------------------------------------

if [ "$#" -ne 1 ]; then
    echo "ERROR: exactly one argument expected (the target tag vX.Y.Z)" >&2
    echo "Usage: $0 vX.Y.Z" >&2
    exit 1
fi

TAG="$1"

# Tag shape check — must start with v and be a semver triple (optional
# pre-release suffix permitted but discouraged at v1).
case "$TAG" in
    v[0-9]*.[0-9]*.[0-9]*) : ;;
    *)
        echo "ERROR: tag '$TAG' does not match the expected shape vX.Y.Z (or vX.Y.Z-suffix)." >&2
        echo "       Examples: v0.1.0, v1.2.3, v0.2.0-beta.1" >&2
        exit 1
        ;;
esac

# Strip leading 'v' for version comparisons against the three files.
VERSION="${TAG#v}"

# ---- Where am I running from? -----------------------------------------

# Resolve the repo root via git so the script works whether the user
# runs it from the repo root or anywhere inside the tree.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
    echo "ERROR: not inside a git repository." >&2
    exit 1
fi

# Sanity-check this is actually the JuraDrop repo, not a different
# checkout that happens to be on a similar path.
if [ ! -f "$REPO_ROOT/src-tauri/Cargo.toml" ] || [ ! -f "$REPO_ROOT/package.json" ]; then
    echo "ERROR: $REPO_ROOT does not look like the JuraDrop repo." >&2
    echo "       (Expected src-tauri/Cargo.toml + package.json.)" >&2
    exit 1
fi

cd "$REPO_ROOT"

# ---- Pre-condition (f): HEAD must be on main --------------------------

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "ERROR: refusing to prep a release from a non-main branch." >&2
    echo "       Current branch: $CURRENT_BRANCH" >&2
    echo "       Switch to main: git switch main" >&2
    exit 1
fi

# ---- Pre-condition (a): working tree must be clean --------------------

if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: working tree has uncommitted changes — commit or stash first." >&2
    echo "       (git status --porcelain output was non-empty)" >&2
    exit 1
fi

# ---- Pre-condition (e): local main must be in sync with origin/main ---

# Fetch the remote ref without merging so the comparison is honest.
git fetch --quiet origin main

LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse origin/main)"

if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
    AHEAD="$(git rev-list --count "$REMOTE_SHA..$LOCAL_SHA" 2>/dev/null || echo "?")"
    BEHIND="$(git rev-list --count "$LOCAL_SHA..$REMOTE_SHA" 2>/dev/null || echo "?")"
    echo "ERROR: local main is out of sync with origin/main." >&2
    echo "       Ahead by $AHEAD commit(s), behind by $BEHIND commit(s)." >&2
    echo "       Push first: git push origin main" >&2
    exit 1
fi

# ---- Pre-condition (b): src-tauri/Cargo.toml version pin --------------

CARGO_VERSION="$(awk '
    /^\[package\]/ { in_pkg = 1; next }
    /^\[/         { in_pkg = 0 }
    in_pkg && /^version[[:space:]]*=/ {
        gsub(/^version[[:space:]]*=[[:space:]]*"/, "")
        gsub(/".*$/, "")
        print
        exit
    }
' src-tauri/Cargo.toml)"

if [ "$CARGO_VERSION" != "$VERSION" ]; then
    echo "ERROR: src-tauri/Cargo.toml version is '$CARGO_VERSION'; expected '$VERSION' for tag $TAG." >&2
    echo "       Bump the [package] version line and commit before tagging." >&2
    exit 1
fi

# ---- Pre-condition (c): src-tauri/tauri.conf.json version pin ---------

TAURI_VERSION="$(awk '
    /"version"[[:space:]]*:/ {
        gsub(/^.*"version"[[:space:]]*:[[:space:]]*"/, "")
        gsub(/".*$/, "")
        print
        exit
    }
' src-tauri/tauri.conf.json)"

if [ "$TAURI_VERSION" != "$VERSION" ]; then
    echo "ERROR: src-tauri/tauri.conf.json version is '$TAURI_VERSION'; expected '$VERSION' for tag $TAG." >&2
    echo "       Update the top-level \"version\" field and commit before tagging." >&2
    exit 1
fi

# ---- Pre-condition (d): package.json version pin ----------------------

PACKAGE_VERSION="$(awk '
    /"version"[[:space:]]*:/ {
        gsub(/^.*"version"[[:space:]]*:[[:space:]]*"/, "")
        gsub(/".*$/, "")
        print
        exit
    }
' package.json)"

if [ "$PACKAGE_VERSION" != "$VERSION" ]; then
    echo "ERROR: package.json version is '$PACKAGE_VERSION'; expected '$VERSION' for tag $TAG." >&2
    echo "       Update the \"version\" field and commit before tagging." >&2
    exit 1
fi

# ---- All checks passed -----------------------------------------------

# Refuse to print the push command if the tag already exists locally.
if git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "ERROR: tag $TAG already exists locally. Delete it first if you mean to re-cut the release:" >&2
    echo "       git tag -d $TAG && git push --delete origin $TAG" >&2
    exit 1
fi

cat <<EOF

All preconditions OK for $TAG:
  - HEAD on main
  - working tree clean
  - origin/main up-to-date (sha $LOCAL_SHA)
  - src-tauri/Cargo.toml         version = $VERSION
  - src-tauri/tauri.conf.json    version = $VERSION
  - package.json                 version = $VERSION
  - tag $TAG does not yet exist

Run this exact command to ship:

  git tag $TAG && git push origin $TAG

GitHub Actions will pick up the tag push, run the full regression sweep
on macos-latest, sign + notarize the DMG, and create a DRAFT release.
Smoke-test the draft DMG before clicking "Publish release".

EOF
