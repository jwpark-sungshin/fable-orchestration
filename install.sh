#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABLE_DIR="$HOME/.claude/fable"
AGENTS_DIR="$HOME/.claude/agents"
BIN_DIR="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"
STATE="$HOME/.claude/.fable-state"
BACKUP_ROOT="$HOME/.claude/fable-backups"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"
HOOK_PATH="$FABLE_DIR/hooks/orchestration-gate.py"
MARKER_BEGIN="# >>> fable-orchestration >>>"
MARKER_END="# <<< fable-orchestration <<<"

SHELL_NAME="$(basename "${SHELL:-sh}")"
case "$SHELL_NAME" in
  bash) RC_FILE="${FABLE_RC_FILE:-$HOME/.bashrc}" ;;
  zsh) RC_FILE="${FABLE_RC_FILE:-$HOME/.zshrc}" ;;
  fish) RC_FILE="${FABLE_RC_FILE:-$HOME/.config/fish/config.fish}" ;;
  *) RC_FILE="${FABLE_RC_FILE:-$HOME/.profile}" ;;
esac

for command_name in python3 claude; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

mkdir -p "$BACKUP_DIR" "$FABLE_DIR/agents" "$FABLE_DIR/hooks" "$AGENTS_DIR" "$BIN_DIR"

if [ -d "$FABLE_DIR" ] && [ "$(find "$FABLE_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  cp -a "$FABLE_DIR" "$BACKUP_DIR/fable"
fi
[ -f "$SETTINGS" ] && cp -a "$SETTINGS" "$BACKUP_DIR/settings.json"
[ -f "$RC_FILE" ] && cp -a "$RC_FILE" "$BACKUP_DIR/shell-rc"
[ -e "$BIN_DIR/fable" ] && cp -a "$BIN_DIR/fable" "$BACKUP_DIR/fable-command"

install -m 0644 "$REPO_DIR/config/fable.md" "$FABLE_DIR/fable.md"
install -m 0644 "$REPO_DIR/config/empty.md" "$FABLE_DIR/empty.md"
install -m 0644 "$REPO_DIR/config/env.sh" "$FABLE_DIR/env.sh"
install -m 0644 "$REPO_DIR/config/env.fish" "$FABLE_DIR/env.fish"
install -m 0755 "$REPO_DIR/hooks/orchestration-gate.py" "$HOOK_PATH"
install -m 0755 "$REPO_DIR/bin/fable" "$BIN_DIR/fable"

for agent in researcher executor explainer runner; do
  target="$AGENTS_DIR/$agent.md"
  if [ -e "$target" ] || [ -L "$target" ]; then
    cp -a "$target" "$BACKUP_DIR/$agent.md" 2>/dev/null || true
  fi
  install -m 0644 "$REPO_DIR/config/agents/$agent.md" "$FABLE_DIR/agents/$agent.md"
  ln -sfn "$FABLE_DIR/agents/$agent.md" "$target"
done

if [ ! -f "$STATE" ]; then
  echo off > "$STATE"
fi
if [ "$(cat "$STATE" 2>/dev/null)" = "on" ]; then
  ln -sfn "$FABLE_DIR/fable.md" "$FABLE_DIR/active.md"
else
  ln -sfn "$FABLE_DIR/empty.md" "$FABLE_DIR/active.md"
fi

python3 "$REPO_DIR/scripts/manage_settings.py" install "$SETTINGS" "$HOOK_PATH"

mkdir -p "$(dirname "$RC_FILE")"
touch "$RC_FILE"
printf '%s\n' "$RC_FILE" > "$FABLE_DIR/shell-rc-path"
printf '%s\n' "$SHELL_NAME" > "$FABLE_DIR/shell-name"

if [ "$SHELL_NAME" = "fish" ]; then
  LOADER_PATTERN="fable/env.fish"
  LOADER_LINE='test -f "$HOME/.claude/fable/env.fish"; and source "$HOME/.claude/fable/env.fish"'
else
  LOADER_PATTERN="fable/env.sh"
  LOADER_LINE='[ -f "$HOME/.claude/fable/env.sh" ] && . "$HOME/.claude/fable/env.sh"'
fi

if ! grep -qF "$MARKER_BEGIN" "$RC_FILE"; then
  if grep -q "$LOADER_PATTERN" "$RC_FILE"; then
    echo "Existing Fable loader found in $RC_FILE; it was left unchanged."
  else
    {
      printf '\n%s\n' "$MARKER_BEGIN"
      printf '%s\n' "$LOADER_LINE"
      printf '%s\n' "$MARKER_END"
    } >> "$RC_FILE"
  fi
fi

echo
echo "Installed Fable orchestration files."
echo "Backup: $BACKUP_DIR"
echo
echo "Next steps:"
if [ "$SHELL_NAME" = "fish" ]; then
  echo "  source \"$RC_FILE\""
else
  echo "  . \"$RC_FILE\""
fi
echo "  fable on"
echo "  bash \"$REPO_DIR/verify.sh\""
echo "  claude                 # use a fresh session, not --resume/--continue"
