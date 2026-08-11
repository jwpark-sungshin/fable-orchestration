#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABLE_DIR="$HOME/.claude/fable"
AGENTS_DIR="$HOME/.claude/agents"
BIN_PATH="$HOME/.local/bin/fable"
SETTINGS="$HOME/.claude/settings.json"
STATE="$HOME/.claude/.fable-state"
BACKUP_DIR="$HOME/.claude/fable-backups/uninstall-$(date +%Y%m%d-%H%M%S)-$$"
HOOK_PATH="$FABLE_DIR/hooks/orchestration-gate.py"
MARKER_BEGIN="# >>> fable-orchestration >>>"
MARKER_END="# <<< fable-orchestration <<<"

if [ -f "$FABLE_DIR/shell-rc-path" ]; then
  RC_FILE="$(cat "$FABLE_DIR/shell-rc-path")"
else
  case "$(basename "${SHELL:-sh}")" in
    bash) RC_FILE="$HOME/.bashrc" ;;
    zsh) RC_FILE="$HOME/.zshrc" ;;
    fish) RC_FILE="$HOME/.config/fish/config.fish" ;;
    *) RC_FILE="$HOME/.profile" ;;
  esac
fi

mkdir -p "$BACKUP_DIR"

for agent in researcher executor explainer runner; do
  path="$AGENTS_DIR/$agent.md"
  if [ -L "$path" ] && [ "$(readlink "$path")" = "$FABLE_DIR/agents/$agent.md" ]; then
    rm "$path"
  fi
done

[ -f "$SETTINGS" ] && cp -a "$SETTINGS" "$BACKUP_DIR/settings.json"
python3 "$REPO_DIR/scripts/manage_settings.py" remove "$SETTINGS" "$HOOK_PATH"

if [ -d "$FABLE_DIR" ]; then
  mv "$FABLE_DIR" "$BACKUP_DIR/fable"
fi
if [ -e "$BIN_PATH" ]; then
  mv "$BIN_PATH" "$BACKUP_DIR/fable-command"
fi
if [ -e "$STATE" ]; then
  mv "$STATE" "$BACKUP_DIR/fable-state"
fi

if [ -f "$RC_FILE" ] && grep -qF "$MARKER_BEGIN" "$RC_FILE"; then
  python3 - "$RC_FILE" "$MARKER_BEGIN" "$MARKER_END" <<'PY'
import sys

path, begin, end = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    lines = handle.readlines()

output = []
inside = False
for line in lines:
    if line.rstrip("\n") == begin:
        inside = True
        continue
    if inside and line.rstrip("\n") == end:
        inside = False
        continue
    if not inside:
        output.append(line)

with open(path, "w", encoding="utf-8") as handle:
    handle.writelines(output)
PY
fi

echo "Fable orchestration was disabled and archived, not permanently deleted."
echo "Archive: $BACKUP_DIR"
echo "Open a new shell before starting Claude again."
