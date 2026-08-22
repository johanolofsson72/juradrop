#!/bin/bash
# Enforce this project's spec-kit extension policy.
#
# spec-kit 0.16.x ships extensions that `specify init --here --force` enables by
# default. One of them, `git`, registers five skills — speckit-git-feature,
# -git-validate, -git-commit, -git-remote, -git-initialize — that directly
# contradict how these projects work:
#
#   - git-feature creates numbered FEATURE BRANCHES, but .claude/rules/spec-register.md
#     is explicit: "No feature branches, no merge step" — one spec, one commit,
#     pushed straight to the working branch;
#   - git-validate enforces feature-branch NAMING, which only makes sense given
#     the branches we do not create;
#   - git-commit auto-commits after every Spec Kit phase, which would shred the
#     one-commit-per-spec protocol and bypass the commit-message discipline.
#
# Nothing auto-fires today — branch creation is not wired into create-new-feature.sh
# — but the skills are model-invocable, so a future session can reach for them
# believing they are part of the pipeline. Prose in a rule file does not stop that;
# disabling the extension does.
#
# `agent-context` stays ENABLED: refreshing the managed Spec Kit section of the
# agent context file is useful and conflicts with nothing.
#
# Idempotent, silent when the policy already holds. Must run AFTER every
# `specify init --force`, which re-enables everything.
#
# Usage: speckit-extension-policy.sh [--repo <path>] [--dry-run]
# Exit: 0 = policy holds (changed or already correct), 1 = could not apply.

set -u

REPO=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    shift; REPO="${1:-}" ;;
    --dry-run) DRY=1 ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

[ -n "$REPO" ] || REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
REG="$REPO/.specify/extensions/.registry"
[ -f "$REG" ] || exit 0            # no spec-kit extensions here — nothing to enforce
command -v python3 >/dev/null 2>&1 || exit 0

# Extensions this project refuses to run. Space-separated.
DISABLE="${SPECKIT_DISABLED_EXTENSIONS:-git}"

# Flipping the registry flag is only half the job. `enabled: false` governs what
# SPEC-KIT wires; it does not delete the skill files, and Claude Code discovers
# skills by file presence. The five speckit-git-* SKILL.md files ship with
# `disable-model-invocation: false`, so Claude can still reach for
# /speckit-git-feature on a disabled extension. Flip that frontmatter too:
# `user-invocable: true` is left alone, so a human can still run one
# deliberately — the model just cannot pick it up on its own.
neutralize_skills() {
  _root="$1"; _n=0
  for _sk in "$_root"/.claude/skills/speckit-git-*/SKILL.md; do
    [ -f "$_sk" ] || continue
    grep -q '^disable-model-invocation: false' "$_sk" 2>/dev/null || continue
    [ "$DRY" = "1" ] && { _n=$((_n + 1)); continue; }
    _tmp="$_sk.tmp.$$"
    sed 's/^disable-model-invocation: false/disable-model-invocation: true/' "$_sk" > "$_tmp" 2>/dev/null \
      && mv "$_tmp" "$_sk" && _n=$((_n + 1))
    rm -f "$_tmp" 2>/dev/null
  done
  [ "$_n" -gt 0 ] && printf 'speckit-extension-policy: %s disable-model-invocation on %s speckit-git-* skill(s)\n' \
    "$([ "$DRY" = "1" ] && echo 'would set' || echo 'set')" "$_n"
  return 0
}
neutralize_skills "$REPO"

python3 - "$REG" "$DISABLE" "$DRY" <<'PY'
import json, sys
path, disable, dry = sys.argv[1], sys.argv[2].split(), sys.argv[3] == "1"
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception as exc:
    print(f"speckit-extension-policy: cannot read registry ({exc})", file=sys.stderr)
    sys.exit(1)

exts = data.get("extensions", {})
changed = []
for name in disable:
    ext = exts.get(name)
    if isinstance(ext, dict) and ext.get("enabled") is not False:
        ext["enabled"] = False
        changed.append(name)

if not changed:
    sys.exit(0)

if not dry:
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")

skills = []
for name in changed:
    skills += exts[name].get("registered_skills", [])
print(f"speckit-extension-policy: {'would disable' if dry else 'disabled'} "
      f"{', '.join(changed)} ({len(skills)} skill(s): {', '.join(skills)})")
print("  reason: feature branches / per-phase auto-commit conflict with "
      ".claude/rules/spec-register.md (one spec, one commit, direct push)")
PY
