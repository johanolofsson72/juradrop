#!/usr/bin/env bash
# test-runtime-markers-ignored.sh — every machine-local marker the hooks write is gitignored,
# every record they mean to commit is not, and a marker nobody classified is a failure.
#
# WHY THIS EXISTS (spec 007bq)
# ---------------------------
# Two hand-written lists decide which .claude/ runtime paths get ignored: this repository's own
# .gitignore, and section "3a. .gitignore additions" in .claude/skills/sync-template/SKILL.md, which
# is what seeds a project during /project-update. Neither was derived from the set of paths the
# hooks actually write, and by 2026-08-28 they had drifted from the hooks and from each other:
# .claude/.bash-write-marker was ignored in neither, and churned in 5 of the 7 repositories running
# the guard — the template among them. Its sibling .claude/.bash-write-blocked was ignored in 0 of
# 73. Both were found by a developer noticing a dirty `git status`, months apart.
#
# So the lists stop being the only thing standing between a new marker and permanent churn.
#
# WHAT IS DECLARED AND WHAT IS DERIVED
# ------------------------------------
# Declared: the two buckets below, with a reason per entry. Whether a path is churn or a record
# meant to be committed is a judgment, and a judgment belongs in an argued list a reviewer can
# contest — the same idiom as EXEMPTIONS in bash-write-detect-hook.sh and EXCLUDED in run-gates.sh.
# Derived: completeness. Assertion C reads scripts/*.sh and fails on any .claude/.<marker> that is
# in neither bucket, which is the only assertion here that protects against the NEXT marker rather
# than the last two.
#
# LIMIT, stated rather than implied: assertion C greps for literal `.claude/.name` text. All 16
# current paths are written that way, but one assembled from a variable would evade it. This is a
# strong net over the idiom in use, not a proof.
#
# ORACLE: `git check-ignore`, never a grep for a line in .gitignore. Nine .local-llm-* paths are
# covered by one glob, the answer is needed for paths with no file on disk, and a machine-local
# marker somebody committed by accident must fail rather than pass on a rule git no longer applies
# to it.
#
#   bash scripts/test-runtime-markers-ignored.sh              # check this repository
#   bash scripts/test-runtime-markers-ignored.sh --self-test  # prove the five assertions can fail

set -u

# --------------------------------------------------------------- the declared buckets
# path%reason.  Machine-local: MUST be gitignored.
MACHINE_LOCAL='.claude/.maintenance-state%maintenance due-state: when each recurring job last ran ON THIS MACHINE. Per-machine for the same reason the crontab entry is (.claude/rules/lane-handoff.md) — David running the suite on Linux says nothing about whether it has run here, and committing it would let one lane mark the other lane clean
.claude/.bash-write-marker%bash-write guard timestamp, re-stamped on every Bash write
.claude/.bash-write-blocked%bash-write guard escape-hatch record (the file set of the last block)
.claude/.template-sync-check%auto-sync rate-limit marker (mtime only; the manifest .template-sync is tracked)
.claude/.local-llm-cache%local-LLM response cache
.claude/.local-llm-commit-draft%local-LLM draft, regenerated on demand
.claude/.local-llm-pr-draft%local-LLM draft, regenerated on demand
.claude/.local-llm-readme-draft%local-LLM draft, regenerated on demand
.claude/.local-llm-env-example-draft%local-LLM draft, regenerated on demand
.claude/.local-llm-gitignore-draft%local-LLM draft, regenerated on demand
.claude/.local-llm-pr-context%local-LLM scratch context for one invocation
.claude/.local-llm-issue-context%local-LLM scratch context for one invocation
.claude/.local-llm-gh-run-context%local-LLM scratch context for one invocation
.claude/state/%repeat-failure guard attempt counters, TTL-pruned
.claude/validation/%Stop-hook validation timestamp'

# Tracked by design: MUST NOT be gitignored.
#
# Phrased "must not be ignored" rather than "must be tracked" on purpose. In the template these four
# do not exist at all — the template is the source, so it syncs from nothing and has no manifest of
# its own. "Not ignored" is true of an absent path; "tracked" is not, and would fail the test in the
# one repository that authors it.
TRACKED_BY_DESIGN='.claude/.template-sync%the sync manifest — a project commits it, it is how drift is detected
.claude/.sync-stack%the declared stack for this project, read by the guards
.claude/.sync-local%accepted intentional differences from the template
.claude/.template-sync-verify%the verify command this project declares for its sync commits
.claude/.runtime-markers%project-local bucket additions (below) — a record a project commits'

SKILL_REL=".claude/skills/sync-template/SKILL.md"

# ------------------------------------------------- project-local additions (.claude/.runtime-markers)
# The two buckets above are CORE: this file is synced, so a path written into it by a project is
# eaten by the next sync. That is fine while every marker comes from a hook the template ships — and
# it stopped being fine the moment one did not. consultpilot's run-gates-stop-hook.sh writes
# .claude/.run-gates-marker; neither the hook nor the runner exists in this template, so assertion C
# fires there and the project has nowhere to answer it.
#
# WHY NOT JUST DECLARE IT UP HERE. Measured before choosing, because it is the cheaper-looking option:
# 8 repositories carry this test, and assertion A asks `git check-ignore` about EVERY declared
# machine-local path whether or not the repository writes it. A bucket line here for a marker one
# project writes turns the gate RED in the other 7 — this template among them — for a file they will
# never see. The sync does not carry .gitignore (it is project-owned), so each of those 7 would need a
# human to add an ignore rule for a path that does not concern them. That is not a cheap fix with an
# odd smell; it is a gate that cries wolf in 7 of 8 repositories, and a gate that does that is the
# permanently-red signal the register keeps arguing is an absent one.
#
# So the judgment stays where the judgment belongs — with the project that owns the hook — in a file
# the sync never rewrites. Same `path%reason` form, same contestable-reason discipline as the buckets
# above and as EXCLUDED in run-gates.sh.
#
#   # .claude/.runtime-markers
#   [machine-local]
#   .claude/.run-gates-marker%gate-runner Stop-hook marker; mtime only
#
#   [tracked-by-design]
#   .claude/.something%a record this project commits
#
# Read per-root, not once at startup, because the self-test drives run_checks against fixture
# repositories and a startup read would make every arm see this repository's file.
#
# Assertion D deliberately does NOT read these. D asks whether section 3a seeds a path to NEW
# projects, and the template cannot seed a marker written by a hook it does not ship. Requiring it
# would make the sidecar unusable the moment it is used.

MARKERS_REL=".claude/.runtime-markers"

# Echoes `path%reason` lines for one section; echoes MALFORMED lines prefixed with `!` so the caller
# can fail on them by name. A classification with no reason is not a classification here.
local_markers() { # $1=root  $2=section
  local f="$1/$MARKERS_REL"
  [ -f "$f" ] || return 0
  awk -v want="$2" '
    { sub(/\r$/, "") }
    /^[[:space:]]*(#|$)/ { next }
    /^[[:space:]]*\[.*\][[:space:]]*$/ {
      gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "")
      sec = $0
      if (sec != "machine-local" && sec != "tracked-by-design") print "!unknown section [" sec "]"
      next
    }
    {
      if (sec == "") { print "!line outside any section: " $0; next }
      if ($0 !~ /^\.claude\/[^%]+%.+$/) { print "!not path%reason: " $0; next }
      if (sec == want) print $0
    }
  ' "$f"
}

# ------------------------------------------------------------------------- helpers
FAILURES=0
CHECKS=0
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL  %s\n' "$*"; }
pass() { CHECKS=$((CHECKS + 1)); }

col1() { printf '%s\n' "$1" | cut -d'%' -f1; }
reason_for() { printf '%s\n' "$1" | awk -F'%' -v p="$2" '$1==p{print $2; exit}'; }

# Does one section-3a pattern cover this path? Trailing slash is a directory prefix; everything
# else is a shell glob, which is what git means by these patterns too.
covered_by() { # $1=path $2=pattern
  case "$2" in
    */) case "$1" in "$2"*) return 0 ;; esac; [ "$1" = "$2" ] && return 0 ;;
    *)  case "$1" in $2) return 0 ;; esac ;;
  esac
  return 1
}

# The patterns section 3a tells a project to add, read out of the backticked bullets.
skill_patterns() { # $1=path to SKILL.md
  [ -f "$1" ] || return 0
  awk '/^### 3a\./{s=1; next} s && /^### /{exit} s' "$1" \
    | grep -oE '`\.claude/[^`]+`' | tr -d '`' | sort -u
}

# ------------------------------------------------------------------- the five assertions
run_checks() { # $1=repo root  $2=SKILL.md path (may be absent)
  local root="$1" skill="$2" p reason pat found line
  local ML TBD bad

  # --- E: the project-local file, if any, parses.  Read BEFORE A/B/C, because a line this rejects
  # is a marker the developer believes is classified and that A/B/C would then report as unclaimed —
  # two messages about one cause, with the misleading one first.
  bad=$( { local_markers "$root" machine-local; local_markers "$root" tracked-by-design; } \
           | grep '^!' | sed 's/^!//' | sort -u )
  if [ -n "$bad" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      fail "[E] $MARKERS_REL is malformed: $line"
      printf '        expected `# comment`, `[machine-local]`, `[tracked-by-design]`,\n'
      printf '        or `.claude/.name%%reason` inside one of those sections. A path with no\n'
      printf '        reason is not a classification — the reason is what a reviewer contests.\n'
    done <<EOF0
$bad
EOF0
  else
    pass
  fi

  ML=$(printf '%s\n' "$MACHINE_LOCAL"; local_markers "$root" machine-local | grep -v '^!')
  TBD=$(printf '%s\n' "$TRACKED_BY_DESIGN"; local_markers "$root" tracked-by-design | grep -v '^!')

  # --- A: every machine-local path is ignored.  The row's bug, and its sibling.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git -C "$root" check-ignore -q "$p" 2>/dev/null; then
      pass
    else
      reason=$(reason_for "$ML" "$p")
      fail "[A] machine-local but NOT gitignored: $p"
      printf '        %s\n' "$reason"
      printf '        add it to %s/.gitignore — it is re-written during a normal session and\n' "$root"
      printf '        means nothing in another machine'"'"'s history.\n'
    fi
  done <<EOF
$(col1 "$ML")
EOF

  # --- B: no tracked-by-design record is ignored.  A rule that swallowed the manifest.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git -C "$root" check-ignore -q "$p" 2>/dev/null; then
      reason=$(reason_for "$TBD" "$p")
      fail "[B] tracked by design but IS gitignored: $p"
      printf '        %s\n' "$reason"
      printf '        an ignore rule here hides the record instead of the churn.\n'
    else
      pass
    fi
  done <<EOF
$(col1 "$TBD")
EOF

  # --- C: every .claude/.<marker> the scripts write is classified.  The next marker.
  # --exclude this file: its header states the grep's limit using `.claude/.name`, and its
  # self-test fixture writes `.claude/.some-new-marker` on purpose. A gate that flagged its own
  # worked examples would have to be silenced, and a silenced gate is not one.
  found=$(grep -rhoE '\.claude/\.[A-Za-z0-9_-]+' \
            --exclude="$(basename "$0")" "$root"/scripts/*.sh 2>/dev/null | sort -u)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if grep -qxF "$p" <<< "$(col1 "$ML"; col1 "$TBD")"; then
      pass
    else
      fail "[C] a marker no bucket claims: $p"
      printf '        scripts/ writes this path and nothing in this test says what it is.\n'
      printf '        Classify it: MACHINE_LOCAL if it is churn — a timestamp, a cache, a draft,\n'
      printf '        anything re-written during a normal session and meaningless on another\n'
      printf '        machine — and then gitignore it. TRACKED_BY_DESIGN if it is a record this\n'
      printf '        project is meant to commit. That judgment is the one thing this test\n'
      printf '        cannot make for you, which is why it stops here.\n'
      printf '        A marker written by a hook THIS TEMPLATE DOES NOT SHIP is classified in the\n'
      printf '        project-owned %s instead — see the header for why it is not\n' "$MARKERS_REL"
      printf '        a line up here.\n'
    fi
  done <<EOF
$found
EOF

  # --- D: section 3a seeds every machine-local path, so a NEW project inherits all of them.
  if [ -f "$skill" ]; then
    pat=$(skill_patterns "$skill")
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      found=no
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        covered_by "$p" "$line" && { found=yes; break; }
      done <<EOF2
$pat
EOF2
      if [ "$found" = yes ]; then
        pass
      else
        fail "[D] not seeded to new projects: $p"
        printf '        %s\n' "$(reason_for "$MACHINE_LOCAL" "$p")"
        printf '        add a bullet under "### 3a. .gitignore additions" in %s —\n' "$SKILL_REL"
        printf '        ignoring it here does nothing for the next project set up from the template.\n'
      fi
    done <<EOF3
$(col1 "$MACHINE_LOCAL")
EOF3
  else
    printf 'skip  [D] %s not present in this repository\n' "$SKILL_REL"
  fi
}

# ------------------------------------------------------------------------ self-test
# Ten arms. A gate nobody has watched fail is a gate nobody knows the shape of — this register
# already carries a row for a falsification arm that falsified nothing (007br), so each arm here
# reverts one real thing and asserts THAT path is named.
#
# Two of the ten (E2, E6) are NEGATIVE arms: they assert a message is ABSENT. They exist because the
# sidecar's whole job is to make an existing failure stop, and every positive arm in this file stays
# green if the sidecar is parsed and then thrown away.
self_test() {
  local st_fail=0 st_pass=0 d
  ST_TMP=$(mktemp -d) || { echo "cannot mktemp"; exit 2; }
  trap 'rm -rf "$ST_TMP"' EXIT

  arm() { # $1=name  $2=fixture dir  $3=expected substring
    local o
    o=$(FAILURES=0; CHECKS=0; run_checks "$2" "$2/$SKILL_REL" 2>&1)
    if grep -q '^FAIL ' <<< "$o" && grep -qF "$3" <<< "$o"; then
      st_pass=$((st_pass + 1)); printf 'ok    %s\n' "$1"
    else
      st_fail=$((st_fail + 1)); printf 'NOT OK %s — expected a failure naming: %s\n' "$1" "$3"
      printf '%s\n' "$o" | sed 's/^/         | /'
    fi
  }

  # A fixture repository carrying the full correct set, which each arm then breaks one way.
  mk() { # $1=name -> echoes path
    local d="$ST_TMP/$1"
    mkdir -p "$d/scripts" "$d/.claude" "$d/$(dirname "$SKILL_REL")"
    git -C "$d" init -q 2>/dev/null || git init -q "$d"
    printf '.claude/.bash-write-marker\n.claude/.bash-write-blocked\n.claude/.template-sync-check\n.claude/.local-llm-*\n.claude/state/\n.claude/validation/\n' > "$d/.gitignore"
    { echo '### 3a. .gitignore additions'
      echo '- `.claude/.bash-write-marker` (t)'
      echo '- `.claude/.bash-write-blocked` (t)'
      echo '- `.claude/.template-sync-check` (t)'
      echo '- `.claude/.local-llm-*` (t)'
      echo '- `.claude/state/` (t)'
      echo '- `.claude/validation/` (t)'
      echo '### 3b. next'; } > "$d/$SKILL_REL"
    printf '#!/usr/bin/env bash\n: > "$ROOT/.claude/.bash-write-marker"\n' > "$d/scripts/h.sh"
    printf '%s\n' "$d"
  }

  # A — a machine-local marker loses its ignore rule.  This is the bug in the row.
  d=$(mk a); grep -v '^\.claude/\.bash-write-marker$' "$d/.gitignore" > "$d/.g" && mv "$d/.g" "$d/.gitignore"
  arm "A: unignored machine-local marker is caught" "$d" "[A] machine-local but NOT gitignored: .claude/.bash-write-marker"

  # B — an ignore rule swallows a record meant to be committed.
  d=$(mk b); echo '.claude/.template-sync' >> "$d/.gitignore"
  arm "B: an ignored sync record is caught" "$d" "[B] tracked by design but IS gitignored: .claude/.template-sync"

  # C — a hook author adds a marker and classifies it nowhere.  The next marker.
  d=$(mk c); printf '#!/usr/bin/env bash\n: > "$ROOT/.claude/.some-new-marker"\n' > "$d/scripts/new.sh"
  arm "C: an unclassified new marker is caught" "$d" "[C] a marker no bucket claims: .claude/.some-new-marker"

  # D — the seeding list drops an entry, so new projects inherit an incomplete set.
  d=$(mk d); grep -v 'bash-write-blocked' "$d/$SKILL_REL" > "$d/.s" && mv "$d/.s" "$d/$SKILL_REL"
  arm "D: a dropped section-3a entry is caught" "$d" "[D] not seeded to new projects: .claude/.bash-write-blocked"

  # --- the project-local sidecar.  The four arms below are one claim each, and the LOAD-BEARING one
  # is `sidecar silences [C]` — without it the file could be parsed and thrown away and every other
  # arm here would still be green, which is the shape 007br recorded (a falsification arm that
  # falsified nothing).
  local nd
  narm() { # $1=name  $2=fixture dir  $3=substring that must NOT appear
    local o
    o=$(FAILURES=0; CHECKS=0; run_checks "$2" "$2/$SKILL_REL" 2>&1)
    if grep -qF "$3" <<< "$o"; then
      st_fail=$((st_fail + 1)); printf 'NOT OK %s — this must not have been reported: %s\n' "$1" "$3"
      printf '%s\n' "$o" | sed 's/^/         | /'
    else
      st_pass=$((st_pass + 1)); printf 'ok    %s\n' "$1"
    fi
  }

  # A hook writes a marker this template does not ship; the project classifies it in its own file.
  mk_sidecar() { # $1=name  $2=sidecar body -> echoes path
    local d; d=$(mk "$1")
    printf '#!/usr/bin/env bash\n: > "$ROOT/.claude/.proj-marker"\n' > "$d/scripts/proj.sh"
    printf '%s\n' "$2" > "$d/.claude/.runtime-markers"
    printf '.claude/.proj-marker\n' >> "$d/.gitignore"
    printf '%s\n' "$d"
  }

  # E1 — no sidecar at all: the marker is unclaimed.  The state the sidecar exists to leave.
  d=$(mk e1); printf '#!/usr/bin/env bash\n: > "$ROOT/.claude/.proj-marker"\n' > "$d/scripts/proj.sh"
  arm "E1: without a sidecar a project marker is unclaimed" "$d" "[C] a marker no bucket claims: .claude/.proj-marker"

  # E2 — the load-bearing one: with the sidecar, the SAME marker is claimed and [C] is silent.
  nd=$(mk_sidecar e2 '[machine-local]
.claude/.proj-marker%written by this project only')
  narm "E2: a sidecar entry silences [C] for that marker" "$nd" "[C] a marker no bucket claims: .claude/.proj-marker"

  # E3 — the sidecar feeds assertion A, not just C.  Classifying churn without ignoring it is
  # a declaration that the path is churn and a repository that commits it anyway.
  d=$(mk_sidecar e3 '[machine-local]
.claude/.proj-marker%written by this project only')
  grep -v '^\.claude/\.proj-marker$' "$d/.gitignore" > "$d/.g" && mv "$d/.g" "$d/.gitignore"
  arm "E3: a sidecar machine-local path must still be gitignored" "$d" "[A] machine-local but NOT gitignored: .claude/.proj-marker"

  # E4 — a path with no reason is not a classification.  The reason is the contestable half.
  d=$(mk_sidecar e4 '[machine-local]
.claude/.proj-marker')
  arm "E4: a sidecar line with no reason is refused" "$d" "[E] .claude/.runtime-markers is malformed: not path%reason: .claude/.proj-marker"

  # E5 — an entry before any section header has no bucket, so it decides nothing.
  d=$(mk_sidecar e5 '.claude/.proj-marker%no section above me')
  arm "E5: a sidecar line outside any section is refused" "$d" "[E] .claude/.runtime-markers is malformed: line outside any section"

  # E6 — assertion D must NOT demand a sidecar path in section 3a: the template cannot seed a
  # marker written by a hook it does not ship, so requiring it would make the sidecar unusable
  # on the first use.  This is the arm that pins the one place the merged list is deliberately
  # not used.
  nd=$(mk_sidecar e6 '[machine-local]
.claude/.proj-marker%written by this project only')
  narm "E6: section 3a is not required to seed a project-local marker" "$nd" "[D] not seeded to new projects: .claude/.proj-marker"

  printf '\nself-test: %d passed, %d failed\n' "$st_pass" "$st_fail"
  [ "$st_fail" -eq 0 ] || return 1
  return 0
}

# --------------------------------------------------------------------------- main
if [ "${1-}" = "--self-test" ]; then
  self_test; exit $?
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=""
if [ -z "$ROOT" ]; then
  # Labelled, never silent: a skip that reads like a pass is the exact shape this register keeps
  # recording (checkpoint F-11 — the gate reporting something other than what it measured).
  printf 'skip: not inside a git repository — `git check-ignore` has nothing to answer against.\n'
  exit 0
fi

run_checks "$ROOT" "$ROOT/$SKILL_REL"

if [ "$FAILURES" -eq 0 ]; then
  N_LOCAL=$(local_markers "$ROOT" machine-local | grep -vc '^!' || true)
  N_TRACKED=$(local_markers "$ROOT" tracked-by-design | grep -vc '^!' || true)
  N_PROJ=$((N_LOCAL + N_TRACKED))
  printf 'ok: %d runtime-marker checks passed (%d machine-local, %d tracked by design%s).\n' \
    "$CHECKS" \
    "$(( $(col1 "$MACHINE_LOCAL" | grep -c .) + N_LOCAL ))" \
    "$(( $(col1 "$TRACKED_BY_DESIGN" | grep -c .) + N_TRACKED ))" \
    "$([ "$N_PROJ" -gt 0 ] && printf '; %d from %s' "$N_PROJ" "$MARKERS_REL")"
  exit 0
fi
printf '\n%d of %d runtime-marker checks failed.\n' "$FAILURES" "$((FAILURES + CHECKS))"
exit 1
