#!/bin/bash
# PreToolUse hook (Write|Edit on docker-compose*.yml) — denies the operation if
# any service in the resulting compose file binds /mnt/nfs/<...> AND has
# replicas > 1. NFS+SQLite requires single-writer enforcement (replicas: 1 +
# update_config.order: stop-first + stop_grace_period: 30s); replicas > 1
# across spot workers on the same NFS-backed file is the textbook NFS+SQLite
# corruption case (see .claude/rules/sqlite.md and
# .claude/docs/spot-architecture.md Architecture A).
#
# The check is per-service: a stack with one NFS-mounting API at replicas: 1
# alongside stateless workers at replicas: 3 is fine — only services that
# combine BOTH an /mnt/nfs/ bind AND replicas > 1 trigger the deny.
#
# Returns:
#   no output  — allow (file is safe or not a compose file)
#   JSON deny  — block, with the offending service name(s) in the reason

set -u

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only inspect docker-compose*.yml files
if [ -z "$FILE" ] || ! echo "$FILE" | grep -qE 'docker-compose.*\.ya?ml$'; then
  exit 0
fi

# Reconstruct the resulting file content
case "$TOOL" in
  Write)
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
    ;;
  Edit)
    if [ ! -f "$FILE" ]; then exit 0; fi
    OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
    NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
    REPLACE_ALL=$(echo "$INPUT" | jq -r '.tool_input.replace_all // false' 2>/dev/null)
    CONTENT=$(OLD="$OLD" NEW="$NEW" FILE="$FILE" REPLACE_ALL="$REPLACE_ALL" python3 -c "
import os, sys
try:
    text = open(os.environ['FILE'], encoding='utf-8').read()
except Exception:
    sys.exit(0)
old = os.environ.get('OLD', '')
new = os.environ.get('NEW', '')
if not old:
    sys.exit(0)
if os.environ.get('REPLACE_ALL', 'false').lower() == 'true':
    out = text.replace(old, new)
else:
    out = text.replace(old, new, 1)
sys.stdout.write(out)
" 2>/dev/null) || exit 0
    ;;
  *)
    exit 0
    ;;
esac

if [ -z "$CONTENT" ]; then exit 0; fi

# Per-service inspection. Walk the YAML by indentation:
#   services:
#     api:           <-- 2-space indented service header
#       deploy:
#         replicas: 1
#       volumes:
#         - source: /mnt/nfs/...
# Within each service block, track whether we see a /mnt/nfs/ reference and
# the largest replicas count. Flag services where both conditions are true.
VIOLATIONS=$(printf '%s\n' "$CONTENT" | python3 -c '
import sys, re

text = sys.stdin.read()
lines = text.splitlines()

in_services = False
services_indent = None
service = None
service_indent = None
nfs = False
replicas = 1
violations = []

def maybe_flag():
    if service and nfs and replicas > 1:
        violations.append(f"{service} (replicas: {replicas}, mounts /mnt/nfs/)")

for raw in lines:
    # Strip comments (anything from an unquoted #)
    line = re.sub(r"(?<!\\)#.*$", "", raw)
    stripped = line.strip()
    if not stripped:
        continue

    indent = len(line) - len(line.lstrip(" "))

    # Top-level "services:" key
    m = re.match(r"^(\s*)services\s*:\s*$", line)
    if m:
        in_services = True
        services_indent = len(m.group(1))
        continue

    if in_services:
        # Left the services: block when indent goes back to <= services_indent on a key line
        if indent <= services_indent and re.match(r"^\s*[A-Za-z_][\w-]*\s*:", line):
            maybe_flag()
            in_services = False
            service = None
            continue

        # Service header line (one level deeper than services:)
        if service_indent is None or indent == service_indent:
            m = re.match(r"^(\s*)([A-Za-z_][\w.-]*)\s*:\s*$", line)
            if m and len(m.group(1)) > services_indent:
                # New service — flush previous
                maybe_flag()
                service = m.group(2)
                service_indent = len(m.group(1))
                nfs = False
                replicas = 1
                continue

        # Inside the current service body
        if service and indent > (service_indent or 0):
            if "/mnt/nfs/" in line:
                nfs = True
            m = re.search(r"\breplicas\s*:\s*([0-9]+)", line)
            if m:
                n = int(m.group(1))
                if n > replicas:
                    replicas = n

# Flush the last service
maybe_flag()

for v in violations:
    print(v)
' 2>/dev/null) || exit 0

if [ -n "$VIOLATIONS" ]; then
  REASON="NFS+SQLite single-writer rule violated. The following service(s) combine an /mnt/nfs/ volume bind with replicas > 1, which corrupts the SQLite file under concurrent access from multiple spot workers: $(echo "$VIOLATIONS" | tr '\n' ';' | sed 's/;$//; s/;/; /g'). Fix: set replicas: 1 (and update_config.order: stop-first + stop_grace_period: 30s) on the NFS-mounting service. If the workload genuinely needs multiple writers, switch to Architecture B (LiteFS) or C (Postgres) — see .claude/docs/spot-architecture.md. If you intentionally want to bypass this check (e.g. a read-only DB on the NFS share), use a sibling path that does not contain '/mnt/nfs/' or move the volume bind into a different service."
  jq -n --arg reason "$REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
fi

exit 0
