#!/bin/sh
# scenario-map-layout.sh — the one predicate that tells a consumer where the scenario map lives.
#
# WHY ONE FILE: five scripts read the scenario map (the reminder hook, both canary sites, the
# archiver, the sync-feature-json hook). Spec 007bl gives the map a second possible shape. If
# each consumer decided for itself which shape it was looking at, they could disagree — and two
# hooks disagreeing about where the rows are is worse than either being wrong, because the
# disagreement is silent. Sourcing this means changing the rule changes every consumer at once.
#
# THE TWO LAYOUTS (.claude/rules/scenarios.md):
#
#   single_file  specs/SCENARIOS.md holds the use-case diagram, every feature's flowchart, every
#                SC-id row and the history. This is correct for almost every project and is what
#                41 of 42 template projects run today. Nothing about it changed in 007bl.
#
#   split        specs/SCENARIOS.md holds the use-case diagram and a per-feature index; each
#                feature's flowchart, rows and validation prose live in specs/scenarios/<slug>.md
#                and are read only when that feature is worked. A project earns this layout by
#                outgrowing one file, not by preferring it.
#
# AN EMPTY specs/scenarios/ IS single_file. An empty directory is indistinguishable in intent
# from an absent one — it is what a half-finished split, an interrupted checkout, or a stray
# mkdir leaves behind. Treating it as `split` would send every consumer looking for rows in a
# directory that has none, which is the one failure mode with no recovery: the reminder hook
# would report a scenario gap for every spec in the project at once. Clarified in the 007bl
# interview, Q11.
#
# USAGE (source it; it defines a function and runs nothing):
#   . "$(dirname "$0")/scenario-map-layout.sh"
#   case "$(scenario_map_layout "$PROJECT_ROOT")" in
#     split)       ... ;;
#     single_file) ... ;;
#   esac
#
# It can also be run directly, which is what the test harness does:
#   scripts/scenario-map-layout.sh /path/to/project   # prints split | single_file

# scenario_map_layout <project-root>
# Echoes exactly one of: split | single_file
# Never fails, never writes, never reads file contents — the answer is a directory question.
scenario_map_layout() {
    _sml_root="${1:-.}"
    _sml_dir="${_sml_root}/specs/scenarios"

    if [ -d "$_sml_dir" ]; then
        # `ls -A` rather than a glob: a glob that matches nothing expands to itself under sh,
        # so `[ -n "$(echo "$dir"/*)" ]` is true for an empty directory. That is exactly the
        # bug this comment exists to stop someone reintroducing.
        if [ -n "$(ls -A "$_sml_dir" 2>/dev/null)" ]; then
            echo split
            unset _sml_root _sml_dir
            return 0
        fi
    fi

    echo single_file
    unset _sml_root _sml_dir
    return 0
}

# scenario_map_files <project-root>
# Echoes every file that holds scenario rows, one per line, index first. Under single_file that
# is just the index. Consumers that must scan "the whole map" use this instead of hard-coding a
# path, so they keep working in both layouts without repeating the branch.
scenario_map_files() {
    _smf_root="${1:-.}"
    [ -f "${_smf_root}/specs/SCENARIOS.md" ] && echo "${_smf_root}/specs/SCENARIOS.md"

    if [ "$(scenario_map_layout "$_smf_root")" = "split" ]; then
        # -maxdepth 1 so a future subdirectory under specs/scenarios/ is not silently swept in
        # as if it were a feature file. Sorted for deterministic output.
        find "${_smf_root}/specs/scenarios" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort
    fi

    unset _smf_root
    return 0
}

# Direct invocation, for the harness and for a human checking what a project looks like.
# The ${0} guard keeps sourcing side-effect free.
case "${0}" in
    *scenario-map-layout.sh)
        [ "${1:-}" = "--files" ] && { scenario_map_files "${2:-.}"; exit 0; }
        scenario_map_layout "${1:-.}"
        ;;
esac
