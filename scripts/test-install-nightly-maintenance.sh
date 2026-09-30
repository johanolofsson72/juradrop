#!/bin/bash
# test-install-nightly-maintenance.sh — the line the installer writes must run under cron, not just
# look right in a terminal.
#
# The two failures this guards against (fundit F084/F086, row 065):
#   1. the line runs under cron's bare PATH, so dotnet/node/docker are "command not found" every
#      night, and
#   2. a run that fails early (or a line that cannot parse) leaves the log untouched, so "never
#      fired" and "ran and failed" look the same.
# crontab is stubbed to a file; the real crontab is never read or written.
set -uo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUT="$SCRIPT_DIR/install-nightly-maintenance.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

[ -f "$SUT" ] || { echo "install-nightly-maintenance.sh not found — this harness would be vacuous"; exit 1; }

WORK=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$WORK"' EXIT
STUB="$WORK/stub"; TOOLS="$WORK/tools"; mkdir -p "$STUB" "$TOOLS" "$WORK/home"
export CRONTAB_FILE="$WORK/crontab"
cat > "$STUB/crontab" <<'SH'
#!/bin/sh
case "$1" in
  -l) [ -f "$CRONTAB_FILE" ] || exit 1; cat "$CRONTAB_FILE" ;;
  -)  cat > "$CRONTAB_FILE" ;;
  *)  exit 2 ;;
esac
SH
printf '#!/bin/sh\necho fake-dotnet\n' > "$TOOLS/dotnet"
chmod +x "$STUB/crontab" "$TOOLS/dotnet"
BASEPATH="$STUB:$TOOLS:/usr/bin:/bin"

# A project whose maintenance script reports whether it can see the tool.
mkproj() {
  d="$WORK/$1"; mkdir -p "$d/scripts"
  ( cd "$d" && git init -q . >/dev/null 2>&1 )
  cp "$SUT" "$d/scripts/"
  cat > "$d/scripts/project-maintenance.sh" <<'SH'
#!/bin/bash
echo "maintenance ran in $(pwd)"
command -v dotnet >/dev/null && echo "dotnet: found" || echo "dotnet: MISSING"
exit "${FAKE_RC:-0}"
SH
  printf '%s' "$d"
}
inst() { ( cd "$1" && shift; HOME="$WORK/home" PATH="${IPATH:-$BASEPATH}" /bin/bash scripts/install-nightly-maintenance.sh "$@" 2>&1 ); }
rc_inst() { ( cd "$1" && shift; HOME="$WORK/home" PATH="${IPATH:-$BASEPATH}" /bin/bash scripts/install-nightly-maintenance.sh "$@" >/dev/null 2>&1; echo $? ); }
# What cron hands to /bin/sh: the line minus its five schedule fields, under cron's PATH.
cronrun() { cmd=$(sed -E 's/^([^ ]+ ){5}//' <<< "$1"); env -i HOME="$WORK/home" PATH=/usr/bin:/bin /bin/sh -c "$cmd"; }
ourline() { grep -F "claude-nightly-maintenance:$1" "$CRONTAB_FILE"; }

# AC1 + AC2 — the installed line finds a tool only the install shell had, and brackets the log.
P=$(mkproj plain); rm -f "$CRONTAB_FILE"
inst "$P" >/dev/null
L=$(ourline "$P")
[ -n "$L" ] && ok "a line is installed" || bad "no line installed"
cronrun "$L"
LOG="$WORK/home/.claude/nightly/plain.log"
grep -q 'dotnet: found' "$LOG" 2>/dev/null && ok "AC1 under cron's PATH the line still finds dotnet" \
  || bad "AC1 the line runs blind under cron's PATH: $(cat "$LOG" 2>/dev/null | tr '\n' '|')"
[ "$(head -1 "$LOG" 2>/dev/null | cut -c1-21)" = "claude-nightly: start" ] && ok "AC2 the log opens with a start heartbeat" \
  || bad "AC2 no start heartbeat on line 1"
[ "$(tail -1 "$LOG" 2>/dev/null)" = "claude-nightly: end exit=0" ] && ok "AC2 the log ends with the exit code" \
  || bad "AC2 no end line: $(tail -1 "$LOG" 2>/dev/null)"

# AC3 — a root that has moved still writes the heartbeat and a non-zero exit.
M=$(mkproj moving); rm -f "$CRONTAB_FILE"
inst "$M" >/dev/null; L=$(ourline "$M"); mv "$M" "$WORK/moved"
cronrun "$L" 2>/dev/null
LOG="$WORK/home/.claude/nightly/moving.log"
grep -q '^claude-nightly: start' "$LOG" 2>/dev/null && ok "AC3 a failed cd still leaves the start line" \
  || bad "AC3 a failed cd leaves the log untouched"
grep -Eq '^claude-nightly: end exit=[1-9]' "$LOG" 2>/dev/null && ok "AC3 a failed cd records a non-zero exit" \
  || bad "AC3 a failed cd records no failure"

# AC4 — a space and a quote in the root survive quoting, parsing, and cd.
Q=$(mkproj "my proj's"); rm -f "$CRONTAB_FILE"
[ "$(rc_inst "$Q")" = 0 ] && ok "AC4 a root with a space and a quote installs" || bad "AC4 install refused a quoted root"
L=$(ourline "$Q")
cronrun "$L" 2>/dev/null
LOG="$WORK/home/.claude/nightly/my proj's.log"
grep -qF "maintenance ran in $Q" "$LOG" 2>/dev/null && ok "AC4 the line cds into the quoted root" \
  || bad "AC4 the quoted root was not reached: $(cat "$LOG" 2>/dev/null | tr '\n' '|')"

# AC5 — a % in the root is refused before crontab is touched.
C=$(mkproj "pct%dir"); echo "07 07 * * * /usr/bin/true # mine" > "$CRONTAB_FILE"; before=$(cat "$CRONTAB_FILE")
[ "$(rc_inst "$C")" = 2 ] && ok "AC5 a % in the root exits 2" || bad "AC5 a % in the root was not refused"
grep -qi 'refus.*%' <<< "$(inst "$C")" && ok "AC5 the refusal names the %" || bad "AC5 the refusal does not say why"
[ "$(cat "$CRONTAB_FILE")" = "$before" ] && ok "AC5 the crontab is unchanged" || bad "AC5 the crontab changed"

# AC6 — a line that fails sh -n is not installed.
printf '#!/bin/sh\necho "syntax error: stub" >&2\nexit 2\n' > "$STUB/badsh"; chmod +x "$STUB/badsh"
echo "07 07 * * * /usr/bin/true # mine" > "$CRONTAB_FILE"; before=$(cat "$CRONTAB_FILE")
rc=$( cd "$P" && HOME="$WORK/home" PATH="$BASEPATH" NIGHTLY_PARSE_SHELL="$STUB/badsh" /bin/bash scripts/install-nightly-maintenance.sh >"$WORK/o6" 2>&1; echo $? )
[ "$rc" = 1 ] && ok "AC6 a line that fails sh -n exits 1" || bad "AC6 an unparsable line gave exit $rc"
grep -q 'syntax error: stub' "$WORK/o6" && ok "AC6 the shell's error is printed" || bad "AC6 the parse error is hidden"
[ "$(cat "$CRONTAB_FILE")" = "$before" ] && ok "AC6 the crontab is unchanged" || bad "AC6 an unparsable line reached the crontab"

# AC7 — relative and empty PATH entries are dropped, duplicates appear once.
rm -f "$CRONTAB_FILE"
IPATH="$STUB::rel/bin:$TOOLS:.:/usr/bin:$TOOLS:/bin" inst "$P" >/dev/null
pathval=$(cat "$WORK/home/.claude/nightly/plain.path" 2>/dev/null)
[ "$pathval" = "$STUB:$TOOLS:/usr/bin:/bin" ] && ok "AC7 PATH is absolute, deduped, in order" \
  || bad "AC7 the captured PATH is '$pathval'"

# AC12 — BSD cron cuts a command at 999 characters; the line stays under it, a long root is refused.
L=$(ourline "$P")
[ "$(sed -E 's/^([^ ]+ ){5}//' <<< "$L" | awk '{ print length($0) }')" -le 999 ] \
  && ok "AC12 the command fits BSD cron's 999 characters" || bad "AC12 the command is longer than 999 characters"
seg=$(printf 'd%.0s' $(seq 1 200)); LONGP=$(mkproj "$seg/$seg/$seg"); before=$(cat "$CRONTAB_FILE")
[ -f "$LONGP/scripts/install-nightly-maintenance.sh" ] || bad "AC12 fixture missing -- the arm would be vacuous"
[ "$(rc_inst "$LONGP")" = 2 ] && ok "AC12 a root that pushes past 999 is refused" || bad "AC12 an over-long line was accepted"
grep -q '999' <<< "$(inst "$LONGP")" && ok "AC12 the refusal names the limit" || bad "AC12 the refusal does not say why"
[ "$(cat "$CRONTAB_FILE")" = "$before" ] && ok "AC12 the crontab is unchanged" || bad "AC12 the crontab changed"

# AC8 — the install message names what the captured PATH lacks.
OUT=$(IPATH="$STUB:$TOOLS:/usr/bin:/bin" inst "$P")
grep -Eq 'dotnet.*found' <<< "$OUT" && ok "AC8 a present tool is reported found" || bad "AC8 no report for dotnet"
grep -Eq 'docker.*(missing|not found)' <<< "$OUT" && ok "AC8 a missing tool is named" || bad "AC8 docker's absence is not reported"

# AC9 — --list flags a legacy line without PATH=.
printf '%s\n' "30 2 * * * cd /old && /bin/bash scripts/project-maintenance.sh --full > /x.log 2>&1 # claude-nightly-maintenance:/old" > "$CRONTAB_FILE"
inst "$P" >/dev/null
OUT=$(inst "$P" --list)
grep -Eqi "stale.*maintenance:/old\$" <<< "$OUT" && ok "AC9 a line without PATH= is flagged stale" \
  || bad "AC9 the legacy line is not flagged"
grep -Fx "$(ourline "$P")" <<< "$OUT" >/dev/null && ok "AC9 a fresh line is listed as is" || bad "AC9 a fresh line is not listed verbatim"
grep -qiF "stale (no PATH= -- runs under cron's bare PATH; reinstall from that project): $(ourline "$P")" <<< "$OUT" && bad "AC9 a fresh line is flagged stale" \
  || ok "AC9 a fresh line is not flagged"

# AC10 — re-install replaces, keeps others. AC11 — remove takes only ours.
echo "07 07 * * * /usr/bin/true # mine" > "$CRONTAB_FILE"
inst "$P" >/dev/null; inst "$P" >/dev/null
[ "$(grep -cF "claude-nightly-maintenance:$P" "$CRONTAB_FILE")" = 1 ] && ok "AC10 re-install leaves one line" \
  || bad "AC10 re-install stacked lines"
grep -q '# mine' "$CRONTAB_FILE" && ok "AC10 an unrelated line survives install" || bad "AC10 install ate another job"
inst "$P" --remove >/dev/null
grep -qF "claude-nightly-maintenance:$P" "$CRONTAB_FILE" && bad "AC11 remove left our line" || ok "AC11 remove takes our line"
grep -q '# mine' "$CRONTAB_FILE" && ok "AC11 remove keeps an unrelated line" || bad "AC11 remove ate another job"
[ -e "$WORK/home/.claude/nightly/plain.path" ] && bad "AC11 remove left the PATH file" || ok "AC11 remove takes the PATH file"

# AC13 — a deleted PATH file stops the run with a logged error, not a blind run.
inst "$P" >/dev/null; L=$(ourline "$P"); rm -f "$WORK/home/.claude/nightly/plain.path"
cronrun "$L" 2>/dev/null; LOG="$WORK/home/.claude/nightly/plain.log"
grep -q 'maintenance ran' "$LOG" && bad "AC13 maintenance ran without its PATH" || ok "AC13 no blind run without the PATH file"
grep -Eq '^claude-nightly: end exit=[1-9]' "$LOG" && ok "AC13 the missing PATH file is a logged failure" \
  || bad "AC13 the missing PATH file is not recorded"

# --dry-run also parse-checks, and changes nothing.
echo "07 07 * * * /usr/bin/true # mine" > "$CRONTAB_FILE"; before=$(cat "$CRONTAB_FILE")
rc=$( cd "$P" && HOME="$WORK/home" PATH="$BASEPATH" NIGHTLY_PARSE_SHELL="$STUB/badsh" /bin/bash scripts/install-nightly-maintenance.sh --dry-run >/dev/null 2>&1; echo $? )
[ "$rc" = 1 ] && ok "--dry-run refuses an unparsable line too" || bad "--dry-run gave exit $rc on an unparsable line"
[ "$(cat "$CRONTAB_FILE")" = "$before" ] && ok "--dry-run leaves the crontab alone" || bad "--dry-run wrote the crontab"

echo
echo "install-nightly-maintenance: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
