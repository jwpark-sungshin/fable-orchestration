#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/hooks/orchestration-gate.py"
TEST_HOME="$(mktemp -d)"
trap 'case "$TEST_HOME" in /tmp/*) rm -rf -- "$TEST_HOME" ;; esac' EXIT

PROJECT="$TEST_HOME/project"
mkdir -p "$TEST_HOME/.claude" "$PROJECT/sub"
ln -s "$PROJECT" "$TEST_HOME/project-link"

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

invoke() {
  printf '%s\n' "$1" | HOME="$TEST_HOME" python3 "$HOOK"
}

expect_allow() {
  invoke "$1" 2>/dev/null || fail "$2 (expected allow)"
}

expect_block() {
  local status=0
  BLOCK_OUTPUT="$(invoke "$1" 2>&1)" || status=$?
  [ "$status" -eq 2 ] || fail "$2 (expected block, got exit $status)"
}

edit() {
  printf '{"session_id":"s1","prompt_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" "$3"
}

BASH_MAIN='{"session_id":"s1","prompt_id":"p1","tool_name":"Bash","tool_input":{"command":"ls"}}'
BASH_SUB='{"session_id":"s1","prompt_id":"p1","agent_id":"a1","agent_type":"runner","tool_name":"Bash","tool_input":{"command":"ls"}}'

# Off (no state file, then explicit off): everything is allowed.
expect_allow "$BASH_MAIN" "gate active without a state file"
printf 'off\n' > "$TEST_HOME/.claude/.fable-state"
expect_allow "$BASH_MAIN" "gate active while off"
expect_allow "$(edit p0 Edit "$PROJECT/x1.py")" "off: code edit 1"
expect_allow "$(edit p0 Edit "$PROJECT/x2.py")" "off: code edit 2"
expect_allow "$(edit p0 Edit "$PROJECT/x3.py")" "off: code edit 3"

printf 'on\n' > "$TEST_HOME/.claude/.fable-state"

# Main-agent Bash is blocked; subagent Bash is allowed.
expect_block "$BASH_MAIN" "main Bash"
grep -q 'cannot run Bash directly' <<<"$BLOCK_OUTPUT" || fail "wrong Bash block reason"
expect_allow "$BASH_SUB" "subagent Bash"

# Non-code files are never counted.
for name in a.md b.txt c.json d.yaml e; do
  expect_allow "$(edit p1 Write "$PROJECT/$name")" "non-code file $name"
done

# Two code files per prompt_id; paths are compared after realpath.
expect_allow "$(edit p1 Edit "$PROJECT/a.py")" "first code file"
expect_allow "$(edit p1 Write "$PROJECT/sub/../b.ts")" "second code file"
expect_allow "$(edit p1 Edit "$TEST_HOME/project-link/a.py")" "same file via symlink"
expect_allow "$(edit p1 Edit "$PROJECT/./b.ts")" "same file via ./"
expect_block "$(edit p1 Edit "$PROJECT/c.sh")" "third code file"
grep -q 'already edited 2 code files in this turn' <<<"$BLOCK_OUTPUT" || fail "wrong limit block reason"
expect_allow "$(printf '{"session_id":"s1","prompt_id":"p1","agent_id":"a1","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$PROJECT/c.sh")" \
  "subagent code edit over the limit"

# A new prompt_id resets the count.
expect_allow "$(edit p2 Edit "$PROJECT/c.sh")" "code file in the next prompt"

# Missing or malformed prompt_id (or payload) fails open.
for payload in \
  "{\"session_id\":\"s1\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PROJECT/m1.py\"}}" \
  "{\"session_id\":\"s1\",\"prompt_id\":null,\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PROJECT/m2.py\"}}" \
  "{\"session_id\":\"s1\",\"prompt_id\":\"\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PROJECT/m3.py\"}}" \
  "{\"session_id\":\"s1\",\"prompt_id\":[],\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PROJECT/m4.py\"}}" \
  'not json'; do
  expect_allow "$payload" "missing/malformed prompt_id: $payload"
done
expect_allow "$(edit p2 Edit "$PROJECT/d.py")" "second file in p2 after fail-open edits"

echo "[OK] orchestration gate checks passed"
