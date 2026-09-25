#!/usr/bin/env bash
# Spec 052 — tests for scripts/bump-version.sh, run against a throwaway
# copy of the release files in a temp git repo (the real tree is untouched).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SCRIPT="$HERE/bump-version.sh"
pass=0; fail=0

ok()   { echo "  ok   $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL $1"; fail=$((fail + 1)); }

fixture() {
    local dir; dir="$(mktemp -d)"
    mkdir -p "$dir/src-tauri" "$dir/src/lib"
    cat > "$dir/package.json" <<'EOF'
{ "name": "juradrop", "version": "0.4.1", "private": true }
EOF
    cat > "$dir/package-lock.json" <<'EOF'
{ "name": "juradrop", "version": "0.4.1", "lockfileVersion": 3, "requires": true,
  "packages": { "": { "name": "juradrop", "version": "0.4.1" } } }
EOF
    cat > "$dir/src-tauri/Cargo.toml" <<'EOF'
[package]
name = "juradrop"
version = "0.4.1"

[dependencies]
serde = { version = "1" }
EOF
    cat > "$dir/src-tauri/Cargo.lock" <<'EOF'
[[package]]
name = "juradrop"
version = "0.4.1"

[[package]]
name = "other"
version = "0.4.1"
EOF
    cat > "$dir/src-tauri/tauri.conf.json" <<'EOF'
{ "productName": "JuraDrop", "version": "0.4.1" }
EOF
    cat > "$dir/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Fixed
- Något.

## [0.4.1] - 2026-06-20
EOF
    cat > "$dir/src/lib/startup-strings.ts" <<'EOF'
export const RELEASE_NOTES = {
  '0.5.0': ['x'],
};
EOF
    (cd "$dir" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
    echo "$dir"
}

run() { JURADROP_ROOT="$1" bash "$SCRIPT" "${@:2}" >/dev/null 2>&1; }

echo "bump-version.sh"

d="$(fixture)"
if run "$d" 0.5.0; then
    [[ "$(node -p "require('$d/package.json').version")" == 0.5.0 ]] && ok "package.json bumped" || bad "package.json bumped"
    [[ "$(node -p "require('$d/package-lock.json').packages[''].version")" == 0.5.0 ]] && ok "lockfile root bumped" || bad "lockfile root bumped"
    grep -q '^version = "0.5.0"' "$d/src-tauri/Cargo.toml" && ok "Cargo.toml bumped" || bad "Cargo.toml bumped"
    grep -q 'serde = { version = "1" }' "$d/src-tauri/Cargo.toml" && ok "Cargo.toml dependency untouched" || bad "Cargo.toml dependency untouched"
    [[ "$(grep -A1 'name = "juradrop"' "$d/src-tauri/Cargo.lock" | tail -1)" == 'version = "0.5.0"' ]] && ok "Cargo.lock juradrop bumped" || bad "Cargo.lock juradrop bumped"
    [[ "$(grep -A1 'name = "other"' "$d/src-tauri/Cargo.lock" | tail -1)" == 'version = "0.4.1"' ]] && ok "Cargo.lock other package untouched" || bad "Cargo.lock other package untouched"
    grep -q '"version": "0.5.0"' "$d/src-tauri/tauri.conf.json" && ok "tauri.conf.json bumped" || bad "tauri.conf.json bumped"
    grep -qE '^## \[0\.5\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$d/CHANGELOG.md" && ok "CHANGELOG section cut" || bad "CHANGELOG section cut"
    [[ "$(grep -c '^## \[Unreleased\]' "$d/CHANGELOG.md")" == 1 ]] && ok "empty [Unreleased] kept" || bad "empty [Unreleased] kept"
else
    bad "happy path exited non-zero"
fi

d="$(fixture)"
run "$d" 0.5.0 --dry-run && [[ -z "$(cd "$d" && git status --porcelain)" ]] && ok "--dry-run changes nothing" || bad "--dry-run changes nothing"

d="$(fixture)"; run "$d" 0.4.1 && bad "refuses same version" || ok "refuses same version"
d="$(fixture)"; run "$d" 0.3.9 && bad "refuses lower version" || ok "refuses lower version"
d="$(fixture)"; run "$d" 1.0 && bad "refuses non-semver" || ok "refuses non-semver"
d="$(fixture)"; run "$d" 0.6.0 && bad "refuses missing in-app notes" || ok "refuses missing in-app notes"
d="$(fixture)"; run "$d" 0.5.0 --force && bad "refuses unknown option" || ok "refuses unknown option"

d="$(fixture)"
printf '# Changelog\n\n## [Unreleased]\n\n## [0.4.1] - 2026-06-20\n' > "$d/CHANGELOG.md"
(cd "$d" && git -c user.email=t@t -c user.name=t commit -qam empty)
run "$d" 0.5.0 && bad "refuses empty [Unreleased]" || ok "refuses empty [Unreleased]"

d="$(fixture)"; echo " " >> "$d/package.json"
run "$d" 0.5.0 && bad "refuses a dirty release file" || ok "refuses a dirty release file"
[[ "$(node -p "require('$d/package.json').version")" == 0.4.1 ]] && ok "a refusal changes nothing" || bad "a refusal changes nothing"

d="$(fixture)"; run "$d" v0.5.0 && [[ "$(node -p "require('$d/package.json').version")" == 0.5.0 ]] && ok "accepts a leading v" || bad "accepts a leading v"

echo "passed $pass, failed $fail"
[[ $fail -eq 0 ]]
