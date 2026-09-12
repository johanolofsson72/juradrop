#!/usr/bin/env bash
# test-core-owed-tick-guard.sh — the gate that refuses a register tick while CORE work is owed,
# and the [unlisted] detector underneath it.
#
# Spec 007ca. Two things are under test and they are joined at the hip:
#
#   scripts/core-owed-tick-guard-hook.sh   denies `- [x]` in specs/INDEX.md while the project owes
#                                          the template CORE work.
#   template-autosync.sh --owed/--unlisted the two questions it asks.
#
# Weighted the way the sibling harness is weighted, and for the same reason: getting the deny right
# is the easy half. This guard sits in front of the register of every project in the fleet, so the
# half that decides whether it survives is everything it must NOT do — and above all that it fails
# OPEN. A gate that bricked the register would be gone within the hour, taking the protection with
# it. Four arms prove it bites; twelve prove it stays quiet or gets out of the way.
#
# Everything runs the real hook and the real sync against throwaway git repositories, fed the same
# PreToolUse JSON Claude Code sends. Nothing greps a source file for a string it hopes is there.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SELF_DIR/core-owed-tick-guard-hook.sh"
SYNC="$SELF_DIR/template-autosync.sh"
BASHGUARD="$SELF_DIR/bash-write-guard-hook.sh"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

[ -f "$HOOK" ] || { echo "missing: $HOOK"; exit 1; }
[ -f "$SYNC" ] || { echo "missing: $SYNC"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t owedtick)
trap 'rm -rf "$WORK"' EXIT

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else cksum "$1" | cut -d' ' -f1; fi
}

# ---------------------------------------------------------------- the fixture
# A synced project as the guard expects one: git root, .claude/, its own copy of the sync, a
# register, and a manifest whose recorded hashes MATCH the files on disk. That last part is what
# makes "clean" a real state rather than an accident — every deny arm below is produced by moving
# exactly one thing away from it, so a test that passes does so for a nameable reason.
#
# origin is set to something emphatically not the template: the template exemption is one of the
# arms, and a repo with no origin would pass it for the wrong reason.
make_project() {
  _p="$WORK/$1"
  mkdir -p "$_p/scripts" "$_p/.claude/rules" "$_p/specs"
  git -C "$_p" init -q 2>/dev/null || git init -q "$_p"
  git -C "$_p" remote add origin "https://github.com/someone/not-the-template.git" 2>/dev/null
  cp "$SYNC" "$_p/scripts/template-autosync.sh"

  # Fixture names are deliberately synthetic. This harness is CORE, so the detector under test READS
  # this file — and the bare-name version of the predicate duly reported msroute's real
  # mutation-gate.sh on its first live run, because a fixture line here mentioned it. The sibling
  # harness reached the same convention (`project-specific-thing.sh`) by the same route.
  printf 'core script\n'  > "$_p/scripts/spec_active.py"                  # CORE
  printf 'core rule\n'    > "$_p/.claude/rules/feature-pipeline.md"       # CORE
  printf 'ours\n'         > "$_p/scripts/project-owned-thing.sh"                # the project's own
  printf '{}\n'           > "$_p/.claude/settings.json"

  cat > "$_p/specs/INDEX.md" <<'IDX'
# Spec register

## Specs

- [x] 001 — done-thing — spec-only track — a finished row
- [/] 002 — current-thing — spec-only track — the row in progress
- [ ] 003 — next-thing — spec-only track — the row after
IDX

  {
    printf 'sha=deadbeefcafe\n'
    printf '%s  scripts/spec_active.py\n'            "$(sha "$_p/scripts/spec_active.py")"
    printf '%s  scripts/template-autosync.sh\n'      "$(sha "$_p/scripts/template-autosync.sh")"
    printf '%s  .claude/rules/feature-pipeline.md\n' "$(sha "$_p/.claude/rules/feature-pipeline.md")"
    printf '%s  .claude/settings.json\n'             "$(sha "$_p/.claude/settings.json")"
  } > "$_p/.claude/.template-sync"

  printf '%s' "$_p"
}

# The hook, driven exactly as Claude Code drives it. $2 is the bytes being written; passing "" is
# the Bash-delegate shape, where a path arrives with no content at all.
run_hook() {          # $1 = file path, $2 = new_string ("" = none), rest = VAR=VAL overrides
  _f="$1"; _new="$2"; shift 2
  if [ -z "$_new" ]; then
    printf '{"tool_name":"Edit","tool_input":{"file_path":%s}}' "$(jq -Rn --arg p "$_f" '$p')" \
      | env "$@" bash "$HOOK" 2>/dev/null
  else
    jq -n --arg p "$_f" --arg n "$_new" \
      '{tool_name:"Edit",tool_input:{file_path:$p,new_string:$n}}' \
      | env "$@" bash "$HOOK" 2>/dev/null
  fi
}

decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null; }
reason()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
context()  { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

TICK='- [x] 002 — current-thing — spec-only track — the row in progress'

# =============================================================== the quiet controls
# First, deliberately. Every deny arm below is this fixture with one thing changed, so if the clean
# case were not silent none of the denies would mean anything.
printf '\n[silent] the healthy tree, and every edit that is not a tick\n'

CLEAN=$(make_project clean)

OUT=$(run_hook "$CLEAN/specs/INDEX.md" "$TICK")
[ -z "$OUT" ] && ok "a tick on a project that owes nothing is silent" \
              || { bad "the guard fired on a clean tree"; info "$(reason "$OUT")"; }

# ---- the register edits that are NOT the event -------------------------------
# Marking a row in progress is what you do ON THE WAY to landing what is owed, so a gate that
# blocked it would block its own repair path. Asserted against a DIRTY tree, because on a clean one
# it would pass for the wrong reason.
DIRTY=$(make_project dirty)
printf 'core script, edited only here\n' > "$DIRTY/scripts/spec_active.py"

for shape in \
  '- [/] 002 — current-thing — spec-only track — the row in progress' \
  '- [!] 002 — current-thing — spec-only track — blocked' \
  '- [ ] 004 — a-new-row — spec-only track — appended while CORE work is owed' \
  '  (prose, no row marker at all)'
do
  OUT=$(run_hook "$DIRTY/specs/INDEX.md" "$shape")
  [ -z "$OUT" ] && ok "not a tick, so not blocked: ${shape:0:34}" \
                || { bad "blocked a non-tick register edit: $shape"; info "$(reason "$OUT")"; }
done

# ---- everything that is not the register -------------------------------------
OUT=$(run_hook "$DIRTY/scripts/project-owned-thing.sh" "$TICK")
[ -z "$OUT" ] && ok "a file that is not specs/INDEX.md is untouched, even carrying tick-shaped text" \
              || { bad "the guard judged a non-register file"; info "$(reason "$OUT")"; }

# =============================================================== it bites
printf '\n[deny] a tick while the project owes the template CORE work\n'

OUT=$(run_hook "$DIRTY/specs/INDEX.md" "$TICK")
if [ "$(decision "$OUT")" = "deny" ]; then
  ok "a tick is denied while a CORE file differs from the manifest"
  R=$(reason "$OUT")
  # Each of these is a separate promise the spec makes about the message (SC-004), so each is
  # asserted alone — a single "does it look right" check is how a message rots one clause at a time.
  case "$R" in *"scripts/spec_active.py"*) ok "  the reason names the divergent path" ;;
    *) bad "  the reason does not name the path"; info "$R" ;; esac
  case "$R" in *"ALLOW_TICK_WITH_CORE_OWED"*) ok "  the reason names the override" ;;
    *) bad "  the reason does not name the override" ;; esac
  case "$R" in *"--force"*) ok "  the reason names the command that resolves it" ;;
    *) bad "  the reason names no next command" ;; esac
  case "$R" in *"\`- [/]\`"*|*"- [/]"*) ok "  the reason says which register edits still pass" ;;
    *) bad "  the reason does not say what is still allowed" ;; esac
else
  bad "a tick was NOT denied on a divergent tree"; info "$OUT"
fi

# ---- the half [owed] cannot see ----------------------------------------------
# The whole second gap. This project's CORE files all match the manifest, so --owed is quiet; what
# it holds is a script the template has never shipped that a CORE file depends on. If this arm did
# not exist the gate would reproduce 007bl's exact blindness inside the fix for 007bl.
UNL=$(make_project unlisted)
printf 'new machinery\n' > "$UNL/scripts/scenario-map-probe.sh"       # CORE name, no manifest line
printf 'run: bash scripts/scenario-map-probe.sh\n' >> "$UNL/.claude/rules/feature-pipeline.md"
# ...and re-record the rule's hash, so THIS arm cannot pass by way of the [owed] family instead.
{ grep -v 'feature-pipeline.md' "$UNL/.claude/.template-sync"
  printf '%s  .claude/rules/feature-pipeline.md\n' "$(sha "$UNL/.claude/rules/feature-pipeline.md")"
} > "$UNL/.claude/.template-sync.new" && mv "$UNL/.claude/.template-sync.new" "$UNL/.claude/.template-sync"

OUT=$(run_hook "$UNL/specs/INDEX.md" "$TICK")
if [ "$(decision "$OUT")" = "deny" ]; then
  ok "a tick is denied for an unlisted CORE-shaped script, with [owed] quiet"
  R=$(reason "$OUT")
  case "$R" in *"scenario-map-probe.sh"*) ok "  the reason names the unlisted script" ;;
    *) bad "  the reason does not name the script"; info "$R" ;; esac
  case "$R" in *"named by: feature-pipeline.md"*) ok "  ...and the CORE file that depends on it" ;;
    *) bad "  the reason does not name the referrer"; info "$R" ;; esac
  case "$R" in *"never shipped"*|*"never had"*) ok "  ...and distinguishes it from the [owed] family" ;;
    *) bad "  the two families are not distinguished" ;; esac
else
  bad "an unlisted CORE-shaped script did not block the tick"; info "$OUT"
fi

# ---- a project's own script is not a finding ---------------------------------
# The negative control for the arm above, and the one that decides whether this block is readable.
# project-owned-thing.sh has no manifest line either; the difference is that no CORE file depends on it.
OWN=$(make_project own)
printf 'ours, unmanaged, and nobody CORE cares\n' > "$OWN/scripts/project-owned-thing.sh"
OUT=$(run_hook "$OWN/specs/INDEX.md" "$TICK")
[ -z "$OUT" ] && ok "an unmanaged script no CORE file names is NOT a finding" \
              || { bad "the project's own script blocked a tick"; info "$(reason "$OUT")"; }

# ---- a name already on the shipping list is not "unlisted" --------------------
# The other negative control, and the one that keeps the referrer column meaningful. CORE_SCRIPTS
# names every CORE script, so without this exclusion template-autosync.sh is a referrer for all of
# them and the column says nothing. A missing manifest line for a name the list already carries is a
# manifest one sync behind, not work owed.
LISTED=$(make_project listed)
printf 'arrived with the last sync\n' > "$LISTED/scripts/scenario-map-rows.sh"   # in CORE_SCRIPTS
printf 'run: bash scripts/scenario-map-rows.sh\n' >> "$LISTED/.claude/rules/feature-pipeline.md"
{ grep -v 'feature-pipeline.md' "$LISTED/.claude/.template-sync"
  printf '%s  .claude/rules/feature-pipeline.md\n' "$(sha "$LISTED/.claude/rules/feature-pipeline.md")"
} > "$LISTED/.claude/.template-sync.new" && mv "$LISTED/.claude/.template-sync.new" "$LISTED/.claude/.template-sync"
OUT=$(run_hook "$LISTED/specs/INDEX.md" "$TICK")
[ -z "$OUT" ] && ok "a script CORE_SCRIPTS already names is not reported as unlisted" \
              || { bad "a listed script was reported as unlisted"; info "$(reason "$OUT")"; }

# ---- a bare mention in prose is not a dependency ------------------------------
# The precision half of the predicate, and the one this harness itself violated first. A CORE file
# that writes `foo.sh` is talking ABOUT a script; one that writes `scripts/foo.sh` is depending on
# it. Without this distinction every fixture name and every sentence in a rule becomes a referrer.
PROSE=$(make_project prose)
printf 'ours\n' > "$PROSE/scripts/some-local-tool.sh"
printf 'Historically some-local-tool.sh did this job.\n' >> "$PROSE/.claude/rules/feature-pipeline.md"
{ grep -v 'feature-pipeline.md' "$PROSE/.claude/.template-sync"
  printf '%s  .claude/rules/feature-pipeline.md\n' "$(sha "$PROSE/.claude/rules/feature-pipeline.md")"
} > "$PROSE/.claude/.template-sync.new" && mv "$PROSE/.claude/.template-sync.new" "$PROSE/.claude/.template-sync"
OUT=$(run_hook "$PROSE/specs/INDEX.md" "$TICK")
[ -z "$OUT" ] && ok "a bare mention in prose is not a referrer" \
              || { bad "prose created a finding"; info "$(reason "$OUT")"; }

# ...and the positive control for it: the same file, referenced as a path.
printf 'run: bash scripts/some-local-tool.sh\n' >> "$PROSE/.claude/rules/feature-pipeline.md"
{ grep -v 'feature-pipeline.md' "$PROSE/.claude/.template-sync"
  printf '%s  .claude/rules/feature-pipeline.md\n' "$(sha "$PROSE/.claude/rules/feature-pipeline.md")"
} > "$PROSE/.claude/.template-sync.new" && mv "$PROSE/.claude/.template-sync.new" "$PROSE/.claude/.template-sync"
OUT=$(run_hook "$PROSE/specs/INDEX.md" "$TICK")
[ "$(decision "$OUT")" = "deny" ] && ok "  ...but the same name written as scripts/<name> is" \
              || { bad "  a path-shaped reference did NOT produce a finding"; info "$OUT"; }

# =============================================================== it gets out of the way
printf '\n[open] every way of failing to answer lets the edit through\n'

# ---- the override -------------------------------------------------------------
OUT=$(run_hook "$DIRTY/specs/INDEX.md" "$TICK" ALLOW_TICK_WITH_CORE_OWED=1)
if [ "$(decision "$OUT")" = "deny" ]; then
  bad "the override did not let the tick through"
else
  ok "ALLOW_TICK_WITH_CORE_OWED=1 lets the tick through"
  case "$(context "$OUT")" in *ALLOW_TICK_WITH_CORE_OWED*)
      ok "  ...and says so rather than passing quietly" ;;
    *) bad "  the override passed silently" ;; esac
fi

# ---- no sync -------------------------------------------------------------------
NOSYNC=$(make_project nosync)
printf 'edited\n' > "$NOSYNC/scripts/spec_active.py"
rm -f "$NOSYNC/scripts/template-autosync.sh"
OUT=$(run_hook "$NOSYNC/specs/INDEX.md" "$TICK")
[ -z "$OUT" ] && ok "no template-autosync.sh: no sync is coming, so nothing is owed" \
              || { bad "the guard fired with no sync present"; info "$(reason "$OUT")"; }

# ---- an unanswerable sync -------------------------------------------------------
# The one that matters most. A broken classifier must be indistinguishable from "nothing owed" —
# see the fail-open note in the hook. If this arm ever inverts, every register in the fleet locks.
BROKEN=$(make_project broken)
printf 'edited\n' > "$BROKEN/scripts/spec_active.py"
printf 'exit 3\n' > "$BROKEN/scripts/template-autosync.sh"
OUT=$(run_hook "$BROKEN/specs/INDEX.md" "$TICK")
[ -z "$OUT" ] && ok "a sync that cannot answer fails OPEN" \
              || { bad "a broken sync BLOCKED a tick — the register would be unticket-able"; info "$(reason "$OUT")"; }

# ---- no manifest at all ---------------------------------------------------------
# A project on its first day. No manifest is no evidence and therefore no claim — otherwise every
# script in the tree is "unmanaged" and the block fires on all of them.
FRESH=$(make_project fresh)
rm -f "$FRESH/.claude/.template-sync"
OUT=$(run_hook "$FRESH/specs/INDEX.md" "$TICK")
[ -z "$OUT" ] && ok "a never-synced project is silent (no manifest, no claim)" \
              || { bad "the guard fired on a project with no manifest"; info "$(reason "$OUT")"; }

# ---- the template repository ----------------------------------------------------
# The deny says "go and land it in the template". Denying the tick there would leave the
# instruction with nowhere to be followed.
TPL=$(make_project tpl)
printf 'edited\n' > "$TPL/scripts/spec_active.py"
git -C "$TPL" remote set-url origin "https://github.com/johanolofsson72/Claude.git"
OUT=$(run_hook "$TPL/specs/INDEX.md" "$TICK")
[ -z "$OUT" ] && ok "the template repository is exempt — that is where the change belongs" \
              || { bad "the guard fired inside the template repo"; info "$(reason "$OUT")"; }

# ---- nothing is written on the deny path -----------------------------------------
# FR-012a. Nothing in this family writes when it refuses; the deny text is the record.
BEFORE=$(cd "$DIRTY" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(sha "$f")" "$f"; done)
run_hook "$DIRTY/specs/INDEX.md" "$TICK" >/dev/null
AFTER=$(cd "$DIRTY" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(sha "$f")" "$f"; done)
[ "$BEFORE" = "$AFTER" ] && ok "a deny writes nothing — the tree is byte-identical afterwards" \
                         || { bad "the guard modified the tree on a deny"; info "$(diff <(printf '%s' "$BEFORE") <(printf '%s' "$AFTER") | head -5)"; }

# =============================================================== the shell route
printf '\n[parity] the same verdict through the shell\n'

# Row H7b: a guard wired only to Edit is silent on `sed -i`, and which tool you picked decides
# whether the rule applies. The delegate list is what closes that; this asserts it is closed here
# too, and states the bound — no bytes on this route, so it answers about the file.
if [ -f "$BASHGUARD" ]; then
  OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"sed -i %s s/x/y/ %s"}}' "''" "$DIRTY/specs/INDEX.md" \
          | bash "$BASHGUARD" 2>/dev/null)
  if [ "$(decision "$OUT")" = "deny" ]; then
    ok "a shell write to the register is denied on the same terms"
    case "$(reason "$OUT")" in *"core-owed-tick-guard-hook.sh"*)
        ok "  ...and the provenance line names THIS gate, not another one" ;;
      *) bad "  the provenance line names the wrong guard"; info "$(reason "$OUT")" ;; esac
  else
    bad "the shell route is silent where the Edit route denies"; info "$OUT"
  fi

  OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"sed -i %s s/x/y/ %s"}}' "''" "$CLEAN/specs/INDEX.md" \
          | bash "$BASHGUARD" 2>/dev/null)
  [ "$(decision "$OUT")" != "deny" ] && ok "  ...and stays quiet through the shell on a clean tree" \
                                     || { bad "  the shell route denied on a clean tree"; info "$(reason "$OUT")"; }
else
  info "bash-write-guard-hook.sh not present — shell-route parity not asserted"
fi

# =============================================================== the detector alone
printf '\n[detector] --owed and --unlisted answer for machines\n'

rc_of() { ( cd "$1" && shift && bash "$SYNC" "$@" >/dev/null 2>&1 ); }

rc_of "$CLEAN" --owed;     [ $? -eq 1 ] && ok "--owed exits 1 on a clean tree"     || bad "--owed did not exit 1 on a clean tree"
rc_of "$DIRTY" --owed;     [ $? -eq 0 ] && ok "--owed exits 0 when a CORE file moved" || bad "--owed did not exit 0 on a divergent tree"
rc_of "$CLEAN" --unlisted; [ $? -eq 1 ] && ok "--unlisted exits 1 with nothing to report" || bad "--unlisted did not exit 1 on a clean tree"
rc_of "$UNL"   --unlisted; [ $? -eq 0 ] && ok "--unlisted exits 0 on a CORE-shaped script" || bad "--unlisted did not exit 0 where it should"

# A finding must carry its referrer, or a reader cannot dismiss a false positive without going and
# reading the script (FR-003).
OUT=$( cd "$UNL" && bash "$SYNC" --unlisted 2>/dev/null )
case "$OUT" in *"scenario-map-probe.sh"*"feature-pipeline.md"*)
    ok "  a finding names both the path and its referrer" ;;
  *) bad "  the finding does not carry its referrer"; info "$OUT" ;; esac

# Neither query may touch the network: this runs in front of an Edit.
if command -v timeout >/dev/null 2>&1; then
  ( cd "$CLEAN" && timeout 5 bash "$SYNC" --unlisted >/dev/null 2>&1 ); RC=$?
  [ "$RC" -ne 124 ] && ok "--unlisted answers well inside 5 s (no template resolution)" \
                    || bad "--unlisted timed out — it is resolving the template"
  ( cd "$CLEAN" && timeout 5 bash "$SYNC" --owed >/dev/null 2>&1 ); RC=$?
  [ "$RC" -ne 124 ] && ok "--owed answers well inside 5 s (no template resolution)" \
                    || bad "--owed timed out — it is resolving the template"
fi

printf '\n%s\n' "----------------------------------------"
printf 'pass: %d   fail: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
