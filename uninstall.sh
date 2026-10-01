#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FABLE_DIR="$HOME/.claude/fable"
AGENTS_DIR="$HOME/.claude/agents"
BIN_PATH="$HOME/.local/bin/fable"
SETTINGS="$HOME/.claude/settings.json"
STATE="$HOME/.claude/.fable-state"
BACKUP_DIR="$HOME/.claude/fable-backups/uninstall-$(date +%Y%m%d-%H%M%S)-$$"
HOOK_PATH="$FABLE_DIR/hooks/orchestration-gate.py"
MARKER_BEGIN="# >>> fable-orchestration >>>"
MARKER_END="# <<< fable-orchestration <<<"

# Every startup file an install (current or older) may have edited.
RC_FILES=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.config/fish/config.fish")
[ -n "${FABLE_RC_FILE:-}" ] && RC_FILES=("$FABLE_RC_FILE" "${RC_FILES[@]}")

mkdir -p "$BACKUP_DIR"

for agent in researcher executor explainer runner; do
  path="$AGENTS_DIR/$agent.md"
  if [ -L "$path" ]; then
    target="$(readlink "$path")"
    if [ "$target" = "../fable/agents/$agent.md" ] || [ "$target" = "$FABLE_DIR/agents/$agent.md" ]; then
      rm "$path"
    fi
  fi
done

[ -e "$SETTINGS" ] && cp -pL "$SETTINGS" "$BACKUP_DIR/settings.json"
python3 "$REPO_DIR/scripts/manage_settings.py" remove "$SETTINGS" "$HOOK_PATH"

if [ -L "$BIN_PATH" ]; then
  rm "$BIN_PATH"
elif [ -e "$BIN_PATH" ]; then
  mv "$BIN_PATH" "$BACKUP_DIR/fable-command"
fi
if [ -e "$STATE" ]; then
  mv "$STATE" "$BACKUP_DIR/fable-state"
fi

index=0
for rc_file in "${RC_FILES[@]}"; do
  [ -f "$rc_file" ] && grep -qF "$MARKER_BEGIN" "$rc_file" || continue
  if ! awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" \
      '$0 == b { open = 1 } $0 == e && open { open = 0 } END { exit open }' "$rc_file"; then
    echo "WARNING: $rc_file has '$MARKER_BEGIN' without '$MARKER_END'; left unchanged." >&2
    continue
  fi
  index=$((index + 1))
  cp -pL "$rc_file" "$BACKUP_DIR/rc-$index-$(basename "$rc_file")"
  python3 - "$rc_file" "$MARKER_BEGIN" "$MARKER_END" <<'PY'
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

# Rewrite in place so the file's mode and any symlink are kept.
with open(path, "w", encoding="utf-8") as handle:
    handle.writelines(output)
PY
done

if [ -e "$FABLE_DIR/.git" ]; then
  echo "$FABLE_DIR is a git checkout; it was left in place."
elif [ -d "$FABLE_DIR" ]; then
  mv "$FABLE_DIR" "$BACKUP_DIR/fable"
fi

echo "Fable orchestration was disabled and archived, not permanently deleted."
echo "Archive: $BACKUP_DIR"
echo "Open a new shell before starting Claude again."
