#!/bin/bash
# test-checkpoint-cadence.sh — the every-5 checkpoint counts feature specs since the last checkpoint.
#
# fundit F211 (spec 068): the cadence counted H rows and carved rows, and fired "checkpoint due" at
# 20 done with four feature specs ticked since H2. Its `% 5` also went silent at 21 on a checkpoint
# that was never worked. Each case below is one of those shapes; the sabotage arms put each old
# behaviour back and require a case to go red.
set -uo pipefail
export LC_ALL=C
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
P=0; F=0
ok(){ echo "  PASS  $1"; P=$((P+1)); }
bad(){ echo "  FAIL  $1"; F=$((F+1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# A throwaway project: .git boundary, a language marker (so the orientation hook orients), the
# register from stdin, and the scripts under test copied in so a sabotaged engine is what runs.
mk() {
  local d="$T/$1"; mkdir -p "$d/.git" "$d/specs" "$d/scripts"; : > "$d/package.json"
  { echo "# Spec register"; echo; echo "## Specs"; echo; cat; } > "$d/specs/INDEX.md"
  cp "$ENGINE" "$d/scripts/checkpoint-cadence.sh"
  printf '%s' "$d"
}
engine() { bash "$1/scripts/checkpoint-cadence.sh" --dir "$1"; }
# The hook resolves the engine as a sibling of itself, so run a copy that sits beside the engine.
orient() {
  cp "$SD/spec-register-orientation-hook.sh" "$SD/hook-notice.sh" "$1/scripts/"
  [ -f "$SD/maintenance-due.sh" ] && cp "$SD/maintenance-due.sh" "$1/scripts/"
  (cd "$1" && bash scripts/spec-register-orientation-hook.sh 2>/dev/null) \
    | jq -r '.hookSpecificOutput.additionalContext // .systemMessage // ""'
}

cases() {
  # AC1 — fundit's shape: 20 ticked (a multiple of 5, so the modulo fired), H2 among them, and
  # only 4 feature specs below it — the rest are a `carved by` row and NNNa rows.
  local a; a=$(mk ac1 <<'M'
- [x] 001 — a — spec-only — x
- [x] 002 — b — spec-only — x
- [x] 003 — c — spec-only — x
- [x] 004 — d — spec-only — x
- [x] 005 — e — spec-only — x
- [x] H1 — integration-hardening — checkpoint — x
- [x] 006 — f — spec-only — x
- [x] 007 — g — spec-only — x
- [x] 008 — h — spec-only — x
- [x] 009 — i — spec-only — x
- [x] 010 — j — spec-only — x
- [x] H2 — integration-hardening — checkpoint — x
- [x] 011 — k — spec-only — x
- [x] 011a — k-followup — spec-only — x
- [x] 011b — k-followup-2 — spec-only — x
- [x] 012 — l — spec-only — x
- [x] 012a — l-followup — spec-only — x
- [x] 013 — m — light track — y — carved by 011
- [x] 014 — n — spec-only — x
- [x] 015 — o — spec-only — x
- [ ] 016 — p — spec-only — x
M
)
  local out rc; out=$(engine "$a"); rc=$?
  [ "$out" = "since=H2 count=4 due=0" ] && [ "$rc" -eq 1 ] \
    && ok "AC1 H rows and carved rows do not count (4 since H2, not due)" \
    || bad "AC1 got '$out' rc=$rc, want 'since=H2 count=4 due=0' rc=1"
  grep -q "CHECKPOINT DUE" <<< "$(orient "$a")" \
    && bad "AC1 orientation fires the checkpoint alarm at 4 feature specs" \
    || ok "AC1 orientation stays quiet at 4 feature specs"

  # AC2 — five features since H1: due, and the banner says what it counted.
  local b; b=$(mk ac2 <<'M'
- [x] H1 — integration-hardening — checkpoint — x
- [x] 001 — a — spec-only — x
- [x] 002 — b — spec-only — x
- [x] 003 — c — spec-only — x
- [x] 004 — d — spec-only — x
- [x] 005 — e — spec-only — x
- [ ] 006 — f — spec-only — x
M
)
  out=$(engine "$b"); rc=$?
  [ "$out" = "since=H1 count=5 due=1" ] && [ "$rc" -eq 0 ] && ok "AC2 five feature specs since H1 are due" \
    || bad "AC2 got '$out' rc=$rc"
  grep -q "CHECKPOINT DUE — 5 feature specs since H1" <<< "$(orient "$b")" \
    && ok "AC2 orientation names the count and the checkpoint" \
    || bad "AC2 orientation: $(orient "$b" | grep -i checkpoint | head -2)"

  # AC3 — a skipped multiple stays due (the modulo went silent here).
  local c; c=$(mk ac3 <<'M'
- [x] H1 — integration-hardening — checkpoint — x
- [x] 001 — a — spec-only — x
- [x] 002 — b — spec-only — x
- [x] 003 — c — spec-only — x
- [x] 004 — d — spec-only — x
- [x] 005 — e — spec-only — x
- [x] 006 — f — spec-only — x
- [x] 007 — g — spec-only — x
- [ ] 008 — h — spec-only — x
M
)
  out=$(engine "$c"); rc=$?
  [ "$out" = "since=H1 count=7 due=1" ] && [ "$rc" -eq 0 ] && ok "AC3 seven since H1 is still due" \
    || bad "AC3 got '$out' rc=$rc"

  # AC4 — no checkpoint ever; the standing T0 row is a pointer, not work.
  local d; d=$(mk ac4 <<'M'
- [x] T0 — harness-defects — standing — points at the template register
- [x] 001 — a — spec-only — x
- [x] 002 — b — full track — x
- [x] 003 — c — spec-only — x
- [x] 004 — d — spec-only — x
- [x] 005 — e — spec-only — x
- [ ] 006 — f — spec-only — x
M
)
  out=$(engine "$d"); rc=$?
  [ "$out" = "since=none count=5 due=1" ] && ok "AC4 no checkpoint yet: counted from the top, T0 skipped" \
    || bad "AC4 got '$out' rc=$rc"
  # A checkpoint recognised by its track alone, with an id that is not H-led.
  local d2; d2=$(mk ac4b <<'M'
- [x] 001 — a — spec-only — x
- [x] C1 — sweep — checkpoint — x
- [x] 002 — b — spec-only — x
M
)
  out=$(engine "$d2")
  [ "$out" = "since=C1 count=1 due=0" ] && ok "AC4 a checkpoint is recognised by its track field" \
    || bad "AC4 track-only checkpoint got '$out'"
  # A slug containing "checkpoint" is not a checkpoint (SC-1444's lesson).
  local d3; d3=$(mk ac4c <<'M'
- [x] H1 — integration-hardening — checkpoint — x
- [x] 001 — a — spec-only — x
- [x] 002 — checkpoint-cadence-counts-checkpoints — spec-only — x
- [x] 003 — c — spec-only — x
M
)
  out=$(engine "$d3")
  [ "$out" = "since=H1 count=3 due=0" ] && ok "AC4 'checkpoint' in a slug does not reset the count" \
    || bad "AC4 slug got '$out'"

  # AC5 — due, but the next row is the checkpoint: nothing to say.
  local e; e=$(mk ac5 <<'M'
- [x] 001 — a — spec-only — x
- [x] 002 — b — spec-only — x
- [x] 003 — c — spec-only — x
- [x] 004 — d — spec-only — x
- [x] 005 — e — spec-only — x
- [ ] H1 — integration-hardening — checkpoint — x
- [ ] 006 — f — spec-only — x
M
)
  grep -q "CHECKPOINT DUE" <<< "$(orient "$e")" && bad "AC5 alarm fires while the next row is the checkpoint" \
    || ok "AC5 no alarm while the next row is the checkpoint"

  # AC6 — project-maintenance reads the same engine.
  local m
  for m in "$b" "$a"; do
    cp "$SD/project-maintenance.sh" "$m/scripts/"
  done
  grep -q "\[HARDENING\] 5 feature specs since H1" <<< "$(cd "$b" && bash scripts/project-maintenance.sh 2>&1)" \
    && ok "AC6 project-maintenance reports the due checkpoint" \
    || bad "AC6 project-maintenance: $( (cd "$b" && bash scripts/project-maintenance.sh 2>&1) | grep -i hardening | head -2)"
  grep -q "\[HARDENING\]" <<< "$(cd "$a" && bash scripts/project-maintenance.sh 2>&1)" \
    && bad "AC6 project-maintenance reports a checkpoint at 4 feature specs" \
    || ok "AC6 project-maintenance stays quiet at 4 feature specs"

  # AC7 — no register is never "not due".
  mkdir -p "$T/empty"; bash "$ENGINE" --dir "$T/empty" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 4 ] && ok "AC7 no register exits 4" || bad "AC7 no register exit $rc, want 4"
}

run() { rm -rf "${T:?}"/ac* "$T/empty"; P=0; F=0; cases; }

ENGINE="$SD/checkpoint-cadence.sh"
echo "checkpoint-cadence"
run
echo "  $P passed, $F failed"
TOTAL_F=$F

# AC8 — sabotage. Each arm deletes one marked region of the engine; at least one case must go red.
# due-at-least is replaced rather than deleted, with the modulo it was written to remove.
echo "sabotage"
for arm in skip-checkpoint skip-carved due-at-least; do
  S="$T/sabotaged-$arm.sh"
  if [ "$arm" = due-at-least ]; then
    awk '/# region: due-at-least/{print; getline; print "    if (count > 0 && count % every == 0) due = 1"; next} {print}' "$SD/checkpoint-cadence.sh" > "$S"
  else
    awk -v r="$arm" '$0 ~ "# region: " r {skip=1} !skip {print} skip && /# endregion/ {skip=0}' "$SD/checkpoint-cadence.sh" > "$S"
  fi
  cmp -s "$S" "$SD/checkpoint-cadence.sh" && { bad "arm $arm changed nothing — the region marker is gone"; TOTAL_F=$((TOTAL_F+1)); continue; }
  ENGINE="$S"; run >/dev/null
  if [ "$F" -gt 0 ]; then echo "  PASS  arm $arm turns $F case(s) red"; else echo "  FAIL  arm $arm: every case stayed green"; TOTAL_F=$((TOTAL_F+1)); fi
done

[ "$TOTAL_F" -eq 0 ] && { echo "OK"; exit 0; } || { echo "FAILED ($TOTAL_F)"; exit 1; }
