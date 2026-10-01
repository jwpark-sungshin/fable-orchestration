#!/usr/bin/env bash

set -euo pipefail

# The repository root has the same layout as the installed ~/.claude/fable.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
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
LOADER_LINE='[ -f "$HOME/.claude/fable/env.sh" ] && . "$HOME/.claude/fable/env.sh"'

SHELL_NAME="$(basename "${SHELL:-sh}")"
if [ -n "${FABLE_RC_FILE:-}" ]; then
  RC_FILE="$FABLE_RC_FILE"
else
  case "$SHELL_NAME" in
    bash) RC_FILE="$HOME/.bashrc" ;;
    zsh) RC_FILE="$HOME/.zshrc" ;;
    *)
      echo "Unsupported shell: $SHELL_NAME. env.sh supports bash and zsh." >&2
      echo "Set FABLE_RC_FILE to a bash/zsh startup file to install anyway." >&2
      exit 1
      ;;
  esac
fi

for command_name in python3 claude; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

IN_PLACE=0
if [ -d "$FABLE_DIR" ] && [ "$(cd "$FABLE_DIR" && pwd -P)" = "$REPO_DIR" ]; then
  IN_PLACE=1
elif [ -e "$FABLE_DIR/.git" ]; then
  echo "$FABLE_DIR is a git checkout; refusing to copy over it." >&2
  echo "Run its own install.sh instead: bash \"$FABLE_DIR/install.sh\"" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR" "$AGENTS_DIR" "$BIN_DIR"

if [ "$IN_PLACE" -eq 0 ]; then
  if [ -d "$FABLE_DIR" ] && [ "$(find "$FABLE_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    cp -a "$FABLE_DIR" "$BACKUP_DIR/fable"
  fi
  mkdir -p "$FABLE_DIR"
  # Replace everything except runtime state, so files from older layouts
  # (config/, env.fish, shell-rc-path, ...) do not linger.
  find "$FABLE_DIR" -mindepth 1 -maxdepth 1 ! -name state -exec rm -rf -- {} +
  find "$REPO_DIR" -mindepth 1 -maxdepth 1 ! -name .git ! -name state \
    -exec cp -a -t "$FABLE_DIR" -- {} +
  # Normalise permissions independent of the checkout's umask.
  find "$FABLE_DIR" -mindepth 1 -path "$FABLE_DIR/state" -prune -o ! -type l \
    -exec chmod u+rwX,go+rX,go-w -- {} +
fi
chmod 0755 "$HOOK_PATH" "$FABLE_DIR/bin/fable"

if [ -e "$BIN_DIR/fable" ] || [ -L "$BIN_DIR/fable" ]; then
  cp -a "$BIN_DIR/fable" "$BACKUP_DIR/fable-command"
fi
ln -sfn "$FABLE_DIR/bin/fable" "$BIN_DIR/fable"

for agent in researcher executor explainer runner; do
  target="$AGENTS_DIR/$agent.md"
  if [ -e "$target" ] || [ -L "$target" ]; then
    cp -a "$target" "$BACKUP_DIR/$agent.md"
  fi
done

[ -e "$SETTINGS" ] && cp -pL "$SETTINGS" "$BACKUP_DIR/settings.json"
python3 "$REPO_DIR/scripts/manage_settings.py" install "$SETTINGS" "$HOOK_PATH"

# Agent links are created (relative) or removed by the saved on/off state.
if [ "$(cat "$STATE" 2>/dev/null)" = "on" ]; then
  "$FABLE_DIR/bin/fable" on >/dev/null
else
  "$FABLE_DIR/bin/fable" off >/dev/null
fi

mkdir -p "$(dirname "$RC_FILE")"
touch "$RC_FILE"
if grep -qF "$MARKER_BEGIN" "$RC_FILE"; then
  :
elif grep -q 'fable/env.sh' "$RC_FILE"; then
  echo "Existing Fable loader found in $RC_FILE; it was left unchanged."
else
  cp -pL "$RC_FILE" "$BACKUP_DIR/$(basename "$RC_FILE")"
  {
    printf '\n%s\n' "$MARKER_BEGIN"
    printf '%s\n' "$LOADER_LINE"
    printf '%s\n' "$MARKER_END"
  } >> "$RC_FILE"
fi

echo
if [ "$IN_PLACE" -eq 1 ]; then
  echo "Installed Fable orchestration in place: $FABLE_DIR"
else
  echo "Installed Fable orchestration files into $FABLE_DIR."
fi
echo "Backup: $BACKUP_DIR"
echo
echo "Next steps:"
echo "  . \"$RC_FILE\""
echo "  fable on"
echo "  bash \"$FABLE_DIR/verify.sh\""
echo "  claude                 # use a fresh session, not --resume/--continue"
