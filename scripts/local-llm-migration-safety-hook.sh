#!/usr/bin/env bash
# PostToolUse hook for Edit/Write on database migration files. The
# local LLM scans for production-unsafe patterns (NOT NULL without
# default on large tables, DROP COLUMN without rename, missing FK
# index, etc.) and reports findings with concrete remediations.
#
# Fits production deployments where migrations run under concurrent
# writes and a bad ALTER can lock a table for minutes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0
[ -r "$FILE" ] || exit 0

# Match common migration file conventions.
case "$FILE" in
  *.sql) ;;
  *Migrations/*.cs|*/Migrations/*.cs) ;;          # EF Core
  */migrations/*.sql|*/migrations/*.py) ;;        # Generic / Django / Alembic
  */db/migrate/*.rb) ;;                           # Rails
  *) exit 0 ;;
esac

SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$SIZE" -gt 100 ] || exit 0
[ "$SIZE" -lt 30000 ] || exit 0

CONTENT=$(head -c 12000 "$FILE")

SYSTEM='You are reviewing a database migration for production safety. Assume tables may be large and writes may be concurrent.

Scan for these critical anti-patterns:
- Adding a NOT NULL column without a default value (forces table rewrite or fails on existing rows)
- DROP COLUMN without a prior rename-and-deploy step (loses data on rollback)
- Renaming a column directly via DROP+ADD (loses data; should use rename-then-drop sequence over two deploys)
- Adding a foreign key without an index on the referencing column (slow joins and FK checks)
- ALTER TABLE without ONLINE/CONCURRENTLY (Postgres) or ALGORITHM=INPLACE LOCK=NONE (MySQL) on big tables
- Breaking type changes (e.g. VARCHAR(255) → VARCHAR(50), INT → SMALLINT) without rollback path
- DELETE or UPDATE without a WHERE clause
- CREATE INDEX without CONCURRENTLY on production-sized tables
- Missing default value forcing a full table rewrite on MySQL/SQLite
- Mixing schema and data changes in the same migration (hard to roll back)

For each issue found, output one line in this format:
- RISK: <one-line description, cite the table/column> | FIX: <concrete remediation>

If the migration looks safe, output exactly: SAFE
If you cannot determine safety because the table size or DB engine is unknown, output exactly: UNCERTAIN: <one-line reason>
No preamble, no markdown.'

REPORT=$(printf '%s' "$CONTENT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$REPORT" ] || exit 0
echo "$REPORT" | grep -qE '^[[:space:]]*SAFE[[:space:]]*$' && exit 0

jq -nc --arg f "$FILE" --arg r "$REPORT" \
  '{additionalContext: ("Local-LLM migration safety review on " + $f + ":\n" + $r + "\nVerify before applying to production.")}'
