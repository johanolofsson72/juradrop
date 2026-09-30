#!/usr/bin/env bash
# test-stryker-guard.sh — the PreToolUse guard that refuses a Stryker run which would measure nothing
# (row 047), and the helper it shares with section 5 of project-maintenance.sh.
#
#   bash scripts/test-stryker-guard.sh
#
# Everything runs the real hook, fed the JSON Claude Code sends, and reads the verdict through
# hook-verdict.sh (spec 029): a deny without hookEventName is "dropped", never "deny". The live-process
# arms start real processes — a script named `dotnet`, looping until TERM, in a fixture directory — so
# what is under test is the process-table read, not a stub of it. Each is killed by its PID, never by a
# pattern (the 056 trap).
#
# Weighted toward what the guard must NOT do. It sits in front of every `dotnet` command Claude issues;
# a false deny there costs more than the defect it prevents, so half the arms prove it stays quiet or
# gets out of the way.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SELF_DIR/stryker-guard-hook.sh"
. "$SELF_DIR/hook-verdict.sh"
PASS=0; FAIL=0; PIDS=""
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t strykerguard)
WORK=$(cd "$WORK" && pwd -P)
cleanup() {
  for p in $PIDS; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  rm -rf "$WORK"
}
trap cleanup EXIT

PROJ="$WORK/proj"; OTHER="$WORK/other"; BIN="$WORK/bin"
mkdir -p "$PROJ/src/Services" "$OTHER" "$BIN"
printf 'class W {}\n' > "$PROJ/src/Services/WpqrService.cs"
printf '%s\n' '#!/bin/bash' "trap 'exit 0' TERM" 'while :; do sleep 0.2; done' > "$BIN/dotnet"
cp "$BIN/dotnet" "$BIN/dotnet-stryker"
chmod +x "$BIN/dotnet" "$BIN/dotnet-stryker"

# spawn <cwd> <program> [args...] — a live process with those arguments in that directory; echoes its PID
spawn() {
  local cwd=$1; shift
  ( cd "$cwd" && exec "$@" ) >/dev/null 2>&1 &
  printf '%s' "$!"
}
stop() { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }

# bounded <seconds> <command> — hook output, or HUNG after <seconds>. A stress arm that hangs the suite
# reports nothing; one that fails in bounded time reports what it found.
bounded() {
  local out="$WORK/bounded.$$" i=0
  hook "$2" > "$out" 2>/dev/null &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -gt $(($1 * 10)) ] && { kill "$pid" 2>/dev/null; pkill -P "$pid" 2>/dev/null; echo HUNG; return; }
    sleep 0.1
  done
  cat "$out"
}

# hook <command> [env...] — the hook's stdout for a Bash tool call
hook() {
  local cmd=$1; shift
  printf '%s' "$cmd" | jq -Rsc '{tool_name:"Bash", tool_input:{command:.}}' |
    env CLAUDE_PROJECT_DIR="$PROJ" "$@" bash "$HOOK"
}
expect() { # expect <name> <deny|none> <output> [substring the reason must carry]
  local v; v=$(hook_verdict "$3")
  if [ "$v" != "$2" ]; then
    bad "$1 — verdict $v, expected $2: $(printf '%s' "$3" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
    return
  fi
  if [ -n "${4:-}" ]; then
    if grep -Fq -e "$4" <<< "$(printf '%s' "$3" | jq -r '.hookSpecificOutput.permissionDecisionReason')"; then ok "$1"
    else bad "$1 — reason lacks '$4'"; fi
  else ok "$1"; fi
}

printf 'stryker-guard self-test (row 047)\n'

# ------------------------------------------------------------------ patterns (F184, F197, F185)
expect "G1 the F184 hyphen span is denied"            deny "$(hook "dotnet stryker -m '**/WpqrService.cs{845-1080}'")" "two dots"
expect "G2 a glob matching no .cs file is denied"     deny "$(hook "dotnet stryker -m '**/Nope.cs'")" "matches no .cs file"
expect "G3 a valid span is denied, as characters"     deny "$(hook "dotnet stryker -m '**/WpqrService.cs{840..1140}'")" "CHARACTER offsets"
expect "G4 and the deny names the span override"      deny "$(hook "dotnet stryker -m '**/WpqrService.cs{840..1140}'")" "STRYKER_SPANS_ARE_CHARACTERS=1"
expect "G5 the span override lets a valid span through" none "$(hook "STRYKER_SPANS_ARE_CHARACTERS=1 dotnet stryker -m '**/WpqrService.cs{840..1140}'")"
expect "G6 the span override does not pass a bad span" deny "$(hook "STRYKER_SPANS_ARE_CHARACTERS=1 dotnet stryker -m '**/WpqrService.cs{1-2}'")" "two dots"
expect "G7 --mutate= form is read"                    deny "$(hook "dotnet stryker --mutate='**/Nope.cs'")" "Nope.cs"
expect "G8 inside a compound command"                 deny "$(hook "cd src && timeout 600 dotnet stryker -m '**/Nope.cs'")" "Nope.cs"
expect "G9 dotnet tool run dotnet-stryker is Stryker" deny "$(hook "dotnet tool run dotnet-stryker -m '**/Nope.cs'")" "Nope.cs"
expect "G10 a good glob passes"                       none "$(hook "dotnet stryker -m '**/WpqrService.cs' -m 'Services/*.cs'")"
expect "G11 an exclude that excludes nothing passes"  none "$(hook "dotnet stryker -m '!**/*.Generated.cs'")"
expect "G12 a \$ pattern is not guessed at"           none "$(hook 'dotnet stryker -m "$SCOPE"')"
expect "G13 -m on another program is not a pattern"   none "$(hook "grep -m 5 dotnet-stryker build.log")"
expect "G14 echo of a Stryker line is not Stryker"    none "$(hook "echo dotnet stryker -m '**/Nope.cs'")"

# ------------------------------------------------------------------ run alone (F069)
P=$(spawn "$PROJ" "$BIN/dotnet-stryker" --config-file stryker-config.json); PIDS="$PIDS $P"; sleep 0.5
expect "G15 dotnet test beside a live Stryker is denied" deny "$(hook "dotnet test")" "pid $P"
expect "G16 and the reason names F069 and the override"  deny "$(hook "dotnet build -c Release")" "STRYKER_GUARD=off"
expect "G17 a second Stryker is denied too"            deny "$(hook "dotnet stryker")" "Stryker run"
expect "G18 a non-dotnet command still passes"         none "$(hook "git status")"
expect "G19 STRYKER_GUARD=off in the command passes"   none "$(hook "STRYKER_GUARD=off dotnet test")"
expect "G20 STRYKER_GUARD=off in the environment passes" none "$(hook "dotnet test" STRYKER_GUARD=off)"
stop "$P"
expect "G21 once it has stopped, dotnet test passes"   none "$(hook "dotnet test")"

P=$(spawn "$PROJ" "$BIN/dotnet" build); PIDS="$PIDS $P"; sleep 0.5
expect "G22 Stryker beside a live dotnet build is denied" deny "$(hook "dotnet stryker")" "pid $P"
expect "G23 the project runner beside it is denied"    deny "$(hook "bash scripts/run-mutation-gate.sh")" "pid $P"
expect "G24 a build beside a build is not this guard's" none "$(hook "dotnet test")"
stop "$P"

P=$(spawn "$PROJ" "$BIN/dotnet" /usr/share/dotnet/sdk/MSBuild.dll -nodemode:1 -nodeReuse:true); PIDS="$PIDS $P"; sleep 0.5
expect "G25 an MSBuild node-reuse worker is not a build" none "$(hook "dotnet stryker")"
stop "$P"

P=$(spawn "$OTHER" "$BIN/dotnet-stryker"); PIDS="$PIDS $P"; sleep 0.5
expect "G26 Stryker in another project does not stop this one" none "$(hook "dotnet test")"
stop "$P"

# An ancestor is waiting on the helper, so it is never a concurrent build: the helper started from a
# `dotnet test` (a test that shells out, or `dotnet test && ...` in one wrapper) must not find its parent.
ANC="$WORK/anc"; mkdir -p "$ANC"
printf '%s\n' '#!/bin/bash' 'python3 "$STRYKER_HELPER" live "$STRYKER_ROOT"' > "$ANC/dotnet"; chmod +x "$ANC/dotnet"
OUT=$(cd "$PROJ" && STRYKER_HELPER="$SELF_DIR/stryker_guard.py" STRYKER_ROOT="$PROJ" "$ANC/dotnet" test)
if [ -z "$OUT" ]; then ok "G34 its own ancestor dotnet test is not a live build"; else bad "G34 ancestor read as live: $OUT"; fi

# ------------------------------------------------------------------ adversarial review (row 047)
# Each arm is one false deny the review found in the first draft, which matched the WORDS anywhere in a
# process's arguments. A build is now an executable named dotnet whose first argument is a verb.
cp "$BIN/dotnet" "$BIN/git"; chmod +x "$BIN/git"
P=$(spawn "$PROJ" "$BIN/git" commit -m fix dotnet test flake); PIDS="$PIDS $P"; sleep 0.5
expect "G35 'dotnet test' in another program's args is not a build" none "$(hook "dotnet stryker")"
stop "$P"
P=$(spawn "$PROJ" "$BIN/dotnet" test --no-build); PIDS="$PIDS $P"; sleep 0.5
expect "G36 a live dotnet test --no-build builds nothing"  none "$(hook "dotnet stryker")"
stop "$P"
P=$(spawn "$PROJ" "$BIN/dotnet" build-server shutdown); PIDS="$PIDS $P"; sleep 0.5
expect "G37 dotnet build-server is not dotnet build"       none "$(hook "dotnet stryker")"
stop "$P"
P=$(spawn "$PROJ" "$BIN/dotnet" run --project Web); PIDS="$PIDS $P"; sleep 0.5
expect "G38 a long-lived dotnet run does not block Stryker" none "$(hook "dotnet stryker")"
stop "$P"
P=$(spawn "$PROJ" "$BIN/dotnet-stryker"); PIDS="$PIDS $P"; sleep 0.5
expect "G39 but dotnet run beside Stryker is denied (it builds)" deny "$(hook "dotnet run --project Web")" "pid $P"
expect "G40 dotnet test --no-build beside Stryker passes"  none "$(hook "dotnet test --no-build")"
expect "G41 a wrapper with options is seen through"        deny "$(hook "nice -n 10 dotnet test")" "pid $P"
expect "G42 bash -x on the runner is the runner"           deny "$(hook "bash -x scripts/run-mutation-gate.sh")" "pid $P"
stop "$P"
HD=$(printf '%s\n' "cat > notes.md <<'EOF'" "dotnet stryker -m '**/WpqrService.cs{845-1080}'" "EOF")
expect "G43 a heredoc body is data, not a command"         none "$(hook "$HD")"
expect "G44 glob case does not invent a no-match"          none "$(hook "dotnet stryker -m '**/wpqrservice.cs'")"
DEEP=$(python3 -c 'print("**/" * 150 + "zz.cs")')
mkdir -p "$PROJ/$(python3 -c 'print("/".join("d%d" % i for i in range(25)))')"
touch "$PROJ/$(python3 -c 'print("/".join("d%d" % i for i in range(25)))')/Deep.cs"
T0=$(date +%s); OUT=$(bounded 8 "dotnet stryker -m '$DEEP'"); T1=$(date +%s)
if [ "$(hook_verdict "$OUT")" = deny ] && [ $((T1 - T0)) -le 5 ]; then ok "G45 150 x '**/' is collapsed: answered in $((T1 - T0))s"
else bad "G45 deep glob: verdict $(hook_verdict "$OUT") in $((T1 - T0))s"; fi
BRACES=$(python3 -c 'print("x" + "{}" * 20000)')
T0=$(date +%s); OUT=$(bounded 8 "dotnet stryker -m '$BRACES'"); T1=$(date +%s)
if [ "$(hook_verdict "$OUT")" = none ] && [ $((T1 - T0)) -le 5 ]; then ok "G46 an over-long pattern is not compiled: answered in $((T1 - T0))s"
else bad "G46 brace flood: verdict $(hook_verdict "$OUT") in $((T1 - T0))s"; fi

# ------------------------------------------------------------------ fails open
OUT=$(printf 'not json' | CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK"); RC=$?
if [ "$(hook_verdict "$OUT")" = none ] && [ "$RC" -eq 0 ]; then ok "G27 input that is not JSON passes, exit 0"; else bad "G27 not-JSON input: '$OUT' rc=$RC"; fi
expect "G28 unbalanced quoting passes"                 none "$(hook "dotnet stryker -m '**/Nope.cs")"
NOPY="$WORK/nopy"; mkdir -p "$NOPY"
for t in bash cat jq dirname; do ln -s "$(command -v "$t")" "$NOPY/$t"; done
expect "G29 no python3 passes"                         none "$(hook "dotnet stryker -m '**/Nope.cs'" PATH="$NOPY")"
OUT=$(printf '%s' '{"tool_input":{"command":"dotnet stryker -m x"}}' | env -u CLAUDE_PROJECT_DIR bash "$HOOK")
if [ "$(hook_verdict "$OUT")" = none ]; then ok "G30 no project dir and no cwd passes"; else bad "G30 no root: '$OUT'"; fi

# ------------------------------------------------------------------ stress
BIG=$(python3 -c 'print("echo " + "x" * 1000000 + " && dotnet test")')
T0=$(date +%s); OUT=$(hook "$BIG"); T1=$(date +%s)
if [ "$(hook_verdict "$OUT")" = none ] && [ $((T1 - T0)) -le 10 ]; then ok "G31 a 1 MB command is read in $((T1 - T0))s and passes"
else bad "G31 1 MB command: verdict $(hook_verdict "$OUT") in $((T1 - T0))s"; fi
MANY=""; for i in 1 2 3 4 5 6 7 8 9 10; do P=$(spawn "$OTHER" "$BIN/dotnet" test); MANY="$MANY $P"; done
PIDS="$PIDS $MANY"; sleep 0.5
T0=$(date +%s); OUT=$(hook "dotnet stryker"); T1=$(date +%s)
if [ "$(hook_verdict "$OUT")" = none ] && [ $((T1 - T0)) -le 10 ]; then ok "G32 ten builds elsewhere: read in $((T1 - T0))s, none are this project's"
else bad "G32 ten builds elsewhere: verdict $(hook_verdict "$OUT") in $((T1 - T0))s"; fi
for P in $MANY; do stop "$P"; done
P=$(spawn "$PROJ" "$BIN/dotnet-stryker"); PIDS="$PIDS $P"; sleep 0.5
T0=$(date +%s); OUT=$(hook "$BIG"); T1=$(date +%s)
if [ "$(hook_verdict "$OUT")" = deny ] && [ $((T1 - T0)) -le 10 ]; then ok "G33 a 1 MB command beside a live Stryker is still denied, in $((T1 - T0))s"
else bad "G33 1 MB beside Stryker: verdict $(hook_verdict "$OUT") in $((T1 - T0))s"; fi
stop "$P"

# ------------------------------------------------------------------ sweep (row 053)
# An abandoned StrykerJS sandbox is removed when the next run starts, and only then; everything that is
# not plainly an abandoned sandbox is kept and said. Weighted like the rest of this file toward what it
# must NOT do: deleting is the destructive direction.
swfix() { # swfix — a fresh project root with one abandoned sandbox at .stryker-tmp; echoes its path
  local d; d=$(mktemp -d "$WORK/sw.XXXXXX")   # not a counter: $(swfix) runs in a subshell
  mkdir -p "$d/.stryker-tmp/sandbox-a1/src"; printf '{}\n' > "$d/.stryker-tmp/sandbox-a1/package.json"
  printf '%s' "$d"
}
sweep() { python3 "$SELF_DIR/stryker_guard.py" sweep "$1"; }
gone() { [ ! -e "$1" ] && [ ! -L "$1" ]; }
ctx() { printf '%s' "$1" | jq -r 'select(.hookSpecificOutput.hookEventName == "PreToolUse") | .hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

D=$(swfix); OUT=$(sweep "$D")
if gone "$D/.stryker-tmp" && grep -q "^removed	.stryker-tmp	" <<< "$OUT"; then ok "S1 an abandoned sandbox is removed and said"; else bad "S1 '$OUT'"; fi
D=$(swfix); mv "$D/.stryker-tmp" "$D/x"; mkdir -p "$D/client"; mv "$D/x" "$D/client/.stryker-tmp"; OUT=$(sweep "$D")
if gone "$D/client/.stryker-tmp" && grep -q "client/.stryker-tmp" <<< "$OUT"; then ok "S2 a nested sandbox is removed"; else bad "S2 '$OUT'"; fi
D=$(swfix); mkdir -p "$D/.stryker-tmp/backup-9f/src"; printf 'orig\n' > "$D/.stryker-tmp/backup-9f/src/a.js"; OUT=$(sweep "$D")
if [ -f "$D/.stryker-tmp/backup-9f/src/a.js" ] && grep -q "^backup	" <<< "$OUT"; then ok "S3 an in-place backup is never removed"; else bad "S3 '$OUT'"; fi
expect "S4 and the next StrykerJS run is denied, naming it" deny "$(hook "npx stryker run" CLAUDE_PROJECT_DIR="$D")" "backup-9f"
D=$(swfix); printf 'x\n' > "$D/.stryker-tmp/notes.txt"; OUT=$(sweep "$D")
if [ -d "$D/.stryker-tmp/sandbox-a1" ] && grep -q "^kept	.*notes.txt" <<< "$OUT"; then ok "S5 an unexpected entry keeps the directory, named"; else bad "S5 '$OUT'"; fi
D=$(swfix); mkdir -p "$D/.stryker-tmp/notes"; OUT=$(sweep "$D")
if [ -d "$D/.stryker-tmp/notes" ] && grep -q "^kept	" <<< "$OUT"; then ok "S6 an unexpected directory keeps it too"; else bad "S6 '$OUT'"; fi
D=$(swfix); printf '{ "cleanTempDir": false }\n' > "$D/stryker.conf.json"; OUT=$(sweep "$D")
if [ -d "$D/.stryker-tmp/sandbox-a1" ] && grep -q "cleanTempDir" <<< "$OUT"; then ok "S7 cleanTempDir: false keeps it"; else bad "S7 '$OUT'"; fi
D=$(swfix); printf 'export default { cleanTempDir: false };\n' > "$D/stryker.config.mjs"; OUT=$(sweep "$D")
if [ -d "$D/.stryker-tmp/sandbox-a1" ]; then ok "S8 cleanTempDir: false in a .mjs config keeps it"; else bad "S8 '$OUT'"; fi
D=$(swfix); mkdir -p "$D/real/sandbox-z"; rm -rf "$D/.stryker-tmp"; ln -s "$D/real" "$D/.stryker-tmp"; OUT=$(sweep "$D")
if [ -d "$D/real/sandbox-z" ] && [ -L "$D/.stryker-tmp" ] && grep -q "^kept	.*symlink" <<< "$OUT"; then ok "S9 a symlink is kept, target untouched"; else bad "S9 '$OUT'"; fi
D=$(swfix); ( cd "$D" && git init -q && git add -f .stryker-tmp && git -c user.email=t@t -c user.name=t commit -qm t ) >/dev/null 2>&1; OUT=$(sweep "$D")
if [ -d "$D/.stryker-tmp/sandbox-a1" ] && grep -q "git tracks" <<< "$OUT"; then ok "S10 git-tracked content is kept"; else bad "S10 '$OUT'"; fi
D=$(swfix); mv "$D/.stryker-tmp" "$D/stryker-tmp"; printf '{ "tempDirName": "stryker-tmp" }\n' > "$D/stryker.conf.json"; OUT=$(sweep "$D")
if gone "$D/stryker-tmp"; then ok "S11 a configured tempDirName is swept"; else bad "S11 '$OUT'"; fi
D=$(swfix); mkdir -p "$D/web/sandbox-q"; printf '{ "tempDirName": "../web" }\n' > "$D/sub.json"; mkdir -p "$D/pkg"
printf '{ "tempDirName": "../web" }\n' > "$D/pkg/stryker.conf.json"; printf '{ "tempDirName": "." }\n' > "$D/stryker.conf.json"; OUT=$(sweep "$D")
if [ -d "$D/web/sandbox-q" ] && [ -f "$D/stryker.conf.json" ]; then ok "S12 a tempDirName of ../x or . is ignored"; else bad "S12 '$OUT'"; fi
D="$WORK/sw-empty"; mkdir -p "$D/src"; OUT=$(sweep "$D")
if [ -z "$OUT" ]; then ok "S13 no temp directory: no output"; else bad "S13 '$OUT'"; fi
D=$(swfix); rm -rf "$D/.stryker-tmp/sandbox-a1"; OUT=$(sweep "$D")
if gone "$D/.stryker-tmp"; then ok "S14 an empty temp directory is removed"; else bad "S14 '$OUT'"; fi
D=$(swfix); mkdir -p "$D/node_modules/pkg/.stryker-tmp/sandbox-n"; OUT=$(sweep "$D")
if [ -d "$D/node_modules/pkg/.stryker-tmp/sandbox-n" ]; then ok "S15 node_modules is not walked"; else bad "S15 '$OUT'"; fi

# live runs: a node process running StrykerJS, a Stryker.NET, in this project or another
cp "$BIN/dotnet" "$BIN/node"; chmod +x "$BIN/node"
D=$(swfix); P=$(spawn "$D" "$BIN/node" "$D/node_modules/@stryker-mutator/core/bin/stryker.js" run); PIDS="$PIDS $P"; sleep 0.5
OUT=$(sweep "$D")
if [ -d "$D/.stryker-tmp/sandbox-a1" ] && grep -q "pid $P" <<< "$OUT"; then ok "S16 a live StrykerJS run keeps it, naming the pid"; else bad "S16 '$OUT'"; fi
expect "S17 a live StrykerJS does not deny dotnet build (F069 stays .NET)" none "$(hook "dotnet build" CLAUDE_PROJECT_DIR="$D")"
stop "$P"
D=$(swfix); P=$(spawn "$D" "$BIN/dotnet-stryker"); PIDS="$PIDS $P"; sleep 0.5; OUT=$(sweep "$D")
if [ -d "$D/.stryker-tmp/sandbox-a1" ]; then ok "S18 a live Stryker.NET keeps it"; else bad "S18 '$OUT'"; fi
stop "$P"
D=$(swfix); P=$(spawn "$OTHER" "$BIN/node" "$OTHER/node_modules/.bin/stryker" run); PIDS="$PIDS $P"; sleep 0.5; OUT=$(sweep "$D")
if gone "$D/.stryker-tmp"; then ok "S19 a StrykerJS run in another project does not keep it"; else bad "S19 '$OUT'"; fi
stop "$P"
D=$(swfix); NOPS="$WORK/nops"; mkdir -p "$NOPS"; for t in python3 git; do ln -sf "$(command -v "$t")" "$NOPS/$t"; done
OUT=$(PATH="$NOPS" sweep "$D")
if [ -d "$D/.stryker-tmp/sandbox-a1" ] && grep -q "^kept	" <<< "$OUT"; then ok "S20 no ps: blind keeps"; else bad "S20 '$OUT'"; fi

# the hook: which commands start a run, and how the sweep reaches the model
for c in "npx stryker run" "pnpm exec stryker run" "yarn stryker run" "bunx stryker run" \
         "node node_modules/.bin/stryker run" "./node_modules/.bin/stryker run --concurrency 2" \
         "npx --yes @stryker-mutator/core run" "cd client && npx stryker run" "dotnet stryker" \
         "npm exec -- stryker run"; do
  D=$(swfix); OUT=$(hook "$c" CLAUDE_PROJECT_DIR="$D")
  if gone "$D/.stryker-tmp" && [ "$(hook_verdict "$OUT")" = none ] && grep -q "swept" <<< "$(ctx "$OUT")"; then ok "S21 '$c' sweeps, said as additionalContext"
  else bad "S21 '$c': verdict $(hook_verdict "$OUT"), ctx '$(ctx "$OUT")', left: $(ls "$D/.stryker-tmp" 2>/dev/null)"; fi
done
for c in "npx stryker init" "echo stryker run" "grep -r stryker ." "git commit -m 'stryker run fix'" "npx stryker --version" \
         "cat > n.md <<'EOF'
npx stryker run
EOF"; do
  D=$(swfix); OUT=$(hook "$c" CLAUDE_PROJECT_DIR="$D")
  if [ -d "$D/.stryker-tmp/sandbox-a1" ] && [ -z "$OUT" ]; then ok "S22 '${c%%$'\n'*}' does not sweep"; else bad "S22 '$c' swept or spoke: '$OUT'"; fi
done
D=$(swfix); OUT=$(hook "npx stryker run" CLAUDE_PROJECT_DIR="$D" STRYKER_GUARD=off)
if [ -d "$D/.stryker-tmp/sandbox-a1" ]; then ok "S23 STRYKER_GUARD=off does not sweep"; else bad "S23 swept under off"; fi
D="$WORK/sw-quiet"; mkdir -p "$D"; OUT=$(hook "npx stryker run" CLAUDE_PROJECT_DIR="$D")
if [ -z "$OUT" ]; then ok "S24 nothing to sweep: the hook says nothing"; else bad "S24 '$OUT'"; fi
D=$(swfix); printf 'x\n' > "$D/.stryker-tmp/notes.txt"; OUT=$(hook "npx stryker run" CLAUDE_PROJECT_DIR="$D")
if [ "$(hook_verdict "$OUT")" = none ] && grep -q "notes.txt" <<< "$(ctx "$OUT")"; then ok "S25 a kept directory is said, the run allowed"; else bad "S25 '$OUT'"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
