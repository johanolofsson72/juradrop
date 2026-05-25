#!/usr/bin/env bash
# Project Wizard Skill Installer for Claude Code
# Works on macOS and Linux
#
# Usage:
#   curl -sL <url-to-this-script> | bash
#   — or —
#   bash install.sh

set -euo pipefail

SKILL_DIR="${HOME}/.claude/skills/project-wizard"

echo "=== Project Wizard Skill Installer ==="
echo ""

# Check if Claude Code config directory exists
if [ ! -d "${HOME}/.claude" ]; then
    echo "Creating ~/.claude directory..."
    mkdir -p "${HOME}/.claude/skills"
fi

if [ ! -d "${HOME}/.claude/skills" ]; then
    mkdir -p "${HOME}/.claude/skills"
fi

# Check if skill already exists
if [ -d "${SKILL_DIR}" ]; then
    echo "Skill already exists at ${SKILL_DIR}"
    read -p "Overwrite? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    rm -rf "${SKILL_DIR}"
fi

# Create skill directory
mkdir -p "${SKILL_DIR}"

echo "Installing project-wizard skill to ${SKILL_DIR}..."

# Copy SKILL.md (the script assumes it's in the same directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/SKILL.md" ]; then
    cp "${SCRIPT_DIR}/SKILL.md" "${SKILL_DIR}/SKILL.md"
else
    echo "ERROR: SKILL.md not found in ${SCRIPT_DIR}"
    echo "Make sure install.sh and SKILL.md are in the same directory."
    exit 1
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Skill installed to: ${SKILL_DIR}/SKILL.md"
echo ""
echo "Usage: Open Claude Code and type:"
echo "  /project-wizard"
echo "  /project-wizard A ticket management system for small teams"
echo ""
echo "Happy architecting!"
