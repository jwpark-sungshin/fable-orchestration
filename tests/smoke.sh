#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'case "$TEMP_ROOT" in /tmp/*) rm -rf -- "$TEMP_ROOT" ;; esac' EXIT

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

make_home() {
  local name="$1"
  local home="$TEMP_ROOT/$name"
  mkdir -p "$home/bin" "$home/.claude"
  cp "$REPO_DIR/tests/fixtures/settings.json" "$home/.claude/settings.json"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*"\n' > "$home/bin/claude"
  chmod +x "$home/bin/claude"
  printf '%s\n' "$home"
}

run_bash_case() {
  local test_home
  local output
  test_home="$(make_home bash)"

  HOME="$test_home" SHELL=/bin/bash PATH="$test_home/bin:$PATH" \
    bash "$REPO_DIR/install.sh" >/dev/null
  HOME="$test_home" SHELL=/bin/bash PATH="$test_home/.local/bin:$test_home/bin:$PATH" \
    bash "$REPO_DIR/verify.sh"

  output="$(HOME="$test_home" PATH="$test_home/.local/bin:$test_home/bin:$PATH" \
    "$test_home/.local/bin/fable" on >/dev/null && \
    HOME="$test_home" PATH="$test_home/.local/bin:$test_home/bin:$PATH" \
    "$test_home/.local/bin/fable" run --print-test)"
  grep -q -- '--model claude-fable-5' <<<"$output" || fail "default model was not injected"
  grep -q -- '--effort medium' <<<"$output" || fail "default effort was not injected"
  grep -q -- '--append-system-prompt-file' <<<"$output" || fail "main prompt was not injected"

  output="$(HOME="$test_home" PATH="$test_home/.local/bin:$test_home/bin:$PATH" \
    bash -c '. "$HOME/.bashrc"; claude --through-shell-function')"
  grep -q -- '--model claude-fable-5' <<<"$output" || fail "shell function did not route through fable"

  output="$(HOME="$test_home" PATH="$test_home/.local/bin:$test_home/bin:$PATH" \
    "$test_home/.local/bin/fable" run --model custom --effort low)"
  [ "$(grep -o -- '--model' <<<"$output" | wc -l)" -eq 1 ] || fail "explicit model was duplicated"
  [ "$(grep -o -- '--effort' <<<"$output" | wc -l)" -eq 1 ] || fail "explicit effort was duplicated"

  HOME="$test_home" PATH="$test_home/.local/bin:$test_home/bin:$PATH" \
    "$test_home/.local/bin/fable" off >/dev/null
  output="$(HOME="$test_home" PATH="$test_home/.local/bin:$test_home/bin:$PATH" \
    "$test_home/.local/bin/fable" run --without-fable)"
  ! grep -q -- '--model claude-fable-5' <<<"$output" || fail "disabled mode still injected a model"

  HOME="$test_home" SHELL=/bin/bash PATH="$test_home/bin:$PATH" \
    bash "$REPO_DIR/install.sh" >/dev/null
  [ "$(grep -c '^# >>> fable-orchestration >>>$' "$test_home/.bashrc")" -eq 1 ] \
    || fail "shell loader is not idempotent"
  [ "$(grep -c 'orchestration-gate.py' "$test_home/.claude/settings.json")" -eq 2 ] \
    || fail "hook installation is not idempotent"
  grep -q '"theme": "dark"' "$test_home/.claude/settings.json" \
    || fail "unrelated settings were not preserved"

  HOME="$test_home" SHELL=/bin/bash PATH="$test_home/bin:$PATH" \
    bash "$REPO_DIR/uninstall.sh" >/dev/null
  [ ! -d "$test_home/.claude/fable" ] || fail "installed directory survived uninstall"
  ! grep -q 'fable-orchestration' "$test_home/.bashrc" || fail "shell loader survived uninstall"
  grep -q '"theme": "dark"' "$test_home/.claude/settings.json" \
    || fail "uninstall removed unrelated settings"
}

run_shell_detection_case() {
  local shell_name="$1"
  local shell_path="$2"
  local expected_rc="$3"
  local test_home
  test_home="$(make_home "$shell_name")"

  HOME="$test_home" SHELL="$shell_path" PATH="$test_home/bin:$PATH" \
    bash "$REPO_DIR/install.sh" >/dev/null
  [ -f "$test_home/$expected_rc" ] || fail "$shell_name startup file was not created"
  grep -q 'fable/env.' "$test_home/$expected_rc" || fail "$shell_name loader was not installed"
}

run_bash_case
run_shell_detection_case zsh /usr/bin/zsh .zshrc
run_shell_detection_case fish /usr/bin/fish .config/fish/config.fish
bash "$REPO_DIR/tests/gate.sh"

echo "[OK] Linux installation smoke tests passed"
