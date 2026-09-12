#!/bin/bash
# test-register-similarity.sh — the duplicate-row detector against known answers.
#
# Two of these are regressions from the day it was written: paraphrase-multilingual
# returns HTTP 500 rather than truncating past its 128-token window, and the
# by-design `H1 — integration-hardening` checkpoint row matched itself across every
# project and produced 208 of 216 cross-project pairs.
#
# Needs a reachable Ollama with the embedding model. Skips (exit 0) without one --
# a test that fails because a service is off teaches people to ignore it.
set -uo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUT="$SCRIPT_DIR/register-similarity.sh"
MODEL="${REGISTER_SIMILARITY_MODEL:-paraphrase-multilingual}"
HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

if ! curl -s -o /dev/null -m 3 "$HOST/api/tags" || ! grep -q "\"$MODEL" <<< "$(curl -s -m 3 "$HOST/api/tags")"; then
  echo "register-similarity: SKIPPED — no Ollama at $HOST with model '$MODEL'."
  exit 0
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

mk() { mkdir -p "$1/specs"; { echo "# Spec register"; echo; echo "## Specs"; echo; cat; } > "$1/specs/INDEX.md"; }

# 1. Two rows that say the same thing in different words are found.
#
# This is agentcrm's real S8/S13 pair verbatim, not a paraphrase written to pass:
# they were identified by hand as one defect described twice, and the detector
# scores them 0.870. A hand-written imitation of them scored 0.718 -- close enough
# to look like a fair fixture and far enough to make the test lie about the
# threshold, so the real text is the fixture. Note it is Swedish: a cross-language
# corpus is the normal case here, which is why the model is multilingual.
mk "$TMP/dup" <<'EOF'
- [ ] 001 — archiver-rejects-our-row-ids — spec-only track — `archive-completed-rows.sh` vägrar på första S-raden, så **inget** har arkiverats: 29 bockade rader inline, 7 i `INDEX.completed.md`. `validate-register-ids.sh` godkänner samma 49 id. Diagnos: `specs/INDEX.pending.md`
- [ ] 002 — row-archiver-inert-on-s-rows — spec-only track — `archive-completed-rows.sh` vägrar hela registret på id `S1`; `validate-register-ids.sh` godtar det. Tio rader ligger över budget. Diagnos: `specs/INDEX.pending.md`
- [ ] 003 — seasonal-suitability — full track — post-route climatology: which seasons and departure windows suit a given sailing route.
EOF
OUT=$(bash "$SUT" --dir "$TMP/dup" --threshold 0.82 2>&1)
grep -q '001' <<<"$OUT" && grep -q '002' <<<"$OUT" \
  && ok "finds two rows that say the same thing in different words" \
  || bad "missed the duplicate pair: $(head -3 <<<"$OUT")"
grep -q '003' <<<"$OUT" && bad "matched an unrelated row (003)" || ok "leaves the unrelated row alone"

# 2. Unrelated rows produce nothing, and the exit code says so.
mk "$TMP/clean" <<'EOF'
- [ ] 001 — stripe-subscription — full track — per-org monthly subscription billing.
- [ ] 002 — gpx-export — full track — GPX and PDF float plan export with a source list.
- [ ] 003 — dkim-alignment — full track — tie the DKIM verdict to the sender.
EOF
bash "$SUT" --dir "$TMP/clean" --threshold 0.80 >/dev/null 2>&1
[ "$?" = 0 ] && ok "unrelated rows: exit 0" || bad "unrelated rows did not exit 0"

# 3. The by-design checkpoint row must not match itself across projects. This is
#    what buried the real signal on the first full run.
for p in a b c d; do
  mk "$TMP/boiler_$p" <<EOF
- [ ] 001 — thing-$p — full track — a feature unique to project $p, sharing no words with the others.
- [ ] H1 — integration-hardening — checkpoint — full-system regression + security sweep after spec 005.
EOF
done
OUT=$(bash "$SUT" --dir "$TMP/boiler_a" --dir "$TMP/boiler_b" --dir "$TMP/boiler_c" --dir "$TMP/boiler_d" --threshold 0.80 2>&1)
grep -q 'integration-hardening' <<<"$OUT" \
  && bad "the checkpoint row is still reported across projects" \
  || ok "the by-design checkpoint row is excluded"

# 4. A row far past the model's token window must not sink the pass. Bare
#    paraphrase-multilingual 500s instead of truncating; halve-and-retry covers it.
LONG=$(python3 -c "print('en mycket lång diagnos med kodidentifierare scripts/validate-scenario-traceability.sh och skiljetecken, ' * 40)")
mk "$TMP/long" <<EOF
- [ ] 001 — long-row — spec-only track — $LONG
- [ ] 002 — long-row-twin — spec-only track — $LONG
- [ ] 003 — unrelated — full track — stripe subscription billing per organisation.
EOF
OUT=$(bash "$SUT" --dir "$TMP/long" --threshold 0.80 2>&1)
grep -qi 'could not be embedded' <<<"$OUT" \
  && bad "a very long row was dropped instead of retried shorter" \
  || ok "a row past the token window is retried shorter, not dropped"

# 5. Query mode answers "would this be a duplicate?" before the row is written.
#    No --threshold here on purpose: the point is that the DEFAULT for query mode
#    is calibrated separately from corpus mode. A short query against a long row
#    scores 0.54 where two long rows score 0.87, so a shared default would make
#    this mode answer "new work" to everything.
OUT=$(bash "$SUT" --dir "$TMP/dup" --text "arkiveraren vägrar hela registret och inget blir arkiverat" 2>&1)
grep -qE '00[12]' <<<"$OUT" && ok "query mode finds the existing row" || bad "query mode found nothing: $(head -3 <<<"$OUT")"
OUT=$(bash "$SUT" --dir "$TMP/dup" --text "add a Stripe subscription checkout flow" 2>&1)
grep -q 'looks like new work' <<<"$OUT" && ok "query mode says new work is new" || bad "query mode did not clear genuinely new work"

# 6. A missing model is a usage error, not a silent clean report.
REGISTER_SIMILARITY_MODEL=no-such-model-xyz bash "$SUT" --dir "$TMP/dup" >/dev/null 2>&1
[ "$?" = 2 ] && ok "a missing model exits 2, not 0" || bad "a missing model did not exit 2"

echo "register-similarity: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
