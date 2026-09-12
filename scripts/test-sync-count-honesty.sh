#!/usr/bin/env bash
# test-sync-count-honesty.sh — the sync's headline must describe the commit it made.
#
# Spec 007an. `scripts/template-autosync.sh` used to count entries in its own
# $WROTE/$ADDED lists, i.e. what it wrote to the WORKING TREE, and print that as
# "N updated, M added" in both the session banner and the commit subject. The
# repository does not always agree: a write can land on bytes identical to HEAD,
# or on a path git ignores, and in both cases the sync wrote a file and the commit
# carries nothing. Measured across msroute's history, 11 of 17 auto-messaged sync
# commits claimed more than they carried, and never fewer.
#
# Two modes:
#   (default)   build a fixture that reproduces both causes, run a real sync, and
#               assert the headline equals the commit, and that each written-but-
#               unrecorded file is named with a reason.
#   --history   walk this repo's own sync commits, compare each claim against its
#               diff, and hold a commit to the honest standard only when the
#               version of template-autosync.sh IN THAT COMMIT'S TREE already has
#               the fix. No hard-coded sha, no hand-maintained list — the marker
#               travels with the code through rebases and cherry-picks, and is
#               correct in every project the template lands in, on whatever day it
#               happens to arrive.
#
# --history sorts a diverging commit into THREE classes, not two (spec 007cb). The two it had were
# both verdicts about template-autosync.sh — "pre-fix history" or "post-fix regression" — and a
# subject that was rewritten by hand after the sync made it is neither. Measured: one such commit
# exists in this estate and it was the only failure --history had, in a repo where re-running the
# sync from the same template SHA over the same parent reproduces the honest count. So the third
# class is not a tolerance added to make a red gate green; it is the difference between a claim the
# script made and a claim somebody else made about it.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
SYNC="$SELF_DIR/template-autosync.sh"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

# The marker the --history mode looks for. It is a string that exists only in a
# fixed template-autosync.sh, and it is deliberately NOT a version number: a
# number has to be remembered and bumped, a behavioural marker cannot drift from
# the behaviour it marks.
FIX_MARKER='STAGED_COUNT_IS_THE_HEADLINE'

# Spec 007cb. The first line of the body `template-autosync.sh` gives its commit, passed as a
# second `-m` to the one `git commit` the script has — the `(stamp advance)` arm shares that call,
# so every sync-authored commit carries it and no other code path writes it.
#
# It is the discriminator because a rewritten subject is indistinguishable from a miscounted one by
# arithmetic alone, and the arithmetic is all --history used to have. Measured across every repo
# in this estate that has sync commits: 288 commits whose subject has the sync's shape, 287 with
# this body, 1 without — and the one without was the only thing --history was failing on. Perfect
# separation on the whole observed population is what makes it evidence rather than a guess.
#
# The rejected alternative was to also test the template SHA's length (a sync-authored subject
# carries `--short=12`, and the failing one carried 7). It is real corroboration and a bad gate:
# `resolve_local_template` appends `-dirty-<timestamp>` when the template clone is dirty and falls
# back to `local-unknown` when it is not a git repo, so a length test needs two exemptions and can
# be falsified by a third. This needs none.
SYNC_BODY_MARKER='Deterministic template sync'

# ---------------------------------------------------------------- history mode
history_mode() {
  local repo="${1:-$(cd "$SELF_DIR/.." && pwd)}"
  printf '\n[history] auto-messaged sync commits in %s\n' "$repo"
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "  (not a git repo — skipped)"; return 0; }

  local shas legacy=0 checked=0 amended=0
  shas=$(git -C "$repo" log --format=%H --grep='chore(sync)' 2>/dev/null)
  [ -n "$shas" ] || { echo "  (no sync commits — nothing to check)"; return 0; }

  local sha subj claimed_u claimed_a actual_m actual_a fixed authored
  for sha in $shas; do
    subj=$(git -C "$repo" log -1 --format=%s "$sha")
    case "$subj" in *" updated, "*" added"*) ;; *) continue ;; esac
    claimed_u=$(printf '%s' "$subj" | sed -n 's/.*— \([0-9][0-9]*\) updated, \([0-9][0-9]*\) added.*/\1/p')
    claimed_a=$(printf '%s' "$subj" | sed -n 's/.*— \([0-9][0-9]*\) updated, \([0-9][0-9]*\) added.*/\2/p')
    [ -n "$claimed_u" ] && [ -n "$claimed_a" ] || continue

    actual_m=$(git -C "$repo" show --numstat --format= --diff-filter=M "$sha" 2>/dev/null \
               | awk '$3 != ".claude/.template-sync" && NF {n++} END{print n+0}')
    actual_a=$(git -C "$repo" show --numstat --format= --diff-filter=A "$sha" 2>/dev/null \
               | awk '$3 != ".claude/.template-sync" && NF {n++} END{print n+0}')

    # Did the sync write this message at all? Asked BEFORE the fix marker, and the order is the
    # whole point: the marker answers "was the fix in the tree this commit built?", which is only a
    # question about template-autosync.sh if template-autosync.sh wrote the sentence being checked.
    # Asked in the other order, a subject somebody rewrote by hand is reported as a regression in a
    # script that counted correctly — an accusation the evidence does not support.
    authored=1
    # Not a pipeline into grep -q, deliberately: under `set -o pipefail` that returns 141 as soon as
    # the body after the match fills the pipe buffer, which reads a commit that DOES carry the marker
    # as one that does not. scripts/validate-no-sigpipe-assertions.sh names this shape (row H7x); the
    # here-string is the fix it prescribes, and it costs one variable.
    _body=$(git -C "$repo" log -1 --format=%b "$sha" 2>/dev/null)
    grep -q "^$SYNC_BODY_MARKER" <<< "$_body" || authored=0

    # Was the fix already in the tree this commit produced? That is what decides
    # whether this commit is history or a regression.
    fixed=0
    [ "$authored" -eq 1 ] && grep -q "$FIX_MARKER" \
      <<< "$(git -C "$repo" show "$sha:scripts/template-autosync.sh" 2>/dev/null)" && fixed=1

    if [ "$claimed_u" = "$actual_m" ] && [ "$claimed_a" = "$actual_a" ]; then
      # Counted only when the sync wrote the message. A rewritten subject that happens to be right
      # is not evidence that the script is right, and letting it raise this number would inflate the
      # one figure the green line offers as proof that anything was checked.
      #
      # ONE test, not two. `fixed` is computed under `authored` above and is therefore 0 for every
      # message the sync did not write, so `[ "$authored" -eq 1 ] && [ "$fixed" -eq 1 ]` was two
      # defences of which only one could ever be shown to work: the mutation that deletes the
      # authored half leaves the whole arm green, which is this project's own recorded shape for a
      # guard that is decoration (H7bd ARM-5). The coupling is deliberate and it lives at `fixed`.
      [ "$fixed" -eq 1 ] && checked=$((checked+1))
      continue
    fi

    if [ "$authored" -eq 0 ]; then
      # Reported, never silenced. The claim in the subject is still false and still published, so a
      # mode that walks published commits has to name it; what it must not do is attribute it. The
      # sentence says what was measured (the body is missing) rather than what is inferred (somebody
      # amended it), because only the first is in the repository.
      #
      # What this class costs, said plainly: a commit that is BOTH hand-amended AND a genuine
      # regression now lands here and does not fail. That hole cannot be closed from history — a
      # rewritten message carries no evidence about what the script wrote — so the choice is between
      # misattributing it and declining to attribute it. The fixture mode is the arm that actually
      # runs the sync and is the primary evidence; this mode corroborates over published commits.
      amended=$((amended+1))
      info "${sha%${sha#???????}} claims ${claimed_u}/${claimed_a}, commit has ${actual_m}/${actual_a} — the sync did not write this message"
      info "  $subj"
    elif [ "$fixed" -eq 1 ]; then
      bad "${sha%${sha#???????}} claims ${claimed_u}/${claimed_a}, commit has ${actual_m}/${actual_a} — created WITH the fix in tree"
      info "  $subj"
    else
      legacy=$((legacy+1))
    fi
  done

  # Both summaries are written only when they have something to summarise. A line that is always
  # there is a line nobody reads, which is the failure mode this whole file exists to report on.
  if [ "$amended" -gt 0 ]; then
    info "$amended sync commit(s) carry a message the sync did not write (no '$SYNC_BODY_MARKER' body)."
    info "Their counts say nothing about template-autosync.sh and are not held to it."
  fi
  if [ "$legacy" -gt 0 ]; then
    info "$legacy pre-fix commit(s) diverge. Recorded as history — published commits are not rewritten."
  fi
  ok "no post-fix sync commit diverges ($checked post-fix commit(s) checked)"
}

# ----------------------------------------------------------------- fixture mode
# Builds a template and a project that between them reproduce both measured causes
# plus an honest control, then runs the real sync and reads what it said.
fixture_mode() {
  local root proj tmpl out rc
  root=$(mktemp -d 2>/dev/null || mktemp -d -t synccount) || { echo "mktemp failed"; return 1; }
  trap 'rm -rf "$root"' RETURN
  proj="$root/proj"; tmpl="$root/tmpl"

  # -- the template ---------------------------------------------------------
  # Minimal but valid: resolve_local_template requires scripts/sync-prompt.md and
  # .claude/rules/. Deliberately does NOT contain template-autosync.sh, so the
  # sync under test cannot overwrite and re-exec itself mid-fixture.
  # The two subjects are CORE RULES, not scripts, on purpose: the sync runs
  # `chmod +x` over everything it writes under scripts/, and against a project
  # that committed its scripts 644 that is a mode-only change — which git DOES
  # record, so it would not reproduce an unrecorded write at all. Rules take no
  # chmod, so a rule rewritten to its own committed bytes is invisible to git,
  # which is exactly the .claude/settings.json case from the field.
  mkdir -p "$tmpl/scripts" "$tmpl/.claude/rules" "$tmpl/.claude/skills/demo"
  : > "$tmpl/scripts/sync-prompt.md"
  printf 'tests v2\n'   > "$tmpl/.claude/rules/tests.md"    # round-trip subject
  printf 'specs v2\n'   > "$tmpl/.claude/rules/specs.md"    # honest control
  # Spec 007aq. The ignored subject used to be .claude/skills/demo/thing.pyc, and the sync
  # now refuses to copy compiled python at all — so that fixture stopped reproducing the
  # cause, and this harness's own "really was written to disk" check is what said so. The
  # subject has to be a file the sync still WRITES and the project still IGNORES; those are
  # two different properties and the .pyc only stopped having the first one.
  printf 'scratch\n'    > "$tmpl/.claude/skills/demo/notes.local"   # ignored subject
  git -C "$tmpl" init -q 2>/dev/null
  git -C "$tmpl" add -A 2>/dev/null
  git -C "$tmpl" -c user.email=t@t -c user.name=t commit -qm fixture 2>/dev/null

  # -- the project ----------------------------------------------------------
  mkdir -p "$proj/scripts" "$proj/.claude"
  git -C "$proj" init -q
  git -C "$proj" config user.email t@t; git -C "$proj" config user.name t
  printf '*.local\n' > "$proj/.gitignore"

  mkdir -p "$proj/.claude/rules"
  # (1) ROUND-TRIP: HEAD already holds the template's bytes. tests.md is a CORE
  #     rule, so the sync overwrites it unconditionally — restoring exactly what
  #     HEAD has. A real write, and nothing for git to record.
  printf 'tests v2\n' > "$proj/.claude/rules/tests.md"
  # (2) HONEST CONTROL: HEAD holds older bytes, so this write is a real change.
  printf 'specs v1\n' > "$proj/.claude/rules/specs.md"
  git -C "$proj" add -A; git -C "$proj" commit -qm base

  printf 'locally scribbled\n' > "$proj/.claude/rules/tests.md"   # dirty the working tree

  # -- run the real sync ----------------------------------------------------
  out=$( cd "$proj" && CLAUDE_TEMPLATE_DIR="$tmpl" CLAUDE_PROJECT_DIR="$proj" \
         bash "$SYNC" 2>&1 ); rc=$?
  printf '\n[fixture] sync said:\n'
  printf '%s\n' "$out" | sed 's/^/        | /'

  local head_line claimed_u claimed_a committed_m committed_a
  head_line=$(printf '%s\n' "$out" | grep '^\[synced\]' | head -1)
  if [ -z "$head_line" ]; then
    bad "the sync produced no [synced] line (rc=$rc) — fixture is broken, not the counter"
    return 0
  fi
  claimed_u=$(printf '%s' "$head_line" | sed -n 's/.*→ \([0-9][0-9]*\) updated, \([0-9][0-9]*\) added.*/\1/p')
  claimed_a=$(printf '%s' "$head_line" | sed -n 's/.*→ \([0-9][0-9]*\) updated, \([0-9][0-9]*\) added.*/\2/p')

  printf '[fixture] the commit it made:\n'
  git -C "$proj" show --numstat --format= HEAD 2>/dev/null | sed 's/^/        | /'
  committed_m=$(git -C "$proj" show --numstat --format= --diff-filter=M HEAD 2>/dev/null \
                | awk '$3 != ".claude/.template-sync" && NF {n++} END{print n+0}')
  committed_a=$(git -C "$proj" show --numstat --format= --diff-filter=A HEAD 2>/dev/null \
                | awk '$3 != ".claude/.template-sync" && NF {n++} END{print n+0}')

  # SC-001 / SC-002 — the headline describes the commit.
  if [ "$claimed_u" = "$committed_m" ] && [ "$claimed_a" = "$committed_a" ]; then
    ok "headline (${claimed_u} updated, ${claimed_a} added) matches the commit"
  else
    bad "headline says ${claimed_u} updated / ${claimed_a} added; commit has ${committed_m} / ${committed_a}"
  fi

  # The honest control must survive: this is the majority case and must not regress.
  if grep -qx '.claude/rules/specs.md' <<< "$(git -C "$proj" show --name-only --format= HEAD)"; then
    ok "the genuinely-changed file is in the commit"
  else
    bad "the genuinely-changed file never reached the commit"
  fi

  # FR-003 — each written-but-unrecorded file is named, with a reason.
  if grep -q 'rules/tests.md' <<< "$out"; then
    if grep -qi 'identical to HEAD' <<< "$(grep 'tests.md' <<< "$out")"; then
      ok "the round-tripped write is named, with the HEAD-identical reason"
    else
      bad "the round-tripped write is named but its reason is wrong or missing"
    fi
  else
    bad "the round-tripped write (.claude/rules/tests.md) is not reported at all"
  fi

  if grep -q 'notes.local' <<< "$out"; then
    if grep -qi 'ignored' <<< "$(grep 'notes.local' <<< "$out")"; then
      ok "the gitignored write is named, with the ignored reason"
    else
      bad "the gitignored write is named but its reason is wrong or missing"
    fi
  else
    bad "the gitignored write (.claude/skills/demo/notes.local) is not reported at all"
  fi

  # The file really was written — otherwise "not recorded" would be trivially true.
  [ -f "$proj/.claude/skills/demo/notes.local" ] \
    && ok "the ignored file really was written to disk" \
    || bad "the ignored file was never written — fixture does not reproduce the cause"
}

# ------------------------------------------------- clean case: no extra noise
# US1-AS3 / SC-005 / R2. The majority of real syncs have nothing to reconcile, and
# this output is forwarded verbatim into every session start. A reconciliation
# block that fires when there is nothing to report is a regression in its own right.
clean_case() {
  local root proj tmpl out
  root=$(mktemp -d 2>/dev/null || mktemp -d -t synccleancase) || return 1
  trap 'rm -rf "$root"' RETURN
  proj="$root/proj"; tmpl="$root/tmpl"

  mkdir -p "$tmpl/scripts" "$tmpl/.claude/rules"
  : > "$tmpl/scripts/sync-prompt.md"
  printf '#!/bin/sh\n# v2\n' > "$tmpl/scripts/emit-pipeline-reminder.sh"
  printf 'rule v2\n'         > "$tmpl/.claude/rules/tests.md"
  git -C "$tmpl" init -q 2>/dev/null; git -C "$tmpl" add -A 2>/dev/null
  git -C "$tmpl" -c user.email=t@t -c user.name=t commit -qm fixture 2>/dev/null

  mkdir -p "$proj/scripts" "$proj/.claude/rules"
  git -C "$proj" init -q; git -C "$proj" config user.email t@t; git -C "$proj" config user.name t
  printf '#!/bin/sh\n# v1\n' > "$proj/scripts/emit-pipeline-reminder.sh"
  printf 'rule v1\n'         > "$proj/.claude/rules/tests.md"
  git -C "$proj" add -A; git -C "$proj" commit -qm base

  out=$( cd "$proj" && CLAUDE_TEMPLATE_DIR="$tmpl" CLAUDE_PROJECT_DIR="$proj" bash "$SYNC" 2>&1 )
  printf '\n[clean] every write recorded — the block must stay silent\n'
  if grep -qi 'recorded no change' <<< "$out"; then
    bad "a reconciliation block fired on a clean sync (this lands in every session start)"
    printf '%s\n' "$out" | sed 's/^/        | /'
  else
    ok "clean sync emits no reconciliation block"
  fi

  # SC-005 — and the counts still have to be right in the quiet case.
  local h cu ca m
  h=$(printf '%s\n' "$out" | grep '^\[synced\]' | head -1)
  cu=$(printf '%s' "$h" | sed -n 's/.*→ \([0-9][0-9]*\) updated.*/\1/p')
  m=$(git -C "$proj" show --numstat --format= --diff-filter=M HEAD 2>/dev/null \
      | awk '$3 != ".claude/.template-sync" && NF {n++} END{print n+0}')
  [ "$cu" = "$m" ] && ok "clean sync headline matches its commit ($cu)" \
                   || bad "clean sync claims $cu updated, commit has $m"
}

# --------------------------------------- nothing to record: no empty commit
# SC-004 / FR-005(c). Re-running a settled sync must not manufacture a commit.
nothing_case() {
  local root proj tmpl out before after
  root=$(mktemp -d 2>/dev/null || mktemp -d -t syncnothing) || return 1
  trap 'rm -rf "$root"' RETURN
  proj="$root/proj"; tmpl="$root/tmpl"

  mkdir -p "$tmpl/scripts" "$tmpl/.claude/rules"
  : > "$tmpl/scripts/sync-prompt.md"
  printf '#!/bin/sh\n# v2\n' > "$tmpl/scripts/emit-pipeline-reminder.sh"
  git -C "$tmpl" init -q 2>/dev/null; git -C "$tmpl" add -A 2>/dev/null
  git -C "$tmpl" -c user.email=t@t -c user.name=t commit -qm fixture 2>/dev/null

  mkdir -p "$proj/scripts"
  git -C "$proj" init -q; git -C "$proj" config user.email t@t; git -C "$proj" config user.name t
  # Already identical to the template: there is genuinely nothing to do.
  printf '#!/bin/sh\n# v2\n' > "$proj/scripts/emit-pipeline-reminder.sh"
  git -C "$proj" add -A; git -C "$proj" commit -qm base

  before=$(git -C "$proj" rev-list --count HEAD)
  out=$( cd "$proj" && CLAUDE_TEMPLATE_DIR="$tmpl" CLAUDE_PROJECT_DIR="$proj" bash "$SYNC" --force 2>&1 )
  after=$(git -C "$proj" rev-list --count HEAD)

  printf '\n[nothing] a sync with no recorded content\n'
  # One commit is legitimate IF it carries the stamp and the SHA moved (FR-005b).
  if [ "$after" -eq "$before" ]; then
    ok "no commit created when there is nothing to record"
  else
    local files
    files=$(git -C "$proj" show --name-only --format= HEAD | grep -c .)
    if [ "$files" -eq 1 ] && grep -qx '.claude/.template-sync' <<< "$(git -C "$proj" show --name-only --format= HEAD)"; then
      ok "only the stamp was committed (a SHA advance, not a file count)"
      if grep -qE '— 0 updated, 0 added' <<< "$(git -C "$proj" log -1 --format=%s)"; then
        ok "the stamp-only commit does not claim files it does not carry"
      else
        bad "the stamp-only commit's subject: $(git -C "$proj" log -1 --format=%s)"
      fi
    else
      bad "an empty sync produced a $files-file commit"
    fi
  fi
}

# ------------------------------------------ stamp advance: written, nothing recorded
# FR-005(b). The case where the sync really did work — it wrote files — and git
# recorded none of it. The stamp still has to be committed or the next run sees a
# stale SHA and re-syncs from scratch; it just must not be described as a file
# count. This is 7c4a6a9 and 9b72263, which claim "1 updated" over an empty diff.
stamp_advance_case() {
  local root proj tmpl out subj files
  root=$(mktemp -d 2>/dev/null || mktemp -d -t syncstamp) || return 1
  trap 'rm -rf "$root"' RETURN
  proj="$root/proj"; tmpl="$root/tmpl"

  mkdir -p "$tmpl/scripts" "$tmpl/.claude/rules" "$tmpl/.claude/skills/demo"
  : > "$tmpl/scripts/sync-prompt.md"
  printf 'tests v2\n' > "$tmpl/.claude/rules/tests.md"
  printf 'scratch\n' > "$tmpl/.claude/skills/demo/notes.local"   # see spec 007aq above
  git -C "$tmpl" init -q 2>/dev/null; git -C "$tmpl" add -A 2>/dev/null
  git -C "$tmpl" -c user.email=t@t -c user.name=t commit -qm fixture 2>/dev/null

  mkdir -p "$proj/.claude/rules"
  git -C "$proj" init -q; git -C "$proj" config user.email t@t; git -C "$proj" config user.name t
  printf '*.local\n' > "$proj/.gitignore"
  printf 'tests v2\n' > "$proj/.claude/rules/tests.md"     # HEAD already has template bytes
  git -C "$proj" add -A; git -C "$proj" commit -qm base
  printf 'scribbled\n' > "$proj/.claude/rules/tests.md"    # dirty: the sync will restore it

  out=$( cd "$proj" && CLAUDE_TEMPLATE_DIR="$tmpl" CLAUDE_PROJECT_DIR="$proj" bash "$SYNC" 2>&1 )
  printf '\n[stamp] files written, nothing recorded\n'
  printf '%s\n' "$out" | sed 's/^/        | /'

  subj=$(git -C "$proj" log -1 --format=%s)
  files=$(git -C "$proj" show --name-only --format= HEAD | grep -c .)
  case "$subj" in
    *"chore(sync)"*)
      if [ "$files" -eq 1 ] && grep -qx '.claude/.template-sync' <<< "$(git -C "$proj" show --name-only --format= HEAD)"; then
        ok "the stamp advanced in a commit of its own"
      else
        bad "the stamp-advance commit carries $files file(s), not just the stamp"
      fi
      case "$subj" in
        *"0 updated, 0 added"*) ok "it claims no files, because it carries none" ;;
        *) bad "stamp-advance subject still claims files: $subj" ;;
      esac ;;
    *) bad "no sync commit was made, so the stamp is left uncommitted and the next run re-syncs" ;;
  esac

  # And the writes it did make must still be reported.
  grep -q 'recorded no change' <<< "$out" \
    && ok "the unrecorded writes are still reported" \
    || bad "files were written, none recorded, and nothing said so"

  [ -z "$(git -C "$proj" status --porcelain --ignored=no)" ] \
    && ok "the working tree is left clean" \
    || { bad "the sync left the tree dirty:"; git -C "$proj" status --porcelain --ignored=no | sed 's/^/        | /'; }
}

# ------------------------------------------------------- --check writes nothing
# FR-006. --check has no commit to reconcile against and must not pretend otherwise.
check_case() {
  local root proj tmpl out
  root=$(mktemp -d 2>/dev/null || mktemp -d -t synccheck) || return 1
  trap 'rm -rf "$root"' RETURN
  proj="$root/proj"; tmpl="$root/tmpl"
  mkdir -p "$tmpl/scripts" "$tmpl/.claude/rules"; : > "$tmpl/scripts/sync-prompt.md"
  printf '#!/bin/sh\n# v2\n' > "$tmpl/scripts/emit-pipeline-reminder.sh"
  git -C "$tmpl" init -q 2>/dev/null; git -C "$tmpl" add -A 2>/dev/null
  git -C "$tmpl" -c user.email=t@t -c user.name=t commit -qm fixture 2>/dev/null

  mkdir -p "$proj/scripts"; git -C "$proj" init -q
  git -C "$proj" config user.email t@t; git -C "$proj" config user.name t
  printf '#!/bin/sh\n# v1\n' > "$proj/scripts/emit-pipeline-reminder.sh"
  git -C "$proj" add -A; git -C "$proj" commit -qm base

  out=$( cd "$proj" && CLAUDE_TEMPLATE_DIR="$tmpl" CLAUDE_PROJECT_DIR="$proj" bash "$SYNC" --check 2>&1 )
  printf '\n[check] --check reconciles nothing\n'
  grep -qi 'recorded no change' <<< "$out" \
    && bad "--check emitted a reconciliation block despite writing nothing" \
    || ok "--check emits no reconciliation block"
  [ -z "$(git -C "$proj" status --porcelain)" ] \
    && ok "--check left the working tree clean" \
    || bad "--check modified files"
}

# ------------------------------------------- a rewritten subject is not the sync's claim
# Spec 007cb. --history's third class needs an arm that can FAIL, and the estate cannot provide one:
# the single hand-amended commit that exists is a fact about published history, so a discriminator
# broken in either direction changes the numbers --history prints and changes nothing about whether
# it exits 0. A class no test can redden is a report, not a gate — the same sentence this project
# already writes about validate-scenario-traceability.sh, and the reason that one ships with a
# sabotage arm.
#
# So the commit is MADE here: a real sync produces a real auto-messaged commit, the arm reads it,
# then amends the subject to claim a count the diff does not carry and drops the body. Both readings
# are asserted, because each catches the opposite mutation — a marker that matches nothing turns the
# first reading's `checked` to 0, and a marker that matches everything leaves the second reading
# calling the amended commit a regression.
amended_case() {
  local root proj tmpl before after
  root=$(mktemp -d 2>/dev/null || mktemp -d -t syncamended) || return 1
  trap 'rm -rf "$root"' RETURN
  proj="$root/proj"; tmpl="$root/tmpl"

  mkdir -p "$tmpl/scripts" "$tmpl/.claude/rules"; : > "$tmpl/scripts/sync-prompt.md"
  printf 'rule v2\n' > "$tmpl/.claude/rules/tests.md"
  git -C "$tmpl" init -q 2>/dev/null; git -C "$tmpl" add -A 2>/dev/null
  git -C "$tmpl" -c user.email=t@t -c user.name=t commit -qm fixture 2>/dev/null

  mkdir -p "$proj/scripts" "$proj/.claude/rules"; git -C "$proj" init -q
  git -C "$proj" config user.email t@t; git -C "$proj" config user.name t
  printf 'rule v1\n' > "$proj/.claude/rules/tests.md"
  # The fix marker has to be in the tree the sync commit builds, or every commit here is pre-fix and
  # the post-fix branch this arm is about never runs. The template ships no template-autosync.sh, so
  # this stub is never overwritten and never triggers the self-update re-exec. Written through
  # $FIX_MARKER rather than spelled out: a second literal copy of a marker is how it drifts from the
  # thing it marks, and this file already owns the one authoritative copy.
  printf '#!/bin/sh\n# %s\n' "$FIX_MARKER" > "$proj/scripts/template-autosync.sh"
  git -C "$proj" add -A; git -C "$proj" commit -qm base

  ( cd "$proj" && CLAUDE_TEMPLATE_DIR="$tmpl" CLAUDE_PROJECT_DIR="$proj" bash "$SYNC" >/dev/null 2>&1 )

  printf '\n[amended] a subject the sync did not write is not a verdict about the sync\n'
  case "$(git -C "$proj" log -1 --format=%s)" in
    "chore(sync):"*) ;;
    *) bad "fixture produced no sync commit — the rest of this arm would assert nothing"; return 0 ;;
  esac

  # Reading 1 — untouched. The sync's own commit is honest, so it is the post-fix commit that got
  # checked. Asserting the number (not just the absence of a FAIL) is what makes a marker matching
  # nothing visible: that mutation leaves this line saying 0.
  before=$(history_mode "$proj" 2>&1)
  grep -q 'no post-fix sync commit diverges (1 post-fix commit(s) checked)' <<< "$before" \
    && ok "the sync's own commit counts as one post-fix commit checked" \
    || { bad "the sync's own commit was not counted as checked"
         printf '%s\n' "$before" | sed 's/^/        | /'; }

  # Reading 2 — the subject rewritten to claim a count the diff does not carry, the body dropped.
  # One -m, deliberately: that is exactly what an amend by hand leaves behind.
  git -C "$proj" commit -q --amend -m "chore(sync): template deadbeefcafe — 99 updated, 0 added"
  after=$(history_mode "$proj" 2>&1)

  grep -q 'the sync did not write this message' <<< "$after" \
    && ok "the rewritten subject is named, with the reason" \
    || { bad "a rewritten subject went unreported"
         printf '%s\n' "$after" | sed 's/^/        | /'; }
  grep -q 'created WITH the fix in tree' <<< "$after" \
    && { bad "a rewritten subject was reported as a regression in template-autosync.sh"
         printf '%s\n' "$after" | sed 's/^/        | /'; } \
    || ok "it is not charged to the sync as a regression"
  grep -q 'no post-fix sync commit diverges (0 post-fix commit(s) checked)' <<< "$after" \
    && ok "a rewritten subject that diverges does not reach the checked count" \
    || { bad "a commit the sync did not write was counted as checked"
         printf '%s\n' "$after" | sed 's/^/        | /'; }

  # Reading 3 — the case reading 2 CANNOT reach, and the only one that tests the guard on the
  # checked counter. A diverging commit returns before that counter no matter who wrote the subject,
  # so reading 2 proves the `continue`, not the guard. Written by hand and MEASURED wrong first: this
  # arm was designed with reading 2 alone and the mutation that removes the guard left it green.
  #
  # Here the rewritten subject is arithmetically RIGHT (the fixture sync records exactly 1 modified
  # file, 0 added) and the body is still gone. It must not be counted: a subject somebody else wrote
  # that happens to agree with the diff says nothing about whether template-autosync.sh can count,
  # and the checked figure is the only evidence the green line offers.
  git -C "$proj" commit -q --amend -m "chore(sync): template deadbeefcafe — 1 updated, 0 added"
  after=$(history_mode "$proj" 2>&1)
  grep -q 'no post-fix sync commit diverges (0 post-fix commit(s) checked)' <<< "$after" \
    && ok "a rewritten subject that AGREES is still not counted as checked" \
    || { bad "a rewritten subject was counted as checked because its arithmetic happened to agree"
         printf '%s\n' "$after" | sed 's/^/        | /'; }
  grep -q 'the sync did not write this message' <<< "$after" \
    && { bad "a rewritten subject whose counts agree was reported — there is nothing to report"
         printf '%s\n' "$after" | sed 's/^/        | /'; } \
    || ok "and it is reported nowhere, because it diverges from nothing"
}

# ---------------------------------------------------------------------- main
case "${1:-}" in
  --history) history_mode "${2:-}" ;;
  --fixture) fixture_mode ;;
  --amended) amended_case ;;
  --stamp)   stamp_advance_case ;;
  "")        fixture_mode; clean_case; nothing_case; stamp_advance_case; check_case; amended_case; history_mode ;;
  -h|--help) grep -E '^#( |$)' "$0" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "usage: $0 [--fixture|--stamp|--amended|--history [repo]]" >&2; exit 1 ;;
esac

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
