#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'case "$TEMP_ROOT" in /tmp/*) rm -rf -- "$TEMP_ROOT" ;; esac' EXIT
umask 022

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

make_home() {
  local home="$TEMP_ROOT/$1"
  mkdir -p "$home/bin" "$home/.claude"
  cp "$REPO_DIR/tests/fixtures/settings.json" "$home/.claude/settings.json"
  chmod 0600 "$home/.claude/settings.json"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*"\n' > "$home/bin/claude"
  chmod +x "$home/bin/claude"
  printf '%s\n' "$home"
}

# Runs a command with HOME set to the test home ($H).
in_home() {
  HOME="$H" SHELL="${TEST_SHELL:-/bin/bash}" PATH="$H/.local/bin:$H/bin:$PATH" "$@"
}

mode_of() { stat -c '%a' "$1"; }

hook_count() {
  python3 - "$H/.claude/settings.json" "$1" <<'PY'
import json
import sys

hooks = json.load(open(sys.argv[1])).get("hooks", {})
print(sum("orchestration-gate" in hook.get("command", "")
          for group in hooks.get(sys.argv[2], []) for hook in group.get("hooks", [])))
PY
}

agent_links_relative() {
  local agent
  for agent in executor explainer researcher runner; do
    [ "$(readlink "$H/.claude/agents/$agent.md")" = "../fable/agents/$agent.md" ] || return 1
    [ -f "$H/.claude/agents/$agent.md" ] || return 1
  done
}

no_agent_links() {
  local agent
  for agent in executor explainer researcher runner; do
    [ ! -e "$H/.claude/agents/$agent.md" ] && [ ! -L "$H/.claude/agents/$agent.md" ] || return 1
  done
}

copy_install_case() {
  H="$(make_home copy)"
  in_home bash "$REPO_DIR/install.sh" >/dev/null

  local fable="$H/.claude/fable"
  [ -L "$fable/active.md" ] && [ "$(readlink "$fable/active.md")" = fable.md ] || fail "active.md is not a symlink to fable.md"
  [ ! -e "$fable/.git" ] || fail ".git was copied"
  [ ! -e "$fable/config" ] && [ ! -e "$fable/env.fish" ] || fail "old layout files present"
  cmp -s "$REPO_DIR/env.sh" "$fable/env.sh" || fail "env.sh was not copied"
  [ "$(mode_of "$fable/hooks/orchestration-gate.py")" = 755 ] || fail "hook is not executable"
  [ "$(mode_of "$fable/fable.md")" = 644 ] || fail "fable.md mode is not 644"
  [ "$(readlink "$H/.local/bin/fable")" = "$fable/bin/fable" ] || fail "fable command is not linked"
  [ "$(mode_of "$H/.claude/settings.json")" = 600 ] || fail "settings mode changed under umask 022"
  grep -q '"theme": "dark"' "$H/.claude/settings.json" || fail "unrelated settings were not preserved"
  [ "$(hook_count PreToolUse)" = 1 ] || fail "gate not registered once"
  [ "$(hook_count UserPromptSubmit)" = 0 ] || fail "UserPromptSubmit entry was added"
  grep -qxF '# >>> fable-orchestration >>>' "$H/.bashrc" || fail "shell loader missing"
  [ "$(cat "$H/.claude/.fable-state" 2>/dev/null || echo off)" = off ] || fail "fresh install is not off"
  no_agent_links || fail "agent links created while off"
  in_home bash "$REPO_DIR/verify.sh" >/dev/null || fail "verify.sh failed (off)"

  in_home fable on >/dev/null
  agent_links_relative || fail "fable on did not create relative agent links"
  local output
  output="$(in_home fable status)"
  grep -q '\[OK\] agent: runner' <<<"$output" || fail "status does not recognise relative links"
  grep -q '\[OK\] shell wrapper' <<<"$output" || fail "status does not see the bashrc loader"
  in_home bash "$REPO_DIR/verify.sh" >/dev/null || fail "verify.sh failed (on)"

  output="$(in_home bash -c '. "$HOME/.bashrc" >/dev/null 2>&1; claude --print-test')"
  grep -q -- '--model claude-fable-5' <<<"$output" || fail "shell function did not inject the model"
  grep -q -- '--effort medium' <<<"$output" || fail "shell function did not inject the effort"
  grep -q -- '--append-system-prompt-file' <<<"$output" || fail "shell function did not inject the prompt"

  in_home fable off >/dev/null
  no_agent_links || fail "fable off left agent links"
  output="$(in_home fable status)"
  grep -q 'Fable orchestration: OFF' <<<"$output" || fail "status is not OFF"

  # Reinstall keeps the saved state and is idempotent.
  in_home fable on >/dev/null
  in_home bash "$REPO_DIR/install.sh" >/dev/null
  agent_links_relative || fail "reinstall did not apply saved ON state"
  [ "$(grep -c '^# >>> fable-orchestration >>>$' "$H/.bashrc")" -eq 1 ] || fail "shell loader is not idempotent"
  [ "$(hook_count PreToolUse)" = 1 ] || fail "hook installation is not idempotent"
  [ "$(mode_of "$H/.claude/settings.json")" = 600 ] || fail "settings mode changed on reinstall"

  # Uninstall backs up and removes only Fable entries.
  printf 'user line\n' >> "$H/.bashrc"
  in_home bash "$REPO_DIR/uninstall.sh" >/dev/null
  [ ! -d "$H/.claude/fable" ] || fail "installed directory survived uninstall"
  [ ! -e "$H/.local/bin/fable" ] && [ ! -L "$H/.local/bin/fable" ] || fail "fable command survived uninstall"
  no_agent_links || fail "agent links survived uninstall"
  ! grep -q 'fable-orchestration' "$H/.bashrc" || fail "shell loader survived uninstall"
  grep -qx 'user line' "$H/.bashrc" || fail "uninstall removed user lines"
  grep -q '"theme": "dark"' "$H/.claude/settings.json" || fail "uninstall removed unrelated settings"
  [ "$(hook_count PreToolUse)" = 0 ] || fail "gate survived uninstall"
  [ "$(mode_of "$H/.claude/settings.json")" = 600 ] || fail "settings mode changed on uninstall"
  local backup
  backup="$(ls -d "$H"/.claude/fable-backups/uninstall-*)"
  [ -f "$backup/settings.json" ] || fail "uninstall did not back up settings.json"
  grep -q 'fable-orchestration' "$backup"/rc-*-.bashrc || fail "uninstall did not back up .bashrc"
  [ -d "$backup/fable" ] || fail "uninstall did not archive the fable folder"
}

old_layout_case() {
  H="$(make_home old)"
  local fable="$H/.claude/fable"
  mkdir -p "$fable/agents" "$fable/hooks" "$fable/state" "$H/.claude/agents"
  for name in fable.md empty.md env.sh env.fish shell-rc-path shell-name; do
    printf 'old %s\n' "$name" > "$fable/$name"
  done
  for agent in executor explainer researcher runner; do
    printf 'old\n' > "$fable/agents/$agent.md"
    ln -s "$fable/agents/$agent.md" "$H/.claude/agents/$agent.md"
  done
  printf '{}\n' > "$fable/state/session.json"
  printf '#!/bin/sh\nexit 0\n' > "$fable/hooks/orchestration-gate.py"
  ln -s "$fable/empty.md" "$fable/active.md"
  printf 'on\n' > "$H/.claude/.fable-state"
  python3 - "$H/.claude/settings.json" "$fable/hooks/orchestration-gate.py" <<'PY'
import json
import sys

path, hook = sys.argv[1:]
settings = json.load(open(path))
entry = {"hooks": [{"type": "command", "command": hook}]}
settings["hooks"]["PreToolUse"].append(dict(entry, matcher="Write|Edit"))
settings["hooks"]["UserPromptSubmit"] = [entry]
json.dump(settings, open(path, "w"), indent=2)
PY

  in_home bash "$REPO_DIR/install.sh" >/dev/null
  [ ! -e "$fable/env.fish" ] && [ ! -e "$fable/shell-rc-path" ] && [ ! -e "$fable/shell-name" ] \
    || fail "stale old-layout files survived reinstall"
  [ -f "$fable/state/session.json" ] || fail "runtime state was not kept"
  [ "$(readlink "$fable/active.md")" = fable.md ] || fail "active.md was not replaced"
  cmp -s "$REPO_DIR/hooks/orchestration-gate.py" "$fable/hooks/orchestration-gate.py" || fail "hook not replaced"
  [ "$(hook_count UserPromptSubmit)" = 0 ] || fail "old UserPromptSubmit entry survived"
  [ "$(hook_count PreToolUse)" = 1 ] || fail "old PreToolUse entry was not replaced"
  agent_links_relative || fail "absolute agent links were not replaced with relative ones"
  [ -f "$(ls -d "$H"/.claude/fable-backups/2*)/fable/env.fish" ] || fail "old folder was not backed up"
}

in_place_case() {
  H="$(make_home inplace)"
  local fable="$H/.claude/fable"
  mkdir -p "$fable"
  find "$REPO_DIR" -mindepth 1 -maxdepth 1 ! -name .git ! -name state -exec cp -a -t "$fable" -- {} +
  git -C "$fable" init -q
  git -C "$fable" add -A
  git -C "$fable" -c user.name=test -c user.email=test@example.com commit -qm checkout

  local before after status=0 output
  output="$(in_home bash "$fable/install.sh")"
  grep -q 'in place' <<<"$output" || fail "in-place install was not detected"
  [ -z "$(git -C "$fable" status --porcelain)" ] || fail "in-place install modified the checkout"
  [ "$(hook_count PreToolUse)" = 1 ] || fail "in-place install did not register the gate"
  in_home bash "$fable/verify.sh" >/dev/null || fail "verify.sh failed for in-place install"

  before="$(git -C "$fable" rev-parse HEAD)"
  in_home bash "$REPO_DIR/install.sh" >/dev/null 2>&1 || status=$?
  [ "$status" -ne 0 ] || fail "install copied over a git checkout"
  after="$(git -C "$fable" rev-parse HEAD)"
  [ "$before" = "$after" ] && [ -z "$(git -C "$fable" status --porcelain)" ] || fail "refused install changed the checkout"

  in_home bash "$fable/uninstall.sh" >/dev/null
  [ -d "$fable/.git" ] || fail "uninstall moved a git checkout"
}

symlinked_settings_case() {
  H="$(make_home symlink)"
  mkdir -p "$H/dotfiles"
  mv "$H/.claude/settings.json" "$H/dotfiles/settings.json"
  ln -s ../dotfiles/settings.json "$H/.claude/settings.json"
  in_home bash "$REPO_DIR/install.sh" >/dev/null
  [ -L "$H/.claude/settings.json" ] || fail "symlinked settings.json was replaced"
  [ "$(hook_count PreToolUse)" = 1 ] || fail "gate not written through the symlink"
  [ "$(mode_of "$H/dotfiles/settings.json")" = 600 ] || fail "symlink target mode changed"
  in_home bash "$REPO_DIR/uninstall.sh" >/dev/null
  [ -L "$H/.claude/settings.json" ] || fail "uninstall replaced symlinked settings.json"
  [ "$(hook_count PreToolUse)" = 0 ] || fail "gate not removed through the symlink"
}

new_settings_case() {
  H="$(make_home newsettings)"
  rm "$H/.claude/settings.json"
  in_home bash "$REPO_DIR/install.sh" >/dev/null
  [ "$(mode_of "$H/.claude/settings.json")" = 600 ] || fail "new settings.json is not 0600"
}

unterminated_marker_case() {
  H="$(make_home unterminated)"
  in_home bash "$REPO_DIR/install.sh" >/dev/null
  printf '# >>> fable-orchestration >>>\nexport KEEP_ME=1\n' > "$H/.zshrc"
  cp "$H/.zshrc" "$TEMP_ROOT/zshrc.before"
  local output
  output="$(in_home bash "$REPO_DIR/uninstall.sh" 2>&1)"
  cmp -s "$H/.zshrc" "$TEMP_ROOT/zshrc.before" || fail "unterminated marker block was edited"
  grep -q "WARNING: $H/.zshrc" <<<"$output" || fail "no warning for unterminated marker block"
  ! grep -q 'fable-orchestration' "$H/.bashrc" || fail "terminated block in .bashrc was not removed"
}

shell_case() {
  H="$(make_home zsh)"
  TEST_SHELL=/usr/bin/zsh in_home bash "$REPO_DIR/install.sh" >/dev/null
  grep -q 'fable/env.sh' "$H/.zshrc" || fail "zsh loader was not installed"

  H="$(make_home fish)"
  local status=0
  TEST_SHELL=/usr/bin/fish in_home bash "$REPO_DIR/install.sh" >/dev/null 2>&1 || status=$?
  [ "$status" -ne 0 ] || fail "unsupported shell did not stop the install"
  [ ! -e "$H/.claude/fable" ] || fail "unsupported shell still installed files"
  TEST_SHELL=/usr/bin/fish FABLE_RC_FILE="$H/custom-rc" in_home bash "$REPO_DIR/install.sh" >/dev/null
  grep -q 'fable/env.sh' "$H/custom-rc" || fail "FABLE_RC_FILE was not used"
}

copy_install_case
old_layout_case
in_place_case
symlinked_settings_case
new_settings_case
unterminated_marker_case
shell_case
bash "$REPO_DIR/tests/gate.sh"

echo "[OK] installation smoke tests passed"
