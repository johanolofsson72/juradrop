#!/bin/sh
# test-scenario-map-fixtures.sh — throwaway project fixtures for the 007bl harnesses.
#
# WHY: the three harnesses added by spec 007bl (layout, reminder, canary) all need the same
# thing: a small directory that looks enough like a project for a hook to run against, in each
# of the two map layouts. Building that inline in each harness would mean three slightly
# different notions of "a project", and the first time one drifted the harness would be testing
# its own fixture rather than the hook.
#
# The fixtures are deliberately minimal but not degenerate: each carries a language marker
# (package.json), a .git directory and a specs/INDEX.md, because every hook under test walks up
# to a project root, checks for a language marker, and reads the register. A fixture missing any
# of those makes the hooks exit silently, and a harness built on it would pass no matter what
# the hook did — the most expensive kind of green.
#
# SOURCE IT; it defines functions and runs nothing:
#   . "$(dirname "$0")/test-scenario-map-fixtures.sh"
#   root=$(make_single_file_fixture)
#   root=$(make_split_fixture)
#   fixture_cleanup            # removes everything made this run
#
# Each maker echoes the fixture root. Fixtures live under one temp dir per process so a single
# cleanup call takes them all, including after a failure.
#
# FIXTURE IDS ARE DERIVED, NEVER WRITTEN (register row H7bd). The ids in the maps below come from
# scenario-probe-ids.sh, which hands back ids no row in the project's real map owns; the heredoc
# bodies carry @IDn@ placeholders substituted on the way to disk. Spelling real ids here — which is
# what this file did until H7bd — is a false binding, not a cosmetic choice: the id-accounting gate
# scans scripts/, cannot tell a fixture from an assertion, and counts a probe map for a hook test as
# proof that a real scenario is tested. Measured in consultpilot, four real ids were bound that way
# from this file alone. scenario-probe-ids.sh's header carries the two alternatives and why neither
# works for a fixture that must be parsed by an SC--anchored row extractor.

FIXTURE_TMPDIR="${FIXTURE_TMPDIR:-}"

_FIXTURE_HERE=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)
# shellcheck source=scripts/scenario-probe-ids.sh
. "$_FIXTURE_HERE/scenario-probe-ids.sh"

# Derived once, at source time, so every maker in one run agrees about which ids it is using and a
# consumer that builds both layouts gets the same four ids in both. The template ships no scenario
# map; with none, every id is free, which is the right answer for a tree that owns no scenarios.
_FIXTURE_MAP=$(git rev-parse --show-toplevel 2>/dev/null)/specs/SCENARIOS.md
_FIXTURE_IDS=$(scenario_probe_checked 4 test-scenario-map-fixtures "$_FIXTURE_MAP") \
  || return 1 2>/dev/null || exit 1

# Read into variables WITHOUT `set --`. This file is SOURCED, so `set --` would silently replace the
# positional parameters of whatever sourced it — a library that eats its caller's arguments is a
# surprise nobody looks for, and it is free to avoid.
FIXTURE_ID1=$(printf '%s\n' "$_FIXTURE_IDS" | sed -n 1p)
FIXTURE_ID2=$(printf '%s\n' "$_FIXTURE_IDS" | sed -n 2p)
FIXTURE_ID3=$(printf '%s\n' "$_FIXTURE_IDS" | sed -n 3p)
FIXTURE_ID4=$(printf '%s\n' "$_FIXTURE_IDS" | sed -n 4p)
_FIXTURE_SUBST=$(scenario_probe_sed_script "$FIXTURE_ID1" "$FIXTURE_ID2" "$FIXTURE_ID3" "$FIXTURE_ID4")

_fixture_tmpdir() {
    if [ -z "$FIXTURE_TMPDIR" ]; then
        FIXTURE_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/scenmap-fixtures.XXXXXX")
        export FIXTURE_TMPDIR
    fi
    echo "$FIXTURE_TMPDIR"
}

fixture_cleanup() {
    [ -n "$FIXTURE_TMPDIR" ] && [ -d "$FIXTURE_TMPDIR" ] && rm -rf "$FIXTURE_TMPDIR"
    FIXTURE_TMPDIR=""
    return 0
}

# _fixture_skeleton <root> — the parts every fixture shares.
_fixture_skeleton() {
    _fs_root="$1"
    mkdir -p "$_fs_root/specs" "$_fs_root/.git" "$_fs_root/scripts"

    # The language marker. Without it every hook under test exits silently, per its own
    # template/scratch-repo guard, and the harness would prove nothing.
    printf '{ "name": "fixture", "private": true }\n' > "$_fs_root/package.json"

    cat > "$_fs_root/specs/INDEX.md" <<'FIXTURE_INDEX'
# Spec register

## Specs

- [x] 001 — alpha — full track — a finished feature
- [/] 002 — beta — full track — the in-progress row
- [ ] 003 — gamma — full track — the next row

## Register history

- 2026-08-26 — fixture register, not a real project
FIXTURE_INDEX
    unset _fs_root
}

# _fixture_index_head <root> — the part of the map that is identical in both layouts.
_fixture_index_head() {
    cat > "$1/specs/SCENARIOS.md" <<'FIXTURE_MAP_HEAD'
# Scenario map

Status:  ☐ mapped  ·  ◐ tested  ·  ✓ validated

## Use case overview (who can do what)

```mermaid
flowchart LR
  user([User]) --> uc1([Do the alpha thing])
  user --> uc2([Do the beta thing])
```

## Actor: User

FIXTURE_MAP_HEAD
}

_fixture_history() {
    cat >> "$1/specs/SCENARIOS.md" <<'FIXTURE_MAP_TAIL'

## Scenario history

- 2026-08-26 — fixture map, not a real project
FIXTURE_MAP_TAIL
}

# make_single_file_fixture — the pre-007bl shape: one map file, no specs/scenarios/ at all.
# This is the fixture that matters most. It is the one asserting that 41 projects which never
# split see byte-identical behaviour from every script 007bl touched.
make_single_file_fixture() {
    _sf_root="$(_fixture_tmpdir)/single-$$-${RANDOM:-0}"
    while [ -e "$_sf_root" ]; do _sf_root="${_sf_root}x"; done
    mkdir -p "$_sf_root"

    _fixture_skeleton "$_sf_root"
    _fixture_index_head "$_sf_root"

    sed "$_FIXTURE_SUBST" >> "$_sf_root/specs/SCENARIOS.md" <<'FIXTURE_SINGLE'
### Feature: Alpha   (spec: 001-alpha)

The alpha feature, with a form the user can submit.

| ID     | Type  | Scenario              | Expected outcome            | Status |
|--------|-------|-----------------------|-----------------------------|--------|
| @ID1@ | happy | Submit the alpha form | Saved and listed            | ✓      |
| @ID2@ | error | Submit it empty       | Field error, input retained | ◐      |

#### The alpha detail   (spec: 001a-alpha-detail)

The nested sub-feature.

| ID     | Type  | Scenario                | Expected outcome     | Status |
|--------|-------|-------------------------|----------------------|--------|
| @ID3@ | happy | Open the detail drawer  | The drawer opens     | ✓      |

### Feature: Beta   (spec: 002-beta)

The beta feature.

| ID     | Type  | Scenario           | Expected outcome | Status |
|--------|-------|--------------------|------------------|--------|
| @ID4@ | happy | Click the beta tab | The tab opens    | ☐      |
FIXTURE_SINGLE

    _fixture_history "$_sf_root"
    echo "$_sf_root"
    unset _sf_root
}

# make_split_fixture — the post-007bl shape: index plus per-feature files.
#
# THE CASE THAT MATTERS is 001a-alpha-detail: a nested sub-feature whose slug appears ONLY
# inside specs/scenarios/001-alpha.md and NOWHERE in the index. It models msroute's real
# 007c-jwks-port-lifetime, a #### block living inside its parent's file whose slug the index
# never names. Pre-007bl the reminder hook greps the index alone, so it reports a scenario gap
# for a feature that is completely mapped.
#
# The other two slugs (001-alpha, 002-beta) DO appear in the index, because an index row names
# its feature's spec and links a file whose name embeds the slug. That makes them useless as a
# regression test for the multi-file search — they would pass with the old index-only grep. A
# fixture where every case passes both before and after the change tests nothing, so the
# nested slug carries the assertion and the other two guard against over-suppression.
make_split_fixture() {
    _sp_root="$(_fixture_tmpdir)/split-$$-${RANDOM:-0}"
    while [ -e "$_sp_root" ]; do _sp_root="${_sp_root}x"; done
    mkdir -p "$_sp_root/specs/scenarios"

    _fixture_skeleton "$_sp_root"
    _fixture_index_head "$_sp_root"

    sed "$_FIXTURE_SUBST" >> "$_sp_root/specs/SCENARIOS.md" <<'FIXTURE_SPLIT_INDEX'
| Feature | Spec | Scenarios | Status |
|---------|------|-----------|--------|
| Alpha   | 001-alpha | [@ID1@..@ID3@](scenarios/001-alpha.md) | 2 ✓, 1 ◐ |
| Beta    | 002-beta  | [@ID4@](scenarios/002-beta.md)       | 1 ☐       |
FIXTURE_SPLIT_INDEX

    _fixture_history "$_sp_root"

    sed "$_FIXTURE_SUBST" > "$_sp_root/specs/scenarios/001-alpha.md" <<'FIXTURE_ALPHA'
[← Scenario map](../SCENARIOS.md)

# Alpha   (spec: 001-alpha)

The alpha feature, with a form the user can submit.

| ID     | Type  | Scenario              | Expected outcome            | Status |
|--------|-------|-----------------------|-----------------------------|--------|
| @ID1@ | happy | Submit the alpha form | Saved and listed            | ✓      |
| @ID2@ | error | Submit it empty       | Field error, input retained | ◐      |

## The alpha detail   (spec: 001a-alpha-detail)

The nested sub-feature. Its slug is named here and in no index row — the shape that makes the
reminder hook's multi-file search load-bearing rather than decorative.

| ID     | Type  | Scenario                | Expected outcome     | Status |
|--------|-------|-------------------------|----------------------|--------|
| @ID3@ | happy | Open the detail drawer  | The drawer opens     | ✓      |
FIXTURE_ALPHA

    sed "$_FIXTURE_SUBST" > "$_sp_root/specs/scenarios/002-beta.md" <<'FIXTURE_BETA'
[← Scenario map](../SCENARIOS.md)

# Beta   (spec: 002-beta)

The beta feature.

| ID     | Type  | Scenario           | Expected outcome | Status |
|--------|-------|--------------------|------------------|--------|
| @ID4@ | happy | Click the beta tab | The tab opens    | ☐      |
FIXTURE_BETA

    echo "$_sp_root"
    unset _sp_root
}

# make_empty_split_fixture — specs/scenarios/ exists but holds nothing.
# The interrupted-split case. Must read as single_file, or every consumer looks for rows in a
# directory that has none and the reminder hook reports a gap for every spec at once.
make_empty_split_fixture() {
    _es_root="$(_fixture_tmpdir)/empty-$$-${RANDOM:-0}"
    while [ -e "$_es_root" ]; do _es_root="${_es_root}x"; done
    mkdir -p "$_es_root/specs/scenarios"

    _fixture_skeleton "$_es_root"
    _fixture_index_head "$_es_root"
    _fixture_history "$_es_root"

    echo "$_es_root"
    unset _es_root
}
