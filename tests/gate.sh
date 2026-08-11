#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/hooks/orchestration-gate.py"
TEST_HOME="$(mktemp -d)"
trap 'case "$TEST_HOME" in /tmp/*) rm -rf -- "$TEST_HOME" ;; esac' EXIT

mkdir -p "$TEST_HOME/.claude"
printf 'on\n' > "$TEST_HOME/.claude/.fable-state"

invoke() {
  local payload="$1"
  printf '%s\n' "$payload" | HOME="$TEST_HOME" python3 "$HOOK"
}

invoke '{"hook_event_name":"UserPromptSubmit","session_id":"session-a"}'
invoke '{"hook_event_name":"PreToolUse","session_id":"session-a","tool_name":"Edit","tool_input":{"file_path":"/project/a.py"}}'
invoke '{"hook_event_name":"PreToolUse","session_id":"session-a","tool_name":"Write","tool_input":{"file_path":"/project/b.py"}}'
invoke '{"hook_event_name":"PreToolUse","session_id":"session-a","tool_name":"Edit","tool_input":{"file_path":"/project/a.py"}}'

set +e
blocked="$(invoke '{"hook_event_name":"PreToolUse","session_id":"session-a","tool_name":"Edit","tool_input":{"file_path":"/project/c.py"}}' 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || { echo "[FAIL] third code file was not blocked" >&2; exit 1; }
grep -q 'already edited 2 code files this turn' <<<"$blocked" \
  || { echo "[FAIL] gate returned the wrong reason" >&2; exit 1; }

invoke '{"hook_event_name":"UserPromptSubmit","session_id":"session-a"}'
invoke '{"hook_event_name":"PreToolUse","session_id":"session-a","tool_name":"Edit","tool_input":{"file_path":"/project/c.py"}}'

invoke '{"hook_event_name":"PreToolUse","session_id":"session-a","agent_id":"subagent-1","tool_name":"Edit","tool_input":{"file_path":"/project/d.py"}}'

echo "[OK] orchestration gate turn reset and delegation checks passed"

