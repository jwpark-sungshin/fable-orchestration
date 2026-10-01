# Fable launcher wrapper.
# When enabled, the main session explicitly starts with Fable 5 at high effort.
# Subagents use their own model and effort settings.

_fable_on() {
  [ "$(cat "$HOME/.claude/.fable-state" 2>/dev/null)" = "on" ]
}

_fable_run() {
  if ! _fable_on; then
    command claude "$@"
    return
  fi

  case "${1:-}" in
    update|install|doctor|mcp|plugin|agents)
      command claude "$@"
      return
      ;;
  esac

  local prompt_file="$HOME/.claude/fable/fable.md"
  local -a defaults=(
    --append-system-prompt-file "$prompt_file"
  )

  local arg
  local has_model=0
  local has_effort=0

  for arg in "$@"; do
    case "$arg" in
      --model|--model=*)
        has_model=1
        ;;
      --effort|--effort=*)
        has_effort=1
        ;;
    esac
  done

  # Respect explicit user overrides.
  (( has_model )) || defaults+=(--model claude-fable-5-1)
  (( has_effort )) || defaults+=(--effort medium)

  command claude "${defaults[@]}" "$@"
}

claude() {
  _fable_run "$@"
}
