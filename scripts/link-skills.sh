#!/usr/bin/env bash
# Link all skills and commands from napat-skills to Claude Code directories.
# Usage: ./scripts/link-skills.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"

mkdir -p "$SKILLS_DIR" "$COMMANDS_DIR"

echo "Linking skills from $REPO_DIR..."

# Link all SKILL.md directories to ~/.claude/skills/
linked=0
while IFS= read -r skill_file; do
    skill_dir="$(dirname "$skill_file")"
    skill_name="$(basename "$skill_dir")"
    target="$SKILLS_DIR/$skill_name"

    # Remove existing symlink or warn if directory exists
    if [ -L "$target" ]; then
        rm "$target"
    elif [ -e "$target" ]; then
        echo "  SKIP $skill_name — $target exists and is not a symlink"
        continue
    fi

    ln -s "$skill_dir" "$target"
    echo "  skill: $skill_name -> $skill_dir"
    linked=$((linked + 1))
done < <(find "$REPO_DIR/skills" -name "SKILL.md" -not -path "*/commands/*" -type f)

# Link CI/CD commands to ~/.claude/commands/
cmd_linked=0
if [ -d "$REPO_DIR/skills/cicd/github-actions-tlm/commands" ]; then
    for cmd_file in "$REPO_DIR/skills/cicd/github-actions-tlm/commands"/*.md; do
        cmd_name="$(basename "$cmd_file")"
        target="$COMMANDS_DIR/$cmd_name"

        if [ -L "$target" ]; then
            rm "$target"
        elif [ -e "$target" ]; then
            echo "  SKIP command $cmd_name — $target exists and is not a symlink"
            continue
        fi

        ln -s "$cmd_file" "$target"
        echo "  command: $cmd_name -> $cmd_file"
        cmd_linked=$((cmd_linked + 1))
    done
fi

echo ""
echo "Done: $linked skills + $cmd_linked commands linked."
echo "Restart Claude Code to load new skills/commands."
