#!/bin/bash
# test-archive-spec-history.sh — harness for scripts/archive-spec-history.sh.
#
# WHY THIS EXISTS: the archiver had ZERO tests. It shipped a positional split —
# "history" meant "every line below the heading" — and four scenario ledger
# blocks that had been appended below that heading were therefore swept into the
# archive as if they were history. Measured before the fix: 155 lines and 76 live
# "✓ validated" SC-ids left SCENARIOS.md in one run, and nothing reported it. A
# silent relocation of proven scenarios is a K5 miss.
#
# This comment used to say validate-scenario-traceability.sh "reported 100% and exit
# 0 the whole time". That script did not exist when this was written; the run went
# unwatched because nothing was watching. Spec 007bs built it — the gate is real now,
# and scripts/test-validate-scenario-traceability.sh is what stops IT becoming the
# next unwatched claim.
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
#
# THE BUDGET CASES CARRY NO SC- ID, DELIBERATELY. Spec 007bs built the traceability gate
# and measured what the ids above actually are: running it with --roots tests,scripts
# reports 15 DANGLING ids — SC-370, SC-758..SC-769 and their neighbours, every one of them
# written into a harness comment in this directory and none of them a row in the scenario
# map. That measurement is why the gate's default reference root is tests/ alone, and why
# scripts/project-maintenance.sh counts a dangling id as a finding rather than a note.
# Minting the next ten ids for the budget cases below would grow a set the project has
# already decided is a defect. (Those ids are deliberately not spelled out here, for the
# same reason the SC2086 lookalike further down is not: writing one would itself be a
# reference from scripts/ to an id the map does not own. The diagnostic run went 15 to 16
# the first time this comment named one, which is how the trap gets re-proved.) The cases
# are named descriptively instead; the names are the handle the sabotage arms match on,
# which is the only thing the ids were doing here anyway.
# Recorded in specs/007bt-history-entries-are-paragraphs/spec.md → Scope → Out.

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
# NB: fixture rows deliberately use 'ID-NNN', never 'SC-NNN'. A real id here would be
# picked up as a reference by scripts/validate-scenario-traceability.sh whenever it is
# pointed at scripts/, so a fixture would silently "trace" a real scenario it never
# exercises — the false-binding failure H5c and H5g both spent a row unpicking. Do not
# "fix" this back to SC-.
#
# That gate did not exist when this note was written (spec 007bs built it), but the note
# was right about what one would do, and it is now enforceable: running the gate with
# --roots tests,scripts reports 15 dangling ids, every one of them an id written into a
# harness comment in this directory. That is why its default reference root is tests/
# alone. Note also that the ID- trick does NOT transfer to the traceability harness:
# scenario-map-rows.sh hardcodes SC- in its row pattern, so an ID- fixture row there
# extracts to nothing — that harness composes its ids at runtime instead.
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

# ---- byte-budget fixtures (spec 007bt) ------------------------------------
# pad <n> — n bytes of 'x'. Built with awk rather than `head -c /dev/zero | tr` so it
# behaves identically on macOS, Linux and Git Bash (BSD head has no -c on some builds).
pad() { awk -v n="$1" 'BEGIN{ s=""; while (length(s) < n) s = s "xxxxxxxxxx"; print substr(s, 1, n) }'; }

# write_budget_scenarios <path> <fat-position> <pad-bytes>
# A well-formed newest-first map with 8 history entries, the one at <fat-position>
# (1 = newest) padded to roughly <pad-bytes>. Every other entry is comfortably inside
# the budget, so any report names exactly one entry and the case cannot pass by accident.
write_budget_scenarios() {
  path="$1"; fat="$2"; bytes="$3"
  cat > "$path" <<'EOF'
# Scenario map

## Actor: Admin

### Feature: Something   (spec: 001-something)

| ID     | Type  | Scenario        | Expected outcome | Status |
|--------|-------|-----------------|------------------|--------|
| ID-001 | happy | A thing happens | It works         | ✓      |

## Scenario history
EOF
  i=1
  for n in 8 7 6 5 4 3 2 1; do
    if [ "$i" -eq "$fat" ]; then
      printf -- '- 2026-08-0%s — %s\n' "$n" "$(pad "$bytes")" >> "$path"
    else
      printf -- '- 2026-08-0%s — entry number %s, one line as the rules require\n' "$n" "$n" >> "$path"
    fi
    i=$((i + 1))
  done
  return 0
}

# The byte length of the single history line whose date matches, as the shell sees it.
# Used to assert the script REPORTS the true size rather than an approximation.
entry_bytes() { LC_ALL=C awk -v d="$2" '$0 ~ ("^- " d) { print length($0); exit }' "$1"; }

# ---- ordering fixtures (row H7bb) -----------------------------------------
# write_dated_index <path> <heading> <date>...
# Entries are numbered top-to-bottom, so a case can assert WHICH end was archived rather
# than merely how many entries moved. That distinction is the whole row: the defect
# archived the right COUNT from the wrong END, and every case that existed at the time
# counted rather than looked.
write_dated_index() {
  path="$1"; heading="$2"; shift 2
  { echo "# Spec register"; echo; echo "## Specs"; echo
    echo "- [x] 001 — something — light track — a goal"; echo; echo "$heading"; } > "$path"
  i=0
  for d in "$@"; do i=$((i + 1)); printf -- '- %s — entry%s, one line as the rules require\n' "$d" "$i" >> "$path"; done
  return 0
}

# Which numbered entries ended up in the archive, comma-separated ("" when none).
archived_entries() { grep -ohE 'entry[0-9]+' "$1" 2>/dev/null | paste -sd, - ; }

# Six entries all carrying the same date — the shape observed live. More than --keep, and
# one shared date, is the entire trigger.
SAME_DATE_6="2026-08-28 2026-08-28 2026-08-28 2026-08-28 2026-08-28 2026-08-28"

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
elif ! grep -q 'archived 3 entries' <<< "$OUT"; then
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
elif ! grep -q 'FAULT' <<< "$OUT"; then
  bad "case3-ledger-block-refused" "no FAULT line in the output"
elif ! grep -q 'A block appended in the wrong place' <<< "$OUT"; then
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
elif grep -q 'would archive' <<< "$OUT"; then
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
elif ! grep -q 'no history section' <<< "$OUT"; then
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
elif ! grep -q 'INDEX.md — archived 3 entries' <<< "$OUT"; then
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
  # THE MAP MAY BE MORE THAN ONE FILE (spec 007bl). When specs/scenarios/ exists, the
  # index carries only per-feature id RANGES and the rows themselves live in the feature
  # files. Copying the index alone left this case counting 24 ids where it used to count
  # 188 — it went on passing, and the "ids in, ids out" line went on looking reassuring,
  # while covering an eighth of what it had. That is the exact shape of decay this case
  # exists to catch, so it had to learn the second layout rather than be trusted.
  if [ -d "$REPO_ROOT/specs/scenarios" ]; then
    mkdir -p "$sd/scenarios"
    cp "$REPO_ROOT"/specs/scenarios/*.md "$sd/scenarios/" 2>/dev/null || true
  fi
  # Counts every SC-id MENTIONED, not only those owned as a table row, so this total
  # runs above scripts/validate-scenario-traceability.sh's, which reads five-column
  # table rows only: prose mentions and flowchart labels inflate this grep and not the
  # gate. Harmless — the assertion is before == after on one file, so a constant offset
  # cannot mask a moved row.
  #
  # This note used to give the offset as exactly one, attributed to a shellcheck code
  # (SC2086) that one map row quotes while explaining it must not be read as an id. The
  # figure was never measured — the gate it compared against did not exist until spec
  # 007bs — and the lookalike it names has no hyphen, so neither this grep nor the gate
  # sees it. The offset is real; its size is not pinned, and nothing here depends on it.
  #
  # That lookalike is deliberately NOT spelled with a hyphen here: writing it out
  # would make this comment a reference from scripts/ to an id the map does not
  # own, i.e. an orphan. Observed while writing this very line.
  map_ids() { grep -rhoE 'SC-[0-9]+' "$1/SCENARIOS.md" "$1/scenarios" 2>/dev/null | sort -u | wc -l | tr -d ' '; }
  ids_before=$(map_ids "$sd")
  run_archiver "$sd"
  ids_after=$(map_ids "$sd")

  # A floor, so the case cannot quietly shrink to near-nothing again and keep passing.
  # 100 is well below the 188 the map holds today and well above the 24 the index alone
  # yields, so it fails loudly if the rows stop being reachable rather than reporting a
  # comfortable "n ids in, n ids out" about a map it can no longer see.
  if [ "$ids_before" -lt 100 ]; then
    bad "case11-real-map-is-well-formed" "only $ids_before ids visible — the map is not being read in full (split layout not picked up?)"
  fi
  # Exit 4 is NOT a refusal, and saying so would send the reader hunting for a ledger
  # block that is not there. Three distinct faults, three distinct sentences.
  if [ "$RC" -eq 3 ]; then
    bad "case11-real-map-is-well-formed" "the repo's own map is refused (exit 3) — a ledger block sits below the history heading"
  elif [ "$RC" -eq 4 ]; then
    bad "case11-real-map-is-well-formed" "the repo's own map is over budget (exit 4) — a kept history entry exceeds the per-entry byte budget; rewrite it to one sentence"
  elif [ "$RC" -ne 0 ]; then
    bad "case11-real-map-is-well-formed" "unexpected exit $RC"
  elif [ "$ids_before" != "$ids_after" ]; then
    bad "case11-real-map-is-well-formed" "archiving moved SC-ids out of the live map: $ids_before -> $ids_after"
  else
    ok "case11-real-map-is-well-formed  ($ids_before ids in, $ids_after ids out)"
  fi
fi

# ------------------------------------------- byte budget (spec 007bt) ----
# KEEP controls how MANY entries stay inline; --max-bytes controls how LARGE one may
# be. Before 007bt nothing measured the second, so specs/SCENARIOS.md carried three
# entries of 2075, 2634 and 2925 bytes — 88% of the section — through every check this
# project had, each of them one line and therefore "one line each" by the rule's letter.

# The budget is invisible on a compliant file: same output, same exit code as before.
sd=$(new_specs_dir); write_budget_scenarios "$sd/SCENARIOS.md" 0 0
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "budget-clean-silent" "expected exit 0 on a compliant map, got $RC"
elif grep -q 'OVER BUDGET' <<< "$OUT"; then
  bad "budget-clean-silent" "reported a budget fault on a map with no long entries"
elif ! grep -q 'archived 3 entries' <<< "$OUT"; then
  bad "budget-clean-silent" "the archiving behaviour changed: $(printf '%s' "$OUT" | tr '\n' ' ')"
else
  ok "budget-clean-silent"
fi

# The headline. A kept entry over the budget is named — with its line, its date and its
# TRUE size — and the run exits 4. The size is compared against the file itself, so an
# off-by-one or a locale-dependent length() cannot pass.
sd=$(new_specs_dir); write_budget_scenarios "$sd/SCENARIOS.md" 1 900
true_bytes=$(entry_bytes "$sd/SCENARIOS.md" 2026-08-08)
run_archiver "$sd"
if [ "$RC" -ne 4 ]; then
  bad "budget-over-reported" "expected exit 4, got $RC"
elif ! grep -q 'OVER BUDGET: SCENARIOS.md — 1 entry over the 300-byte budget' <<< "$OUT"; then
  bad "budget-over-reported" "no per-file report naming one entry: $(printf '%s' "$OUT" | tr '\n' ' ')"
elif ! grep -q "2026-08-08   ${true_bytes} bytes" <<< "$OUT"; then
  bad "budget-over-reported" "reported size is not the entry's true $true_bytes bytes: $(printf '%s' "$OUT" | tr '\n' ' ')"
elif ! grep -qE 'line (12|13) ' <<< "$OUT"; then
  bad "budget-over-reported" "no usable line number in the report: $(printf '%s' "$OUT" | tr '\n' ' ')"
else
  ok "budget-over-reported"
fi

# Exit 4 reports a cost; it does not veto the cleanup. Refusing to archive because a kept
# entry is too long would leave MORE bytes inline than completing the run does. This is
# the deliberate difference from exit 3, where writing is what does the damage.
if [ "$RC" -ne 4 ]; then
  bad "budget-writes-completed" "expected exit 4 from the previous run, got $RC — this case cannot say anything about writes under a verdict it did not get"
elif [ ! -f "$sd/SCENARIOS.history.md" ]; then
  bad "budget-writes-completed" "exit 4 suppressed the archiving — no archive file was written"
elif [ "$(grep -c '^- 2026-' "$sd/SCENARIOS.history.md" 2>/dev/null || echo 0)" -ne 3 ]; then
  bad "budget-writes-completed" "expected 3 entries archived despite the budget fault"
elif [ "$(grep -c '^- 2026-' "$sd/SCENARIOS.md")" -ne 5 ]; then
  bad "budget-writes-completed" "expected 5 entries kept inline despite the budget fault"
else
  ok "budget-writes-completed"
fi

# An over-budget entry that THIS RUN archives is not reported. It has stopped being read
# by the pipeline, and naming it would make the gate red about bytes the run just removed.
# This is why the budget is measured over the KEPT set, after the partition — the opposite
# of the foreign-content guard, which is measured over the whole region before it.
sd=$(new_specs_dir); write_budget_scenarios "$sd/SCENARIOS.md" 7 900
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "budget-archived-entry-not-reported" "expected exit 0 — the long entry was archived by this very run — got $RC"
elif grep -q 'OVER BUDGET' <<< "$OUT"; then
  bad "budget-archived-entry-not-reported" "reported an entry the run had just moved out of the live file"
elif ! grep -q 'xxxxxxxxxx' "$sd/SCENARIOS.history.md"; then
  bad "budget-archived-entry-not-reported" "the long entry did not reach the archive"
else
  ok "budget-archived-entry-not-reported"
fi

# --max-bytes 0 is the whole escape hatch: a project that wants the pre-007bt archiver
# gets one flag rather than a fork.
sd=$(new_specs_dir); write_budget_scenarios "$sd/SCENARIOS.md" 1 900
run_archiver "$sd" --max-bytes 0
if [ "$RC" -ne 0 ]; then
  bad "budget-disabled-at-zero" "expected exit 0 with the check disabled, got $RC"
elif grep -q 'OVER BUDGET' <<< "$OUT"; then
  bad "budget-disabled-at-zero" "reported a budget fault with --max-bytes 0"
else
  ok "budget-disabled-at-zero"
fi

# 3 BEATS 4. A refused file wrote nothing and still holds content that is not history, so
# its budget figure describes a region the caller does not have. The refusal is the fact
# to act on first — and the file must still be byte-identical afterwards.
sd=$(new_specs_dir); write_budget_scenarios "$sd/SCENARIOS.md" 1 900; append_ledger_block "$sd/SCENARIOS.md"
before=$(sha_of "$sd/SCENARIOS.md")
run_archiver "$sd"
if [ "$RC" -ne 3 ]; then
  bad "budget-refusal-wins" "expected exit 3 when a file is BOTH refused and over budget, got $RC"
elif [ "$(sha_of "$sd/SCENARIOS.md")" != "$before" ]; then
  bad "budget-refusal-wins" "the refused file was modified"
elif [ -f "$sd/SCENARIOS.history.md" ]; then
  bad "budget-refusal-wins" "an archive was written despite the refusal"
else
  ok "budget-refusal-wins"
fi

# A dry run that hides the fault teaches people that --dry-run is the safe way to not
# find out. It reports the entries that WOULD stay inline, exits 4, and writes nothing.
sd=$(new_specs_dir); write_budget_scenarios "$sd/SCENARIOS.md" 1 900
before=$(sha_of "$sd/SCENARIOS.md")
run_archiver "$sd" --dry-run
if [ "$RC" -ne 4 ]; then
  bad "budget-dry-run-exits-4" "expected exit 4 from --dry-run, got $RC"
elif ! grep -q 'OVER BUDGET: SCENARIOS.md' <<< "$OUT"; then
  bad "budget-dry-run-exits-4" "--dry-run stayed silent about the budget"
elif grep -q 'Archiving completed' <<< "$OUT"; then
  bad "budget-dry-run-exits-4" "--dry-run claimed archiving completed — nothing was written"
elif [ "$(sha_of "$sd/SCENARIOS.md")" != "$before" ] || [ -f "$sd/SCENARIOS.history.md" ]; then
  bad "budget-dry-run-exits-4" "--dry-run wrote to disk"
else
  ok "budget-dry-run-exits-4"
fi

# --dry-run must name the line the reader finds when they open the file NOW. Nothing was
# archived, so the kept entries have not shifted up under the heading.
if [ "$RC" -ne 4 ]; then
  bad "budget-dry-run-line-is-current" "expected exit 4 from the dry run, got $RC — no report to check a line number in"
elif ! grep -q 'line 12 ' <<< "$OUT"; then
  bad "budget-dry-run-line-is-current" "the dry-run report does not name the entry's current line 12: $(printf '%s' "$OUT" | tr '\n' ' ')"
else
  ok "budget-dry-run-line-is-current"
fi

# Same validation --keep already has. A negative value lands in the [!0-9] class, so it is
# rejected here rather than silently flagging every entry in the file.
sd=$(new_specs_dir); write_budget_scenarios "$sd/SCENARIOS.md" 0 0
run_archiver "$sd" --max-bytes banana
if [ "$RC" -ne 2 ]; then
  bad "budget-bad-arg-exits-2" "expected exit 2 for --max-bytes banana, got $RC"
else
  run_archiver "$sd" --max-bytes -5
  if [ "$RC" -ne 2 ]; then
    bad "budget-bad-arg-exits-2" "expected exit 2 for a negative --max-bytes, got $RC"
  else
    ok "budget-bad-arg-exits-2"
  fi
fi

# "Split the paragraph across lines" does not evade the budget — and it is NOT the budget
# that stops it. The foreign-content guard admits only dated entries and blank lines, so a
# continuation line is foreign content and the file is REFUSED at exit 3, one layer before
# the budget is computed. The requirement was written assuming the budget's per-entry
# summing closed this; measuring showed the hole was already shut. Assert what happens.
sd=$(new_specs_dir); write_budget_scenarios "$sd/SCENARIOS.md" 0 0
printf '  %s\n' "$(pad 290)" >> "$sd/SCENARIOS.md"
before=$(sha_of "$sd/SCENARIOS.md")
run_archiver "$sd"
if [ "$RC" -ne 3 ]; then
  bad "budget-multiline-refused-not-measured" "expected exit 3 — a continuation line is foreign content — got $RC"
elif [ "$(sha_of "$sd/SCENARIOS.md")" != "$before" ]; then
  bad "budget-multiline-refused-not-measured" "the refused file was modified"
else
  ok "budget-multiline-refused-not-measured"
fi

# ------------------------------------------------- ordering (row H7bb) ----
# --keep controls how MANY entries stay inline and --max-bytes how LARGE one may be.
# Neither says which END holds the newest entry, and getting that backwards archives the
# entry most likely to be read next while reporting "kept newest 5 inline". Before H7bb
# the answer came from one comparison — first entry's date strictly greater than the last
# entry's — so a section whose entries all shared a date fell through to keep-last and
# archived the top. Twenty-one cases were green at the time; not one of them used a
# section with a repeated date.

# The headline: all entries share a date, nothing declares the order, so nothing moves.
sd=$(new_specs_dir); write_dated_index "$sd/INDEX.md" "## Register history" $SAME_DATE_6
before=$(sha_of "$sd/INDEX.md")
run_archiver "$sd"
if [ "$RC" -ne 5 ]; then
  bad "order-same-date-undecided" "expected exit 5, got $RC — a coin flip was resolved as a verdict"
elif [ "$(sha_of "$sd/INDEX.md")" != "$before" ]; then
  bad "order-same-date-undecided" "the file was modified despite the undecided verdict"
elif [ -f "$sd/INDEX.history.md" ]; then
  bad "order-same-date-undecided" "an archive was written despite the undecided verdict"
elif ! grep -q 'UNDECIDED' <<< "$OUT"; then
  bad "order-same-date-undecided" "no UNDECIDED line in the output"
elif ! grep -q 'same date' <<< "$OUT"; then
  bad "order-same-date-undecided" "the message does not say WHY the dates are no help"
else
  ok "order-same-date-undecided"
fi

# Declared newest-first: the BOTTOM entry is the oldest, so entry6 is what leaves.
sd=$(new_specs_dir); write_dated_index "$sd/INDEX.md" "## Register history (newest first)" $SAME_DATE_6
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "order-declared-first-archives-the-bottom" "expected exit 0, got $RC"
elif [ "$(archived_entries "$sd/INDEX.history.md")" != "entry6" ]; then
  bad "order-declared-first-archives-the-bottom" "archived [$(archived_entries "$sd/INDEX.history.md")], expected entry6"
elif ! grep -q 'entry1,' "$sd/INDEX.md"; then
  bad "order-declared-first-archives-the-bottom" "the newest entry did not stay inline"
else
  ok "order-declared-first-archives-the-bottom"
fi

# The mirror. Same file, same dates, opposite declaration, opposite end archived — which
# is the proof that the declaration is what decides and not something incidental.
sd=$(new_specs_dir); write_dated_index "$sd/INDEX.md" "## Register history (newest last)" $SAME_DATE_6
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "order-declared-last-archives-the-top" "expected exit 0, got $RC"
elif [ "$(archived_entries "$sd/INDEX.history.md")" != "entry1" ]; then
  bad "order-declared-last-archives-the-top" "archived [$(archived_entries "$sd/INDEX.history.md")], expected entry1"
else
  ok "order-declared-last-archives-the-top"
fi

# Undeclared but unambiguously descending: entry6 is the oldest and the one that leaves.
# This is the path 22 of the 46 measured sections take, and nothing asserted its DIRECTION
# before this row — case1 counts three entries moved and never looks at which three.
sd=$(new_specs_dir)
write_dated_index "$sd/INDEX.md" "## Register history" 2026-08-06 2026-08-05 2026-08-04 2026-08-03 2026-08-02 2026-08-01
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "order-trend-first-archives-the-bottom" "expected exit 0, got $RC"
elif [ "$(archived_entries "$sd/INDEX.history.md")" != "entry6" ]; then
  bad "order-trend-first-archives-the-bottom" "archived [$(archived_entries "$sd/INDEX.history.md")], expected entry6"
else
  ok "order-trend-first-archives-the-bottom"
fi

# One mistyped date must not flip the verdict. Seven descending steps against one ascending
# clears the 2:1 bar, and real registers do contain the occasional wrong date — a rule that
# demanded strict monotonicity would strand the three largest registers measured (107, 53
# and 47 entries, all obviously newest-first).
sd=$(new_specs_dir)
write_dated_index "$sd/INDEX.md" "## Register history" 2026-08-09 2026-08-08 2026-08-07 2026-08-11 2026-08-05 2026-08-04 2026-08-03 2026-08-02
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "order-trend-survives-one-bad-date" "expected exit 0, got $RC — one inverted date sank a clear trend"
elif [ "$(archived_entries "$sd/INDEX.history.md")" != "entry6,entry7,entry8" ]; then
  bad "order-trend-survives-one-bad-date" "archived [$(archived_entries "$sd/INDEX.history.md")], expected entry6,entry7,entry8"
else
  ok "order-trend-survives-one-bad-date"
fi

# A genuinely unsorted section is refused rather than guessed. This is a real shape, copied
# from a measured register: equal ends, one step up in the middle and one back down. The old
# rule answered "newest-last" here and would have archived the eight newest entries.
sd=$(new_specs_dir)
write_dated_index "$sd/INDEX.md" "## Register history" 2026-06-01 2026-06-01 2026-06-02 2026-06-02 2026-06-02 2026-06-01
run_archiver "$sd"
if [ "$RC" -ne 5 ]; then
  bad "order-non-monotone-undecided" "expected exit 5, got $RC — a 1-against-1 trend was treated as evidence"
elif [ -f "$sd/INDEX.history.md" ]; then
  bad "order-non-monotone-undecided" "an archive was written despite the undecided verdict"
elif ! grep -q 'not consistently ordered' <<< "$OUT"; then
  bad "order-non-monotone-undecided" "the message does not distinguish this from the all-same-date case"
else
  ok "order-non-monotone-undecided"
fi

# A declaration that contradicts an unambiguous trend is not obeyed and not overruled —
# one of the two is wrong and the script cannot tell which, so it moves nothing.
sd=$(new_specs_dir)
write_dated_index "$sd/INDEX.md" "## Register history (newest last)" 2026-08-06 2026-08-05 2026-08-04 2026-08-03 2026-08-02 2026-08-01
run_archiver "$sd"
if [ "$RC" -ne 5 ]; then
  bad "order-declaration-contradicts-dates" "expected exit 5, got $RC"
elif [ -f "$sd/INDEX.history.md" ]; then
  bad "order-declaration-contradicts-dates" "an archive was written despite the contradiction"
elif ! grep -q 'declares newest-last' <<< "$OUT"; then
  bad "order-declaration-contradicts-dates" "the message does not name the declaration it disbelieved"
else
  ok "order-declaration-contradicts-dates"
fi

# The question is only asked when a partition would actually happen. Five same-date entries
# at --keep 5 move nothing whichever end is newest, and a gate that fires where nothing is
# at stake is one people learn to ignore — 20 of the 46 measured sections are this shape.
sd=$(new_specs_dir)
write_dated_index "$sd/INDEX.md" "## Register history" 2026-08-28 2026-08-28 2026-08-28 2026-08-28 2026-08-28
run_archiver "$sd"
if [ "$RC" -ne 0 ]; then
  bad "order-undecided-silent-below-keep" "expected exit 0, got $RC — asked a question with no consequence"
elif grep -q 'UNDECIDED' <<< "$OUT"; then
  bad "order-undecided-silent-below-keep" "reported UNDECIDED on a section that cannot partition"
else
  ok "order-undecided-silent-below-keep"
fi

# --dry-run reaches the same verdict. A dry run that says "would archive 1 entry" about a
# section whose order it cannot establish is a false green, exactly as it is for exit 3.
sd=$(new_specs_dir); write_dated_index "$sd/INDEX.md" "## Register history" $SAME_DATE_6
run_archiver "$sd" --dry-run
if [ "$RC" -ne 5 ]; then
  bad "order-dry-run-undecided" "expected exit 5, got $RC"
elif grep -q 'would archive' <<< "$OUT"; then
  bad "order-dry-run-undecided" "dry-run reported a planned archive on an undecided file"
else
  ok "order-dry-run-undecided"
fi

# One undecided file must not cancel unrelated correct work — the same property case10
# pins for exit 3, and for the same reason: a non-zero `return` under `set -e` would kill
# the run before the sibling was ever examined.
sd=$(new_specs_dir)
write_dated_index "$sd/INDEX.md" "## Register history" $SAME_DATE_6
write_clean_scenarios "$sd/SCENARIOS.md"
run_archiver "$sd"
if [ "$RC" -ne 5 ]; then
  bad "order-undecided-does-not-block-sibling" "expected exit 5, got $RC"
elif ! grep -q 'SCENARIOS.md — archived 3 entries' <<< "$OUT"; then
  bad "order-undecided-does-not-block-sibling" "the clean sibling was not processed: $(printf '%s' "$OUT" | tr '\n' ' ')"
elif [ -f "$sd/INDEX.history.md" ]; then
  bad "order-undecided-does-not-block-sibling" "the undecided file was archived anyway"
else
  ok "order-undecided-does-not-block-sibling"
fi

# 3 BEATS 5. A refused file wrote nothing AND still holds content that is not history, so
# its ordering verdict describes a region the caller does not have. Both faults present,
# exit 3 is what surfaces.
sd=$(new_specs_dir)
write_dated_index "$sd/INDEX.md" "## Register history" $SAME_DATE_6
write_clean_scenarios "$sd/SCENARIOS.md"; append_ledger_block "$sd/SCENARIOS.md"
run_archiver "$sd"
if [ "$RC" -ne 3 ]; then
  bad "order-refusal-outranks-undecided" "expected exit 3 when both faults are present, got $RC"
else
  ok "order-refusal-outranks-undecided"
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
  expected_red="case3-ledger-block-refused case4-dry-run-refused case5-keep-independent case6-undated-bullet-refused case7-horizontal-rule-refused case10-mixed-clean-and-foul order-refusal-outranks-undecided"
  missing=""
  for c in $expected_red; do
    grep -q "FAIL  $c" <<< "$sab_out" || missing="$missing $c"
  done

  if [ -n "$missing" ]; then
    echo "  FAIL  sabotage — these cases stayed GREEN without the guard:$missing"
    echo "        They therefore prove nothing about the shipped script."
    exit 1
  fi
  echo "  PASS  sabotage — all 6 refusal cases go red without the guard"

  # Second, INDEPENDENT arm: neutralise the BYTE BUDGET (spec 007bt) and require the
  # budget cases to go red by name. One sabotage cannot vouch for two guards — stripping
  # the foreign-content guard leaves every budget case green, which is exactly how a new
  # check gets added under an existing falsification arm and inherits credit it never
  # earned. So the budget gets its own arm, felling its own named cases.
  sab2=$(mktemp -d)/archive-nobudget.sh
  sed 's/if \[ "\$MAX_BYTES" -eq 0 \]; then return 0; fi/if true; then return 0; fi/' "$SCRIPT" > "$sab2"

  if ! grep -q 'if true; then return 0; fi' "$sab2"; then
    echo "  FAIL  sabotage-budget — could not neutralise the budget check; the harness cannot prove anything"
    exit 1
  fi

  sab2_out=$(bash "$0" --script "$sab2" --no-sabotage 2>&1)
  expected_red2="budget-over-reported budget-writes-completed budget-dry-run-exits-4 budget-dry-run-line-is-current"
  missing2=""
  for c in $expected_red2; do
    grep -q "FAIL  $c" <<< "$sab2_out" || missing2="$missing2 $c"
  done

  if [ -n "$missing2" ]; then
    echo "  FAIL  sabotage-budget — these cases stayed GREEN without the budget check:$missing2"
    echo "        They therefore prove nothing about the shipped script."
    exit 1
  fi

  # And the cases that SHOULD survive it must survive it. A budget arm that fells
  # everything is not measuring the budget, it is measuring that the copy is broken —
  # the false-green shape inverted, and just as useless.
  survivors="budget-clean-silent budget-disabled-at-zero budget-refusal-wins budget-multiline-refused-not-measured budget-archived-entry-not-reported budget-bad-arg-exits-2"
  wrongly_red=""
  for c in $survivors; do
    grep -q "FAIL  $c" <<< "$sab2_out" && wrongly_red="$wrongly_red $c"
  done
  if [ -n "$wrongly_red" ]; then
    echo "  FAIL  sabotage-budget — these cases went red for a check they do not exercise:$wrongly_red"
    exit 1
  fi
  echo "  PASS  sabotage-budget — 4 budget cases go red without the check, 6 unrelated ones stay green"

  # Third, INDEPENDENT arm: neutralise the ORDERING DECISION (row H7bb) and require the
  # ordering cases to go red by name. The two arms above leave every one of them green —
  # they exercise the foreign-content guard and the byte budget, and the archiver decided
  # which end to keep quite happily without either. That is exactly how a new check gets
  # bolted under an existing falsification arm and inherits credit it never earned, so the
  # ordering gets its own arm.
  #
  # The sabotage restores the DEFECT, not merely a broken script: forcing the verdict to
  # "last" is the answer the old code fell through to whenever its one comparison came out
  # false. So this arm asks the harness the question the row is about — would these cases
  # have caught the bug that shipped? — rather than the weaker "does anything change".
  sab3=$(mktemp -d)/archive-keeplast.sh
  sed 's/      asc = 0; desc = 0$/      print "last"; exit; &/' "$SCRIPT" > "$sab3"

  if ! grep -q 'print "last"; exit;' "$sab3"; then
    echo "  FAIL  sabotage-order — could not force the ordering verdict; the harness cannot prove anything"
    exit 1
  fi

  sab3_out=$(bash "$0" --script "$sab3" --no-sabotage 2>&1)
  expected_red3="order-same-date-undecided order-declared-first-archives-the-bottom order-trend-first-archives-the-bottom order-trend-survives-one-bad-date order-non-monotone-undecided order-declaration-contradicts-dates order-dry-run-undecided order-undecided-does-not-block-sibling"
  missing3=""
  for c in $expected_red3; do
    grep -q "FAIL  $c" <<< "$sab3_out" || missing3="$missing3 $c"
  done

  if [ -n "$missing3" ]; then
    echo "  FAIL  sabotage-order — these cases stayed GREEN with the old keep-last verdict forced:$missing3"
    echo "        They therefore prove nothing about the shipped script."
    exit 1
  fi

  # And the three that SHOULD survive it must. One of them — order-declared-last-archives-the-top —
  # expects exactly what the sabotage forces, which is what makes it the sharpest survivor here:
  # if it went red, the sabotage broke something other than the verdict.
  survivors3="order-declared-last-archives-the-top order-undecided-silent-below-keep order-refusal-outranks-undecided case1-clean-archives"
  wrongly_red3=""
  for c in $survivors3; do
    grep -q "FAIL  $c" <<< "$sab3_out" && wrongly_red3="$wrongly_red3 $c"
  done
  if [ -n "$wrongly_red3" ]; then
    echo "  FAIL  sabotage-order — these cases went red for a check they do not exercise:$wrongly_red3"
    exit 1
  fi
  echo "  PASS  sabotage-order — 8 ordering cases go red with the old verdict forced, 4 unrelated ones stay green"

  # The clean-input cases must still pass while sabotaged: they measure the
  # archiver's original behaviour, not the guard. If they went red too, the
  # sabotage broke the script wholesale and the red above would be meaningless.
  for c in case1-clean-archives case2-prose-with-markup-admitted; do
    if grep -q "FAIL  $c" <<< "$sab_out"; then
      echo "  FAIL  sabotage — $c also broke, so the sabotage was not surgical"
      exit 1
    fi
  done
  echo "  PASS  sabotage — the clean-input cases stay green, so the sabotage was surgical"
fi

[ "$FAIL" -eq 0 ] || exit 1
exit 0
