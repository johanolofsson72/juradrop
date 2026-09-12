#!/bin/sh
# scenario-map-baseline.sh — capture what the map's consumers DO, so 007bl can prove it
# changed nothing for projects that never split.
#
# WHY THIS EXISTS: spec 007bl edits five scripts that 42 projects run. Forty-one of those
# projects have a small, correct, single-file scenario map and must not notice this spec
# happened. "Must not notice" is a claim about behaviour, and the only honest way to check a
# behaviour claim across an edit is to record the behaviour before the edit and diff after.
# Reasoning about the diff is not the same thing — the whole point is that the change looks
# harmless, which is what every silent regression looks like.
#
# Run it BEFORE changing the consumers, then again after, and diff the two outputs.
#
#   scripts/scenario-map-baseline.sh > before.txt     # on the pre-change tree
#   ...make the changes...
#   scripts/scenario-map-baseline.sh > after.txt
#   diff before.txt after.txt                         # must be empty
#
# Output is normalized: fixture paths (which contain a pid and a temp dir) are rewritten to
# stable placeholders, because otherwise every run differs and the diff proves nothing.

set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/test-scenario-map-fixtures.sh"

# Initialize the temp dir in THIS shell before the first fixture is made. The makers run
# inside command substitution, i.e. a subshell, so an export from in there never reaches us —
# and $FIXTURE_TMPDIR would be empty for the rest of the script. Cost the first time round:
# a cp to "/map.small" that failed against a read-only root, and a restore that silently did
# not happen, which made the under-threshold canary case report the padded map.
FIXTURE_TMPDIR=$(_fixture_tmpdir)
export FIXTURE_TMPDIR

ROOT=$(make_single_file_fixture)

# Rewrite the fixture root to a placeholder so two runs are comparable.
normalize() { sed "s|$ROOT|<FIXTURE>|g; s|$FIXTURE_TMPDIR|<TMP>|g"; }

section() { printf '\n===== %s =====\n' "$1"; }

# --- the reminder hook ----------------------------------------------------------------
# Three inputs that exercise its whole decision tree on a single-file map: a spec whose slug
# IS in the map, one whose slug is NOT, and one with no interactive behaviour at all (which
# must stay silent regardless of the map).
mkdir -p "$ROOT/specs/001-alpha" "$ROOT/specs/003-gamma" "$ROOT/specs/004-delta"

cat > "$ROOT/specs/001-alpha/spec.md" <<'EOF'
# Alpha
The user submits a form with an input field and a button.
EOF
cat > "$ROOT/specs/003-gamma/spec.md" <<'EOF'
# Gamma
The user clicks a button to submit the search filter form.
EOF
cat > "$ROOT/specs/004-delta/spec.md" <<'EOF'
# Delta
A pure refactor. No user-facing surface at all.
EOF

# run_hook <spec-file> — the hook's own exit status, not the status of whatever last ran in
# a pipeline. `hook | normalize; printf "$?"` reports sed's exit, so every case in the first
# capture of this baseline recorded a cheerful [exit 0] that described the normalizer.
run_hook() {
  _rh_out=$(printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$SCRIPT_DIR/scenario-map-reminder-hook.sh" 2>&1)
  _rh_rc=$?
  printf '%s' "$_rh_out" | normalize
  [ -n "$_rh_out" ] && printf '\n'
  printf '[exit %s]\n' "$_rh_rc"
}

section "reminder-hook: slug IS in the map (expect silence)"
run_hook "$ROOT/specs/001-alpha/spec.md"

section "reminder-hook: slug is NOT in the map (expect advisory)"
run_hook "$ROOT/specs/003-gamma/spec.md"

section "reminder-hook: no interactive behaviour (expect silence)"
run_hook "$ROOT/specs/004-delta/spec.md"

# --- the orientation canary -----------------------------------------------------------
# Two sizes: a small map (silent) and one padded past the 25,600-byte threshold (warns).
# The padding is history entries, which is what actually bloats a real map.
section "orientation canary: map under threshold"
# The hook walks up from $PWD — it takes no cwd argument — so it must RUN in the fixture.
# Passing {"cwd": ...} on stdin looks right and silently reports the real repository instead,
# which is how the first capture of this baseline came back describing msroute's own register.
( cd "$ROOT" && bash "$SCRIPT_DIR/spec-register-orientation-hook.sh" </dev/null 2>&1 ) \
  | grep -oE 'SCENARIOS\.md \([0-9]+ KB\)' | normalize
printf '[no SCENARIOS.md size above means silent]\n'

cp "$ROOT/specs/SCENARIOS.md" "$FIXTURE_TMPDIR/map.small"
i=0
while [ "$i" -lt 400 ]; do
  printf -- '- 2026-08-26 — padding entry %s, present only to push this file past the canary threshold so the warning path is exercised\n' "$i" >> "$ROOT/specs/SCENARIOS.md"
  i=$((i + 1))
done

section "orientation canary: map over threshold"
( cd "$ROOT" && bash "$SCRIPT_DIR/spec-register-orientation-hook.sh" </dev/null 2>&1 ) \
  | grep -oE 'SCENARIOS\.md \([0-9]+ KB\)' | normalize

section "maintenance canary: map over threshold"
( cd "$ROOT" && bash "$SCRIPT_DIR/project-maintenance.sh" 2>&1 ) \
  | grep -E '\[CONTEXT-COST\]' | normalize

cp "$FIXTURE_TMPDIR/map.small" "$ROOT/specs/SCENARIOS.md"

section "maintenance canary: map under threshold"
( cd "$ROOT" && bash "$SCRIPT_DIR/project-maintenance.sh" 2>&1 ) \
  | grep -E '\[CONTEXT-COST\]' | normalize
printf '[no CONTEXT-COST line above means silent]\n'

# --- the archiver ---------------------------------------------------------------------
section "archiver: single-file map"
bash "$SCRIPT_DIR/archive-spec-history.sh" --dir "$ROOT/specs" --dry-run 2>&1 | normalize

fixture_cleanup
