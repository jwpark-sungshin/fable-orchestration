#!/usr/bin/env bash

set -u

FABLE_DIR="$HOME/.claude/fable"
FAILURES=0

ok() { printf '[OK] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
warn() { printf '[WARN] %s\n' "$1"; }

check_file() {
  if [ -f "$1" ]; then ok "$2"; else fail "$2"; fi
}

check_value() {
  local file="$1"
  local expected="$2"
  local label="$3"
  if grep -qF -- "$expected" "$file" 2>/dev/null; then ok "$label"; else fail "$label"; fi
}

echo "Static installation checks"
check_file "$FABLE_DIR/fable.md" "main orchestration prompt"
check_file "$FABLE_DIR/env.sh" "shell wrapper"
check_file "$FABLE_DIR/hooks/orchestration-gate.py" "orchestration gate"
check_value "$HOME/.local/bin/fable" "--model claude-fable-5" "Fable 5 startup model"
check_value "$HOME/.local/bin/fable" "--effort medium" "main effort medium"
check_value "$FABLE_DIR/agents/researcher.md" "model: claude-opus-5" "researcher uses Opus 5"
check_value "$FABLE_DIR/agents/researcher.md" "effort: xhigh" "researcher effort xhigh"
check_value "$FABLE_DIR/agents/executor.md" "effort: high" "executor effort high"
check_value "$FABLE_DIR/agents/explainer.md" "model: claude-sonnet-5" "explainer uses Sonnet 5"
check_value "$FABLE_DIR/agents/runner.md" "model: claude-haiku-4-5-20251001" "runner uses Haiku"
check_value "$HOME/.claude/settings.json" "orchestration-gate.py" "gate registered in settings"
if [ -f "$FABLE_DIR/shell-rc-path" ]; then
  RC_FILE="$(cat "$FABLE_DIR/shell-rc-path")"
  check_value "$RC_FILE" "fable/env." "wrapper loaded by shell startup file"
else
  fail "recorded shell startup file"
fi

for agent in researcher executor explainer runner; do
  if [ -L "$HOME/.claude/agents/$agent.md" ]; then
    ok "agent link: $agent"
  else
    fail "agent link: $agent"
  fi
done

if grep -q 'fable/active.md' "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
  fail "fable.md must not be imported from ~/.claude/CLAUDE.md"
else
  ok "no global fable.md import"
fi

for variable in CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_EFFORT_LEVEL ANTHROPIC_DEFAULT_SONNET_MODEL; do
  if [ -n "${!variable:-}" ]; then
    warn "$variable is set and may override role routing"
  else
    ok "$variable is not set"
  fi
done

if command -v claude >/dev/null 2>&1; then
  ok "Claude Code executable found: $(command -v claude)"
  claude --version 2>/dev/null || true
else
  fail "Claude Code executable not found"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "Static checks passed. Start a fresh Claude session and run 'fable audit' after using agents."
else
  echo "$FAILURES check(s) failed. Review README.md troubleshooting before starting Claude."
  exit 1
fi
