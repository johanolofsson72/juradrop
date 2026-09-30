#!/bin/bash
# No script may run template-autosync.sh except through drive_sync (spec 011, landed from
# consultpilot H7bo; spec 010 before it).
#
# THE DEFECT THIS GATE CLOSES. template-autosync.sh resolves its target as
# `${CLAUDE_PROJECT_DIR:-$PWD}`. A caller that selects its target with `cd` alone has therefore not
# selected it at all: under a Claude Code hook the harness has already exported CLAUDE_PROJECT_DIR,
# pointing at the real repository, and it wins. On 2026-08-30 test-template-autosync-stranded.sh
# did exactly that from the Stop hook and synced the real repository against a three-file sandbox
# template — 54 `chore(sync)` commits made and pushed to origin/main, and 505 lines deleted in the
# working tree, including 61 of the 62 lines of .claude/rules/continuous-execution.md.
#
# THE RULE, ENTIRE. A script under scripts/ may not RUN template-autosync.sh. It goes through
# scripts/drive-sync.sh, which owns both halves of the declaration (CLAUDE_PROJECT_DIR names the
# target, CLAUDE_TEMPLATE_SYNC_SANDBOX declares where it may write), the `/` and contains-this-repo
# refusals, the cwd, the timeout and the choice of binary — checked once, against values.
#
# Spec 010's version of this gate asked "does each invocation carry both halves?", and asking it
# meant reverse-engineering a convention spelled by hand at 19 sites: a handle derivation, two match
# arms, a two-line lookback, a `/` branch and seven exclusions, two of which only absorbed its own
# false positives. Finding F014 recorded eight shapes it could not see. With one way in, the
# ABSENCE of an invocation is the compliance, and there is no per-line clause to evaluate.
#
# WHAT "RUNS" MEANS. The scanner is a small shell lexer, not a line regex, because every hole the
# line regexes had was a lexing mistake: a `bash` inside `"$(…)"` read as quoted text, a `<<` inside
# a string opening a heredoc that swallowed the rest of the file, a comment ending in `\` joining
# the next line into itself. It walks each logical line (joined while a quote, `$(`, subshell,
# array or `\`-continuation is still open) keeping a stack of frames — code, "…", '…', $'…', `…`,
# $(…)/(…), and array literals — skips comments and heredoc bodies, and splits code into words and
# separators. A word is a TARGET when it is the literal path (…template-autosync.sh) or a handle:
# a variable whose assigned value ENDS in -autosync.sh. A target is RUN when, within its own
# command segment:
#
#   (a) the nearest preceding non-option word is an interpreter — bash, sh, zsh, dash, ksh,
#       source, `.`, exec, $BASH, $SHELL, find's -exec — whatever comes before that; or
#   (b) every preceding word is transparent — an assignment, a redirection with its file,
#       an option, a number, or env/timeout/nohup/time/command/nice/sudo/xargs/if/then/do/!/{ —
#       i.e. the path itself is the command word (the sync carries a #! line); or
#   (c) the segment's command is `eval`, or an interpreter with -c, and the target appears
#       anywhere in the rest of the segment, quoted or not, because that text IS code.
#
# A redirection's file (`> "$d/scripts/template-autosync.sh"`) and an array element are not runs:
# a bare `>` is neither an interpreter nor transparent, and array elements are data.
#
# WHAT IS EXEMPT, AND WHY THE SHAPE OF THE EXEMPTION MATTERS
#
# By PROPERTY — checked, so nobody can write their way into them:
#
#   The sync itself: template-autosync.sh re-execs itself. "This file IS the sync" is not a habit.
#
#   The helper's definition site, which must run the sync because that is its job. The price of
#   that exemption is paid below: the gate asserts there is EXACTLY ONE definition of
#   drive_sync/drive_sync_readonly and that it is scripts/drive-sync.sh. Otherwise any driver could
#   define its own drive_sync() and walk out through the gap.
#
#   Query-mode runs. --is-core, --list-core-scripts, --list-core-rules and --template-dir return
#   from template-autosync.sh ABOVE the project-root resolution — they never resolve a root, so
#   they cannot write, so there is nothing for a declaration to constrain. Judged per command
#   SEGMENT, not per line or per file: a query on one side of `;` does not excuse a sync on the
#   other, and a `# --is-core` comment is a comment. test-validate-sync-sandbox-declarations.sh
#   asserts the property for each mode; move one below the resolution and it reddens.
#
# By ARGUED LIST — exactly four, contestable by deleting an entry and re-running (the harness
# pins the count, so the list cannot grow quietly). The developer set the template's cap at 4 on
# 2026-09-29; consultpilot's is 3, because it has no lane-catchup.sh.
#
# RESIDUALS, NAMED. A sync reached through a user function's positional parameter
# (`run() { bash "$1"; }; run "$SYNC"`), through a copy under a name that does not end in
# -autosync.sh, behind a wrapper command this lexer does not know (`sudo -u x "$SYNC"`), or under a
# deliberately quote-spliced name (`template-auto""sync.sh`, which the grep narrowing never selects)
# is not seen. The adversary here is the next honest author of a self-test, not someone obfuscating.
# The six drivers are held to the helper by the harness's census instead, which is the stronger
# check for exactly those files.
#
# Offline. Reads scripts as text and starts nothing — a gate proving the sync cannot escape its
# sandbox must not become the caller that does.
#
# Scenario ids deliberately absent: this file is CORE and ships into projects whose SC numbering
# is their own (row 012).
#
# Exit: 0 = clean, 1 = violations found, 2 = cannot answer.
# Run: bash scripts/validate-sync-sandbox-declarations.sh [--quiet]

set -u

QUIET=0
for a in "$@"; do
  case "$a" in
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

ROOT="${SANDBOX_GATE_ROOT:-}"
if [ -z "$ROOT" ]; then
  ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || { echo "cannot resolve repo root" >&2; exit 2; }
fi
[ -d "$ROOT/scripts" ] || { echo "no scripts/ under $ROOT" >&2; exit 2; }

HELPER_REL="scripts/drive-sync.sh"

# The scanner runs inside a command substitution, so a broken awk program would write to stderr,
# produce no lines, and the gate would report a clean tree — a status shaped like success for a
# check that never ran. Its stderr lands here and is read before any verdict is printed.
SCAN_ERR=$(mktemp 2>/dev/null) || { echo "cannot create a temp file" >&2; exit 2; }
trap 'rm -f "$SCAN_ERR"' EXIT

# path|reason. Four entries, each falsifiable: delete it, re-run, and read what the gate says.
EXCLUDED="
scripts/template-autosync-hook.sh|SessionStart hook — syncs the real repository on purpose and passes CLAUDE_PROJECT_DIR for it. A sandbox declaration would be a lie about its target
scripts/core-owed-tick-guard-hook.sh|PreToolUse guard — must answer --owed/--unlisted about the repository holding the edited file, and passes CLAUDE_PROJECT_DIR for it. Same reason
scripts/lane-catchup.sh|developer-run catch-up — previews a --force --dry-run sync of its own repository (it cds to the git toplevel and passes CLAUDE_PROJECT_DIR for it). Same reason
scripts/test-validate-sync-sandbox-declarations.sh|this gate's own harness — its non-compliant invocations are fixtures, and run_sync/sync_undeclared must hand the interlock invalid or absent declarations, which drive_sync refuses before the interlock could be tested
"

EXCLUDED_KEYS="|"
while IFS='|' read -r _p _r; do
  [ -n "$_p" ] || continue
  EXCLUDED_KEYS="$EXCLUDED_KEYS$_p|"
done <<EOF
$EXCLUDED
EOF
inlist() { case "$1" in *"|$2|"*) return 0 ;; *) return 1 ;; esac; }
is_excluded() { inlist "$EXCLUDED_KEYS" "$1"; }

# ------------------------------------------------------------------ the lexer
#
# One awk process over every selected file. Emits one line per finding, tab-separated:
#   I <file> <line> <segment>   a run of the sync
#   F <file> <line> <segment>   a run of the sync inside a function body
#   Q <file> <line> <segment>   a run in a query mode
#   D <file> <line> <name>      a definition of drive_sync or drive_sync_readonly
#   T <file> <line> <word>      a definition of, or assignment to, one of the helper's internals
#   E <file> <line> <why>       the file could not be lexed to its end — the gate cannot answer
read -r -d '' LEXER <<'AWK'
function push(t) { d++; ft[d] = t; fs[d] = ++serial; fh[d] = 0; bd[d] = 0; AM[serial] = 0; LW[serial] = "" }
# A word is flushed as a token. A substitution in the middle of a word — `"$(dirname "$0")/x.sh"` —
# splits the lexing but not the word: the text after the `)` is GLUED back onto the word that was
# open when the `$(` started, so the target test sees `"/x.sh"` and not a fragment it skips. The
# first version kept the tail as a separate, ignored token, and `bash "$(dirname "$0")/template-
# autosync.sh"` was invisible (adversarial review, 011).
function flush(   k) {
  if (cur == "") { glue = 0; return }
  if (glue && gh > 0) { TT[gh] = TT[gh] cur; LASTW = gh }
  else {
    # A word belongs to the COMMAND it is a word of, so it takes the nearest enclosing code frame, not
    # the quote it was flushed from: `echo "see $(pwd)/template-autosync.sh"` has `echo` before it.
    k = d; while (k > 0 && (ft[k] == 1 || ft[k] == 2 || ft[k] == 7 || ft[k] == 9)) k--
    NT++; TT[NT] = cur; TK[NT] = "w"; TF[NT] = fs[k]; TY[NT] = ft[k]; TL[NT] = wl; LASTW = NT
  }
  LW[TF[LASTW]] = TT[LASTW]
  if (TY[LASTW] == 5 && mentions(TT[LASTW])) AM[TF[LASTW]] = 1
  cur = ""; glue = 0
}
function sep() { flush(); NT++; TT[NT] = ""; TK[NT] = "s"; TF[NT] = fs[d]; TY[NT] = ft[d]; TL[NT] = ln }
function wordc(c) { if (cur == "") wl = ln; cur = cur c }
# A $(…), `…`, (…), $((…)) or array literal opening mid-word remembers the word it interrupts.
function opensub(t,   h) {
  if (cur != "") { flush(); h = LASTW } else h = (glue ? gh : 0)
  glue = 0; push(t); fh[d] = h
}
function closesub(   h, nm) {
  flush(); h = fh[d]
  # `S=$(realpath scripts/template-autosync.sh)` and `CMD=(bash ".../template-autosync.sh" --force)`:
  # the value is what the substitution or the array holds, so the name becomes a handle here.
  if (h > 0 && TT[h] ~ /^[A-Za-z_][A-Za-z0-9_]*\+?="?$/) {
    nm = TT[h]; sub(/\+?="?$/, "", nm)
    if ((ft[d] == 6 && bare(LW[fs[d]]) ~ /-autosync\.sh$/) || (ft[d] == 5 && AM[fs[d]])) addhandle(nm)
  }
  gh = h; d--; glue = 1
}
function addhandle(n) { if (n != "" && index("|" handles "|", "|" n "|") == 0) handles = handles (handles == "" ? "" : "|") n }
# A resumable lexer. lex_start opens a logical line; lex_feed lexes one more physical line into it,
# keeping the frame stack, so a line joined across 60 physical lines costs 60 lines of work, not
# 60 x 60. Tokens: TT text, TK kind (w word, s separator), TF frame serial, TY frame type, TL physical
# line. Frames: 0 top, 1 "…", 2 '…', 4 `…`, 5 array literal, 6 $(…)/(…), 7 $'…', 8 $((…)) arithmetic,
# 9 ${…}. Heredoc delimiters found on a line queue in PD/PT at once, so a body opened mid-way through
# a joined line (`x=$(cat <<EOF`) is skipped rather than lexed.
function lex_start(at) { NT = 0; d = 0; ft[0] = 0; serial = 0; fs[0] = 0; cur = ""; glue = 0; gh = 0; ln = at; wl = at; pend_bs = 0 }
function lex_done() { return (d == 0 && !pend_bs) }
function lex_feed(s, first,   n, i, c, nx, t, dl, q, rest, tab, k) {
  if (!first) {
    if (pend_bs) { pend_bs = 0; ln++; if (ft[d] != 1) flush() }  # a `\`-continuation: no separator
    else { t = ft[d]; if (t == 1 || t == 2 || t == 7 || t == 9) { cur = cur "\n" } else if (t != 8) sep(); ln++ }
  }
  n = length(s)
  for (i = 1; i <= n; i++) {
    t = ft[d]
    # Fast paths: consume a run of characters that cannot change state in one step. Per-character
    # substr() is what an awk lexer spends its time on.
    if (t == 2) { k = index(substr(s, i), "'"); if (k == 0) { cur = cur substr(s, i); break } cur = cur substr(s, i, k); i += k - 1; d--; continue }
    if (t == 1 && match(substr(s, i), /^[^"\\$`]+/)) { cur = cur substr(s, i, RLENGTH); i += RLENGTH - 1; continue }
    if ((t == 0 || t == 4 || t == 5 || t == 6) && match(substr(s, i), /^[^] \t"'\\`$()<;|&#=[]+/)) { if (cur == "") wl = ln; cur = cur substr(s, i, RLENGTH); i += RLENGTH - 1; continue }
    c = substr(s, i, 1); nx = substr(s, i + 1, 1)
    if (t == 7) { cur = cur c; if (c == "\\") { cur = cur nx; i++ } else if (c == "'") d--; continue }
    # $((…)) is arithmetic: `<<` there is a shift, not a heredoc, and nothing in it is a command.
    # Reading `m=$(( 1 << 3 ))` as a heredoc named `3` swallowed the rest of the file (review, 011).
    if (t == 8) {
      if (c == "(") bd[d]++
      else if (c == ")") { if (bd[d] > 0) bd[d]--; else { if (nx == ")") i++; closesub() } }
      continue
    }
    # ${…} is part of the word it sits in; `<<`, `#`, `;` inside it are text.
    if (t == 9) {
      if (c == "\\") { cur = cur c nx; i++; continue }
      if (c == "}") { cur = cur c; if (bd[d] > 0) bd[d]--; else d--; continue }
      if (c == "{") bd[d]++
      if (c == "\"") { cur = cur c; push(1); continue }
      if (c == "'") { cur = cur c; push(2); continue }
      cur = cur c; continue
    }
    if (t == 1) {
      if (c == "\\") { if (nx == "") { pend_bs = 1; continue } cur = cur c nx; i++; continue }
      if (c == "\"") { cur = cur c; d--; continue }
      if (c == "$" && nx == "{") { cur = cur "${"; i++; push(9); continue }
      if (c == "$" && nx == "(") { i++; if (substr(s, i + 1, 1) == "(") { i++; opensub(8) } else opensub(6); continue }
      if (c == "`") { opensub(4); continue }
      cur = cur c; continue
    }
    # a code frame: 0 top level, 4 backticks, 5 array literal, 6 $(…) or (…)
    if (c == "\\") {
      if (nx == "") { pend_bs = 1; continue }             # continues on the next physical line
      wordc(c nx); i++; continue
    }
    if (c == " " || c == "\t") { flush(); continue }
    # A comment starts only at a word boundary. Right after `)` or a closing backtick the word is
    # still open (`x=$(:)#…` is one word in bash), which the first version got wrong.
    if (c == "#" && cur == "" && !glue) break
    if (c == ";" || c == "|") { sep(); continue }
    if (c == "&") { if (cur ~ /[<>]$/) { wordc(c); continue } sep(); continue }
    if (c == "$" && nx == "{") { wordc("${"); i++; push(9); continue }
    if (c == "<" && nx == "<" && substr(cur, length(cur)) != "<") {
      flush(); i += 2
      tab = 0; if (substr(s, i, 1) == "-") { tab = 1; i++ }
      while (substr(s, i, 1) ~ /[ \t]/) i++
      dl = ""
      while (i <= n) {
        q = substr(s, i, 1)
        if (q ~ /[ \t;&|<>()]/) break                    # so a here-string's third `<` yields no delimiter
        if (q == "\"" || q == "'") { i++; while (i <= n && substr(s, i, 1) != q) { dl = dl substr(s, i, 1); i++ } i++; continue }
        if (q == "\\") { i++; q = substr(s, i, 1) }
        dl = dl q; i++
      }
      i--
      if (dl != "") { PD[++npd] = dl; PT[npd] = tab; PL[npd] = ln }
      continue
    }
    if (c == "(") {
      if (cur ~ /=$/) { opensub(5); continue }             # an array literal
      if (nx == "(" && (cur == "" || cur ~ /\$$/)) { if (cur ~ /\$$/) cur = substr(cur, 1, length(cur) - 1); i++; opensub(8); continue }
      if (cur ~ /[$<>]$/) { cur = substr(cur, 1, length(cur) - 1); opensub(6); continue }
      rest = substr(s, i + 1)
      if (match(rest, /^[ \t]*\)/)) { flush(); i += RLENGTH; NT++; TT[NT] = "()"; TK[NT] = "s"; TF[NT] = fs[d]; TY[NT] = ft[d]; TL[NT] = ln; continue }
      flush(); push(6); continue
    }
    if (c == ")") {
      if (t == 5 || t == 6) { closesub(); continue }
      sep(); continue                                    # a `case` pattern's close
    }
    if (c == "`") { if (t == 4) closesub(); else opensub(4); continue }
    if (c == "\"") { wordc(c); push(1); continue }
    if (c == "'") { wordc(c); push(cur ~ /[$]'$/ ? 7 : 2); continue }
    wordc(c)
  }
}
function is_assign(w) { return (w ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/) }
function bare(w) { gsub(/["'{}]/, "", w); return w }
function base(w) { w = bare(w); sub(/.*\//, "", w); return w }
function is_interp(w,   b) {
  b = base(w)
  return (b ~ /^(bash|sh|zsh|dash|ksh|mksh|ash|source|\.|exec|-exec|-execdir|-ok)$/ || bare(w) ~ /^\$(BASH|SHELL)$/)
}
function is_transparent(w,   b) {
  if (is_assign(w)) return 1       # an assignment prefix
  if (w ~ /^[0-9]*(>>?|<|&>)[^ ]+$/ || w ~ /^[0-9]*>&[0-9-]+$/) return 1   # a redirection with its file
  if (w ~ /^-/) return 1
  if (w ~ /^[0-9]+(\.[0-9]+)?[smhd]?$/) return 1
  b = base(w)
  return (b ~ /^(env|timeout|gtimeout|nohup|time|command|builtin|nice|ionice|sudo|doas|exec|xargs|caffeinate|stdbuf|setsid|coproc|busybox|then|do|else|elif|if|while|until|!|\{)$/)
}
# Options that take the NEXT word as their argument, so that word is neither the command nor a
# blocker: `bash -o pipefail "$S"`, `exec -a name "$S"`, `env -u VAR "$S"`, `timeout -s KILL 5 "$S"`.
function takes_arg(w) { return (w ~ /^-(o|O|a|u|s|k|n|C|g|p|-signal|-kill-after|-unset|-chdir)$/) }
function is_target(w,   b) {
  if (is_assign(w)) return 0      # an assignment holds a path, it runs nothing
  b = bare(w)
  if (b ~ /template-autosync\.sh$/) return 1
  # A handle anywhere in the word: "$S", "${S:?}", "$PWD/scripts/$NAME", "${CMD[@]}".
  if (handles != "" && b ~ ("\\$(" handles ")([^A-Za-z0-9_]|$)")) return 1
  return 0
}
function mentions(w) { return (index(w, "template-autosync.sh") > 0 || (handles != "" && w ~ ("\\$\\{?(" handles ")([^A-Za-z0-9_]|$)"))) }
function segment(i,   j, a, b, out) {                                 # the command segment holding token i
  a = i; while (a > 1 && !(TK[a-1] == "s" && TF[a-1] == TF[i])) a--
  b = i; while (b < NT && !(TK[b+1] == "s" && TF[b+1] == TF[i])) b++
  out = ""
  for (j = a; j <= b; j++) if (TK[j] == "w" && TF[j] == TF[i]) out = out (out == "" ? "" : " ") TT[j]
  gsub(/[\t\n]/, " ", out)
  return out
}
# Is the run a query mode? Judged on the ARGUMENTS after the target only — redirection operators and
# their files are not argv, so `bash "$S" --force > --is-core` is a writing run and not a query
# (adversarial review, 011: the first version matched anywhere in the segment).
function is_query(i, textual,   k, w, skip) {
  skip = 0
  for (k = i + 1; k <= NT && !(TK[k] == "s" && TF[k] == TF[i]); k++) {
    if (TK[k] != "w" || TF[k] != TF[i]) continue
    w = TT[k]
    if (skip) { skip = 0; continue }
    if (w ~ /^[0-9]*(>|>>|<|<>|>\||&>|&>>|<<<|>&|<&)$/) { skip = 1; continue }
    if (w ~ /^[0-9]*[<>&]/) continue
    if (bare(w) ~ /^--(is-core|list-core-scripts|list-core-rules|template-dir)$/) return 1
    if (textual && w ~ /(^|[ "'])--(is-core|list-core-scripts|list-core-rules|template-dir)([ "']|$)/) return 1
  }
  return 0
}
function report(i, textual) { print (is_query(i, textual) ? "Q" : (FNB > 0 ? "F" : "I")) "\t" FILENAME "\t" TL[i] "\t" segment(i) }
function scan_invoke(   i, j, w, near, allt, pre, k, found, np, P, m, cmdv) {
  for (i = 1; i <= NT; i++) {
    if (TK[i] != "w") continue
    w = TT[i]
    # Function bodies are tracked so the helper's own file is exempt only INSIDE its functions: a
    # run at its top level would fire at source time, in every driver (review, 011).
    if (FNP && w == "{") { FNB++; FNP = 0 } else if (FNB > 0 && w == "{") FNB++; else if (FNB > 0 && w == "}") FNB--
    # (c) eval, or an interpreter with -c: the rest of the segment is code whatever its quoting.
    if ((base(w) == "eval" || (is_interp(w) && i < NT && TK[i+1] == "w" && TF[i+1] == TF[i] && bare(TT[i+1]) ~ /^-[a-z]*c[a-z]*$/)) && TY[i] != 5) {
      pre = 1
      for (j = i - 1; j >= 1 && !(TK[j] == "s" && TF[j] == TF[i]); j--)
        if (TK[j] == "w" && TF[j] == TF[i] && !is_transparent(TT[j])) { pre = 0; break }
      if (pre) {
        found = 0
        for (k = i + 1; k <= NT && !(TK[k] == "s" && TF[k] == TF[i]); k++) if (TK[k] != "s" && mentions(TT[k])) { found = 1; break }
        if (found) { report(i, 1); continue }
      }
    }
    if (!is_target(w) || TY[i] == 5) continue
    # The words before the target, in order, within its own segment and frame.
    np = 0
    for (j = i - 1; j >= 1 && !(TK[j] == "s" && TF[j] == TF[i]); j--) if (TK[j] == "w" && TF[j] == TF[i]) P[++np] = TT[j]
    for (m = 1; m <= np / 2; m++) { k = P[m]; P[m] = P[np - m + 1]; P[np - m + 1] = k }
    # `command -v "$S"` asks where the file is; it does not run it.
    cmdv = 0; for (m = 1; m < np; m++) if (base(P[m]) == "command" && P[m+1] ~ /^-[vV]$/) cmdv = 1
    if (cmdv) continue
    near = ""; allt = 1; m = np
    while (m >= 1) {
      if (P[m] ~ /^-/) { m--; continue }
      if (m > 1 && takes_arg(P[m-1])) { m -= 2; continue }
      break
    }
    if (m >= 1) near = P[m]
    for (m = 1; m <= np; m++) {
      if (m > 1 && takes_arg(P[m-1])) continue
      if (!is_transparent(P[m])) { allt = 0; break }
    }
    if ((near != "" && is_interp(near)) || allt) report(i, 0)
  }
}
# The helper's names are its contract. A second definition of drive_sync or of any _drive_sync_*
# internal, or an assignment to one of its internals, is a way to walk through the exemption its
# definition site enjoys: `_drive_sync_check_sandbox() { :; }` after sourcing it disables the check
# for everything after (review, 011). Reported as D; the gate allows them in one file only.
# D: a definition of an entry point. T: a definition of, or assignment to, one of its internals.
function defn(i, b) { sub(/\(\)$/, "", b); print (b ~ /^drive_sync(_readonly)?$/ ? "D" : "T") "\t" FILENAME "\t" TL[i] "\t" b }
function scan_define(   i, b) {
  for (i = 1; i <= NT; i++) {
    if (TK[i] == "s" && TT[i] == "()") FNP = 1
    if (TK[i] != "w") continue
    b = bare(TT[i])
    if (b ~ /^_?drive_sync[A-Za-z0-9_]*\(\)$/) { defn(i, b); continue }
    if (b ~ /^_?drive_sync[A-Za-z0-9_]*$/ && i < NT && TT[i+1] == "()") { defn(i, b); continue }
    if (b == "function" && i < NT && TK[i+1] == "w" && bare(TT[i+1]) ~ /^_?drive_sync[A-Za-z0-9_]*(\(\))?$/) { defn(i, bare(TT[i+1])); FNP = 1; continue }
    if (TT[i] ~ /^_drive_sync_[A-Za-z0-9_]*\+?=/) print "T\t" FILENAME "\t" TL[i] "\t" TT[i]
  }
}
# Handles assigned on this logical line become visible to it and to every later one: `S=…; bash "$S"`,
# `local -r S=…`, and `for S in …/template-autosync.sh; do`.
function derive_handles(   i, nm, v, k) {
  for (i = 1; i <= NT; i++) {
    if (TK[i] != "w") continue
    if (is_assign(TT[i])) {
      nm = TT[i]; sub(/\+?=.*/, "", nm); v = TT[i]; sub(/^[^=]*=/, "", v)
      if (bare(v) ~ /-autosync\.sh$/) addhandle(nm)
    }
    if (TT[i] == "for" && i + 2 <= NT && TK[i+1] == "w" && TT[i+2] == "in")
      for (k = i + 3; k <= NT && !(TK[k] == "s" && TF[k] == TF[i]); k++) if (TK[k] == "w" && bare(TT[k]) ~ /-autosync\.sh$/) addhandle(TT[i+1])
  }
}
function finish_line() { flush(); derive_handles(); scan_define(); scan_invoke(); open = 0; joins = 0 }
function end_file() {
  if (open) { print "E\t" CURF "\t" bufat "\tan unclosed quote, $(, ${ or ( reaches the end of the file"; finish_line() }
  # A heredoc that never closes swallowed everything after it. Silence here would be a clean report
  # for a file that was never read — the review's arithmetic `<<` did exactly that.
  if (hp <= npd) print "E\t" CURF "\t" PL[hp] "\ta heredoc delimited by '" PD[hp] "' never closes, so the rest of the file was not read"
  hp = 1; npd = 0; open = 0; FNB = 0; FNP = 0
}
# A handle is a variable whose assigned VALUE ends in -autosync.sh. Spec 010's derivation took any
# assignment that MENTIONED the name, so lane-catchup.sh's `TPL=$( [ -f scripts/template-autosync.sh ]
# && … --template-dir )` made TPL a handle and a later `bash "$TPL/scripts/install-global-skills.sh"`
# a violation. This pre-pass finds them before the scan, so a function body that uses a handle
# assigned further down still sees it; derive_handles adds the shapes a line regex cannot read.
BEGIN {
  hp = 1; npd = 0
  for (a = 1; a < ARGC; a++) {
    f = ARGV[a]; handles = ""
    while ((getline line < f) > 0) {
      if (line !~ /^[ \t]*((export|declare|local|typeset|readonly)[ \t]+(-[a-zA-Z]+[ \t]+)*)?[A-Za-z_][A-Za-z0-9_]*=[^#;&|]*-autosync\.sh["'}]*[ \t]*([;#].*)?$/) continue
      sub(/^[ \t]*/, "", line); sub(/^(export|declare|local|typeset|readonly)[ \t]+/, "", line)
      while (line ~ /^-[a-zA-Z]+[ \t]+/) sub(/^-[a-zA-Z]+[ \t]+/, "", line)
      nm = substr(line, 1, index(line, "=") - 1)
      addhandle(nm)
    }
    close(f); H[f] = handles
  }
}
FNR == 1 { if (CURF != "") end_file(); CURF = FILENAME; handles = H[FILENAME] }
{
  if (hp <= npd) {                                       # inside a heredoc body
    body = $0; if (PT[hp]) sub(/^\t+/, "", body)
    if (body == PD[hp]) hp++
    next
  }
  if (!open) { lex_start(FNR); bufat = FNR; lex_feed($0, 1); open = 1 } else { lex_feed($0, 0); joins++ }
  if (lex_done()) { finish_line(); next }
  if (joins >= 400) { print "E\t" CURF "\t" bufat "\tan unclosed quote, $(, ${ or ( runs past 400 lines"; finish_line() }
}
END { if (CURF != "") end_file() }
AWK

TAB="	"

# The inputs. Two sound supersets, narrowed by grep: a run needs the literal `template-autosync.sh`
# or a handle assigned a value ending `-autosync.sh`, so a file with no `autosync` cannot hold one;
# a definition must contain the name it defines. The sync itself is left out — it is exempt by
# property and nothing in it is read. Everything else, excluded files included, is lexed: an
# excluded file is not judged for runs, but a second drive_sync definition in one would still be a
# way out of this gate.
# Shell files only, but not only `*.sh`: an extensionless script with a shell #! line, a `.bash`
# file and a symlink run just as well, and the first version never opened them (review, 011).
FILES=$( find "$ROOT/scripts" \( -type f -o -type l \) -exec grep -l -e 'autosync' -e 'drive_sync' {} + 2>/dev/null \
         | grep -v "^$ROOT/scripts/template-autosync.sh$" | sort -u \
         | while IFS= read -r _f; do
             case "${_f##*/}" in
               (*.sh|*.bash) printf '%s\n' "$_f" ;;
               (*.*) ;;
               (*) awk 'NR == 1 && /^#!.*[\/ ](ba|z|k|da|a)?sh([[:space:]]|$)/ { f = 1 } END { exit !f }' "$_f" 2>/dev/null && printf '%s\n' "$_f" ;;
             esac
           done )

SCAN=""
[ -n "$FILES" ] && SCAN=$(printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 awk "$LEXER" 2>>"$SCAN_ERR")

DEFINERS="|"; TAMPER=""; CANNOT=""; RUNS=""; RUN_FILES="|"; QUERY_FILES="|"; CHECKED=0
while IFS="$TAB" read -r kind file num text; do
  [ -n "$kind" ] || continue
  rel="${file#$ROOT/}"
  case "$kind" in
    D) inlist "$DEFINERS" "$rel" || DEFINERS="$DEFINERS$rel|" ;;
    T) [ "$rel" = "$HELPER_REL" ] || TAMPER="${TAMPER}  $rel:$num — $text
" ;;
    E) CANNOT="${CANNOT}  $rel:$num: $text
" ;;
    Q) inlist "$QUERY_FILES" "$rel" || QUERY_FILES="$QUERY_FILES$rel|" ;;
    I|F) is_excluded "$rel" && continue
       # PROPERTY: the helper runs the sync inside its two functions, which is its job. A run at its
       # top level would fire at source time in every driver, so only function bodies are exempt.
       [ "$rel" = "$HELPER_REL" ] && [ "$kind" = "F" ] && continue
       RUNS="$RUNS$rel$TAB$num$TAB$text
"
       inlist "$RUN_FILES" "$rel" || { RUN_FILES="$RUN_FILES$rel|"; CHECKED=$((CHECKED + 1)); } ;;
  esac
done <<EOF
$SCAN
EOF

# ------------------------------------------------------------------ the uniqueness assertion
#
# The price of exempting the helper by property rather than by name. Without it, any driver could
# define its own drive_sync() and be exempt from the rule it is meant to obey — or, having sourced
# the real one, redefine or reassign one of its _drive_sync_* internals and switch a check off. Every
# such definition or assignment must sit in the helper's own file. (DRIVE_SYNC_EBADARG is not one:
# the helper returns a literal 64 and never reads it back.)
VIOLATIONS=0
DEFINER_LINES=$(printf '%s' "${DEFINERS#|}" | tr '|' '\n')
DEFINER_COUNT=$(printf '%s' "$DEFINER_LINES" | grep -c . )
if [ "$DEFINERS" != "|$HELPER_REL|" ]; then
  VIOLATIONS=$((VIOLATIONS + 1))
  if [ "$DEFINER_COUNT" -eq 0 ]; then
    say "  $HELPER_REL — nothing defines drive_sync. The rule below exempts its definition site by property; with no definition site the exemption is unanchored"
  else
    say "  drive_sync is defined in $DEFINER_COUNT place(s), and the exemption is only safe for one:"
    printf '%s\n' "$DEFINER_LINES" | while IFS= read -r d; do [ -n "$d" ] && say "      $d"; done
    say "      A second definition site is a way out of this gate. There is exactly one: $HELPER_REL"
  fi
fi

if [ -n "$TAMPER" ]; then
  say "  The helper's internals are redefined or reassigned outside it — each switches one of its checks"
  say "  off for everything after, a way out of this gate:"
  printf '%s' "$TAMPER" | while IFS= read -r t; do [ -n "$t" ] && say "  $t"; done
  VIOLATIONS=$((VIOLATIONS + $(printf '%s' "$TAMPER" | grep -c .)))
fi

# PROPERTY: a file whose every run is a query mode never resolves a root, so it is exempt by that
# property, not by name — a filename list is how the next script gets written the old way and
# passes anyway. Counted per file, and only where no real run sits beside the queries.
EXEMPT_QUERY=0
EXEMPT_SELF=0
[ -f "$ROOT/scripts/template-autosync.sh" ] && EXEMPT_SELF=$((EXEMPT_SELF + 1))
[ -f "$ROOT/$HELPER_REL" ] && EXEMPT_SELF=$((EXEMPT_SELF + 1))
_q="${QUERY_FILES#|}"
while [ -n "$_q" ]; do
  _f="${_q%%|*}"; _q="${_q#*|}"
  is_excluded "$_f" && continue
  [ "$_f" = "$HELPER_REL" ] && continue
  inlist "$RUN_FILES" "$_f" || EXEMPT_QUERY=$((EXEMPT_QUERY + 1))
done

while IFS="$TAB" read -r rel num text; do
  [ -n "$rel" ] || continue
  VIOLATIONS=$((VIOLATIONS + 1))
  say "  $rel:$num — runs template-autosync.sh directly instead of through drive_sync"
  say "      $(printf '%s' "$text" | cut -c1-100)"
done <<EOF
$RUNS
EOF

if [ -s "$SCAN_ERR" ] || [ -n "$CANNOT" ]; then
  echo "the scanner failed; this gate cannot answer:" >&2
  [ -s "$SCAN_ERR" ] && sed 's/^/  /' "$SCAN_ERR" >&2
  [ -n "$CANNOT" ] && printf '%s' "$CANNOT" >&2
  exit 2
fi

say ""
if [ "$VIOLATIONS" -gt 0 ]; then
  say "[sandbox-declarations] $VIOLATIONS violation(s) across $CHECKED file(s); $EXEMPT_QUERY exempt (query modes only), $EXEMPT_SELF by self-reference"
  say ""
  say "  Source the helper and drive the sync through it:"
  say "      . \"\$(dirname \"\$0\")/drive-sync.sh\""
  say "      DRIVE_SYNC_SCRIPT=\"\$SYNC\" drive_sync \"\$P\" \"\$TMP\" --force      # names the target AND declares the sandbox"
  say "      DRIVE_SYNC_SCRIPT=\"\$SYNC\" drive_sync_readonly \"\$P\" --is-core \"\$f\"   # query modes only"
  say ""
  say "  \`cd\` alone does not choose the target — the sync reads \${CLAUDE_PROJECT_DIR:-\$PWD}, and"
  say "  under a hook that variable is already set to the real repository. Specs 010, 011."
  exit 1
fi
say "[sandbox-declarations] 0 direct invocations outside the helper; $CHECKED file(s) checked, $EXEMPT_QUERY exempt (query modes only), $EXEMPT_SELF by self-reference"
exit 0
