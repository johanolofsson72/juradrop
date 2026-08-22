#!/bin/bash
# test-archive-spec-history.sh — harness for scripts/archive-spec-history.sh.
#
# WHY THIS EXISTS: the archiver had ZERO tests. It shipped a positional split —
# "history" meant "every line below the heading" — and four scenario ledger
# blocks that had been appended below that heading were therefore swept into the
# archive as if they were history. Measured before the fix: 155 lines and 76 live
# "✓ validated" SC-ids left SCENARIOS.md in one run, while
# validate-scenario-traceability.sh reported 100% and exit 0 the whole time
# (it reads both files). A silent relocation of proven scenarios is a K5 miss.
# Row H5j added the guard; this harness is what stops the guard from becoming
# the next unwatched claim.
#
# It runs the archiver against generated fixtures in a temp dir — never against
# the repo's real specs/ — and it checks its own teeth: the final step sabotages
# a COPY of the archiver and requires the named refusal cases to go red. A gate
# nobody has watched fail is a report, not a gate (the H5b lesson, restated by
# H5g's SC-370 where a harness sat green and unrun for months).
#
# Usage:
#   bash scripts/test-archive-spec-history.sh              # test the shipped script
#   bash scripts/test-archive-spec-history.sh --script X   # test some other copy
#   bash scripts/test-archive-spec-history.sh --no-sabotage
#
# Exit: 0 all cases passed · 1 one or more failed.
#
# Covers SC-758/759/760/761/762/763/764/765/766/767/768/769.

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO_ROOT/scripts/archive-spec-history.sh"
RUN_SABOTAGE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --script) SCRIPT="$2"; shift 2 ;;
    --no-sabotage) RUN_SABOTAGE=0; shift ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -f "$SCRIPT" ] || { echo "script under test not found: $SCRIPT" >&2; exit 2; }

PASS=0; FAIL=0; FAILED_CASES=""

ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_CASES="$FAILED_CASES $1"; printf '  FAIL  %s — %s\n' "$1" "$2"; }

# ---------------------------------------------------------------- fixtures --

# A well-formed map: real content above the heading, dated one-line entries below.
# Newest-first, matching how this repo's register actually orders them.
#
# NB: fixture rows deliberately use 'ID-NNN', never 'SC-NNN'. An SC-id here would
# be picked up by validate-scenario-traceability.sh as a reference from scripts/,
# so a fixture would silently "trace" a real scenario it never exercises — the
# false-binding failure H5c and H5g both spent a row unpicking. Do not "fix" this
# back to SC-.
write_clean_scenarios() { # <path> [extra-entry-text]
  cat > "$1" <<'EOF'
# Scenario map

## Actor: Admin

### Feature: Something   (spec: 001-something)

| ID     | Type  | Scenario        | Expected outcome | Status |
|--------|-------|-----------------|------------------|--------|
| ID-001 | happy | A thing happens | It works         | ✓      |

## Scenario history
EOF
  # 8 entries, newest first.
  for n in 8 7 6 5 4 3 2 1; do
    printf -- '- 2026-08-0%s — entry number %s, one line as the rules require\n' "$n" "$n" >> "$1"
  done
  [ -n "${2:-}" ] && printf -- '%s\n' "$2" >> "$1"
  return 0
}

write_clean_index() { # <path>
  cat > "$1" <<'EOF'
# Spec register

## Specs

- [x] 001 — something — light track — a goal

## Register history
EOF
  for n in 8 7 6 5 4 3 2 1; do
    printf -- '- 2026-08-0%s — register entry %s\n' "$n" "$n" >> "$1"
  done
  return 0
}

# The defect this row fixes: a ledger block appended BELOW the history heading.
append_ledger_block() { # <path>
  cat >> "$1" <<'EOF'

### Feature: A block appended in the wrong place   (spec: X1-somewhere)

Prose explaining the block.

| ID     | Type        | Scenario           | Expected outcome | Status |
|--------|-------------|--------------------|------------------|--------|
| ID-900 | adversarial | Something hostile  | It is refused    | ✓      |
EOF
}

new_specs_dir() { d=$(mktemp -d); mkdir -p "$d/specs"; echo "$d/specs"; }

# Run the script under test; capture output and exit code without tripping set -e.
run_archiver() { # <specs-dir> [extra args...]
  sd="$1"; shift
  OUT=$(bash "$SCRIPT" --dir "$sd" "$@" 2>&1)
  RC=$?
  return 0
}

sha_of() { shasum "$1" | awk '{print $1}'; }

echo "Testing: $SCRIPT"
echo

# ------------------------------------------------------------------ cases --

# SC-758 — the guard is invisible on clean input: archiving still works.
sd=$(new_specs_dir); write_clean_scenarios "$sd/SCENARIOS.md"
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "case1-clean-archives" "expected exit 0, got $RC"
elif ! printf '%s' "$OUT" | grep -q 'archived 3 entries'; then
  bad "case1-clean-archives" "expected 3 entries archived; got: $(printf '%s' "$OUT" | tr '\n' ' ')"
elif [ "$(grep -c '^- 2026-' "$sd/SCENARIOS.md")" -ne 5 ]; then
  bad "case1-clean-archives" "expected 5 entries kept inline, got $(grep -c '^- 2026-' "$sd/SCENARIOS.md")"
elif [ "$(grep -c '^- 2026-' "$sd/SCENARIOS.history.md")" -ne 3 ]; then
  bad "case1-clean-archives" "expected 3 entries archived to the sibling file"
elif ! grep -q 'ID-001' "$sd/SCENARIOS.md"; then
  bad "case1-clean-archives" "the live ledger row left the file"
else
  ok "case1-clean-archives"
fi

# SC-759 — a history entry whose prose quotes '#', '|' and a bare date is still
# admitted. The guard anchors at line start; the real entries quote all three.
sd=$(new_specs_dir)
write_clean_scenarios "$sd/SCENARIOS.md" '- 2026-08-09 — quotes ## Scenario history and a | pipe and 2026-01-01 mid-sentence'
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "case2-prose-with-markup-admitted" "expected exit 0, got $RC — the guard matched inside prose"
else
  ok "case2-prose-with-markup-admitted"
fi

# SC-760, SC-743 — the headline: a ledger block below the heading is REFUSED,
# exit 3, and the file is left byte-identical. SC-743 is the carve that named the
# defect (155 lines, 76 live ids, four blocks); this case is its closure.
sd=$(new_specs_dir); write_clean_scenarios "$sd/SCENARIOS.md"; append_ledger_block "$sd/SCENARIOS.md"
before=$(sha_of "$sd/SCENARIOS.md")
run_archiver "$sd"
if [ "$RC" -ne 3 ]; then
  bad "case3-ledger-block-refused" "expected exit 3, got $RC"
elif [ "$(sha_of "$sd/SCENARIOS.md")" != "$before" ]; then
  bad "case3-ledger-block-refused" "file was modified despite the refusal"
elif [ -f "$sd/SCENARIOS.history.md" ]; then
  bad "case3-ledger-block-refused" "an archive was written despite the refusal"
elif ! printf '%s' "$OUT" | grep -q 'FAULT'; then
  bad "case3-ledger-block-refused" "no FAULT line in the output"
elif ! printf '%s' "$OUT" | grep -q 'A block appended in the wrong place'; then
  bad "case3-ledger-block-refused" "the message does not quote the offending line"
else
  ok "case3-ledger-block-refused"
fi

# SC-761 — --dry-run refuses identically. A dry run that reports "would archive
# 3 entries" on a foul file is a false green.
sd=$(new_specs_dir); write_clean_scenarios "$sd/SCENARIOS.md"; append_ledger_block "$sd/SCENARIOS.md"
run_archiver "$sd" --dry-run
if [ "$RC" -ne 3 ]; then
  bad "case4-dry-run-refused" "expected exit 3, got $RC"
elif printf '%s' "$OUT" | grep -q 'would archive'; then
  bad "case4-dry-run-refused" "dry-run reported a planned archive on a foul file"
else
  ok "case4-dry-run-refused"
fi

# SC-762 — the verdict is independent of --keep. At --keep 99 nothing would have
# moved anyway; the file is still malformed and is still refused. A guard that
# passed here would be a function of an unrelated flag.
sd=$(new_specs_dir); write_clean_scenarios "$sd/SCENARIOS.md"; append_ledger_block "$sd/SCENARIOS.md"
run_archiver "$sd" --keep 99
if [ "$RC" -ne 3 ]; then
  bad "case5-keep-independent" "expected exit 3 at --keep 99, got $RC"
else
  ok "case5-keep-independent"
fi

# SC-763 — an UNDATED bullet is refused too. The rule is '- YYYY-MM-DD', not
# merely 'starts with a dash'.
sd=$(new_specs_dir); write_clean_scenarios "$sd/SCENARIOS.md"
printf -- '- some loose note nobody dated\n' >> "$sd/SCENARIOS.md"
run_archiver "$sd"
if [ "$RC" -ne 3 ]; then
  bad "case6-undated-bullet-refused" "expected exit 3, got $RC"
else
  ok "case6-undated-bullet-refused"
fi

# SC-764 — a horizontal rule is foreign content. It is not a dated bullet, and
# the one in the real map belonged to a misplaced ledger block.
sd=$(new_specs_dir); write_clean_scenarios "$sd/SCENARIOS.md"
printf -- '\n---\n' >> "$sd/SCENARIOS.md"
run_archiver "$sd"
if [ "$RC" -ne 3 ]; then
  bad "case7-horizontal-rule-refused" "expected exit 3, got $RC"
else
  ok "case7-horizontal-rule-refused"
fi

# SC-765 — no history heading at all is NOT a fault. A guard that cried wolf on
# a fresh project would be bypassed within a week.
sd=$(new_specs_dir)
printf '# Scenario map\n\n## Actor: Admin\n\n| SC-001 | happy | x | y | ✓ |\n' > "$sd/SCENARIOS.md"
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "case8-no-history-section-ok" "expected exit 0, got $RC"
elif ! printf '%s' "$OUT" | grep -q 'no history section'; then
  bad "case8-no-history-section-ok" "expected the existing skip path"
else
  ok "case8-no-history-section-ok"
fi

# SC-766 — a heading with an EMPTY region is not a fault either. Zero entries is
# a legitimate state, not foreign content.
sd=$(new_specs_dir)
printf '# Scenario map\n\n## Actor: Admin\n\n## Scenario history\n' > "$sd/SCENARIOS.md"
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "case9-empty-region-ok" "expected exit 0, got $RC"
else
  ok "case9-empty-region-ok"
fi

# SC-767 — one foul file must not cancel unrelated correct work, and correct work
# must not mask the fault. INDEX archives, SCENARIOS refuses, overall exit 3.
# This is the case that catches a refusal implemented as a non-zero `return`:
# under `set -e` that would kill the script before SCENARIOS was ever examined.
sd=$(new_specs_dir)
write_clean_index "$sd/INDEX.md"
write_clean_scenarios "$sd/SCENARIOS.md"; append_ledger_block "$sd/SCENARIOS.md"
scen_before=$(sha_of "$sd/SCENARIOS.md")
run_archiver "$sd"
if [ "$RC" -ne 3 ]; then
  bad "case10-mixed-clean-and-foul" "expected exit 3, got $RC"
elif ! printf '%s' "$OUT" | grep -q 'INDEX.md — archived 3 entries'; then
  bad "case10-mixed-clean-and-foul" "the clean sibling was not processed: $(printf '%s' "$OUT" | tr '\n' ' ')"
elif [ "$(sha_of "$sd/SCENARIOS.md")" != "$scen_before" ]; then
  bad "case10-mixed-clean-and-foul" "the refused file was modified"
else
  ok "case10-mixed-clean-and-foul"
fi

# SC-768 — the real repo's own map is well-formed. This is the regression that
# would catch a future ledger block being appended below the heading again.
if [ -f "$REPO_ROOT/specs/SCENARIOS.md" ] && [ "$SCRIPT" = "$REPO_ROOT/scripts/archive-spec-history.sh" ]; then
  sd=$(new_specs_dir)
  cp "$REPO_ROOT/specs/SCENARIOS.md" "$sd/SCENARIOS.md"
  cp "$REPO_ROOT/specs/INDEX.md" "$sd/INDEX.md"
  # Counts every SC-id MENTIONED, not only those owned as a table row, so this
  # total runs one above validate-scenario-traceability.sh's: one map row quotes
  # a shellcheck code (SC2086) while explaining it must not be read as an id, and
  # this naive grep sees the lookalike. Harmless — the assertion is before ==
  # after on one file, so a constant offset cannot mask a moved row.
  #
  # That lookalike is deliberately NOT spelled with a hyphen here: writing it out
  # would make this comment a reference from scripts/ to an id the map does not
  # own, i.e. an orphan. Observed while writing this very line.
  ids_before=$(grep -oE 'SC-[0-9]+' "$sd/SCENARIOS.md" | sort -u | wc -l | tr -d ' ')
  run_archiver "$sd"
  ids_after=$(grep -oE 'SC-[0-9]+' "$sd/SCENARIOS.md" | sort -u | wc -l | tr -d ' ')
  if [ "$RC" -ne 0 ]; then
    bad "case11-real-map-is-well-formed" "the repo's own map is refused (exit $RC) — a ledger block sits below the history heading"
  elif [ "$ids_before" != "$ids_after" ]; then
    bad "case11-real-map-is-well-formed" "archiving moved SC-ids out of the live map: $ids_before -> $ids_after"
  else
    ok "case11-real-map-is-well-formed  ($ids_before ids in, $ids_after ids out)"
  fi
fi

echo
echo "  passed: $PASS   failed: $FAIL"

# ------------------------------------------------------------- sabotage ----
# SC-769 — the harness checks its own teeth. Neutralise the guard in a COPY and require
# the refusal cases to go red BY NAME. Asserting only "the sabotaged run exits
# non-zero" would be satisfied by a copy that died of a syntax error, which is
# the false-green shape this whole row exists to remove.
if [ "$RUN_SABOTAGE" -eq 1 ] && [ "$FAIL" -eq 0 ]; then
  echo
  echo "Sabotage check — the guard must be load-bearing:"
  sab=$(mktemp -d)/archive-sabotaged.sh
  sed 's/if \[ -n "\$foreign" \]; then/if [ -n "" ]; then/' "$SCRIPT" > "$sab"

  if ! grep -q 'if \[ -n "" \]; then' "$sab"; then
    echo "  FAIL  sabotage — could not neutralise the guard; the harness cannot prove anything"
    exit 1
  fi

  sab_out=$(bash "$0" --script "$sab" --no-sabotage 2>&1)
  expected_red="case3-ledger-block-refused case4-dry-run-refused case5-keep-independent case6-undated-bullet-refused case7-horizontal-rule-refused case10-mixed-clean-and-foul"
  missing=""
  for c in $expected_red; do
    printf '%s' "$sab_out" | grep -q "FAIL  $c" || missing="$missing $c"
  done

  if [ -n "$missing" ]; then
    echo "  FAIL  sabotage — these cases stayed GREEN without the guard:$missing"
    echo "        They therefore prove nothing about the shipped script."
    exit 1
  fi
  echo "  PASS  sabotage — all 6 refusal cases go red without the guard"

  # The clean-input cases must still pass while sabotaged: they measure the
  # archiver's original behaviour, not the guard. If they went red too, the
  # sabotage broke the script wholesale and the red above would be meaningless.
  for c in case1-clean-archives case2-prose-with-markup-admitted; do
    if printf '%s' "$sab_out" | grep -q "FAIL  $c"; then
      echo "  FAIL  sabotage — $c also broke, so the sabotage was not surgical"
      exit 1
    fi
  done
  echo "  PASS  sabotage — the clean-input cases stay green, so the sabotage was surgical"
fi

[ "$FAIL" -eq 0 ] || exit 1
exit 0
