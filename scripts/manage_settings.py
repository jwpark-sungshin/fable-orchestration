#!/usr/bin/env python3
"""Install or remove only the Fable orchestration hook entries."""

import argparse
import json
import os
import stat
import tempfile


def load_settings(path):
    try:
        with open(path, encoding="utf-8") as handle:
            value = json.load(handle)
        if not isinstance(value, dict):
            raise ValueError("settings root must be an object")
        return value
    except FileNotFoundError:
        return {}


def is_fable_hook(group, hook_path):
    for hook in group.get("hooks", []):
        command = hook.get("command", "")
        if command == hook_path or command.endswith("/fable/hooks/orchestration-gate.py"):
            return True
    return False


def write_settings(path, settings):
    # Follow a symlinked settings.json so the link itself survives.
    target = os.path.realpath(path)
    directory = os.path.dirname(target)
    os.makedirs(directory, exist_ok=True)
    try:
        mode = stat.S_IMODE(os.stat(target).st_mode)
    except FileNotFoundError:
        mode = 0o600

    # mkstemp creates the file with mode 0600 regardless of umask.
    fd, temporary = tempfile.mkstemp(prefix=".settings.", suffix=".fable.tmp", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(settings, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        os.chmod(temporary, mode)
        os.replace(temporary, target)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "remove"))
    parser.add_argument("settings_path")
    parser.add_argument("hook_path")
    args = parser.parse_args()

    settings = load_settings(args.settings_path)
    hooks = settings.setdefault("hooks", {})
    # UserPromptSubmit is only cleaned up: older installs registered the gate
    # there, but the current gate reads prompt_id and needs no such entry.
    for event in ("PreToolUse", "UserPromptSubmit"):
        groups = hooks.setdefault(event, [])
        groups[:] = [group for group in groups if not is_fable_hook(group, args.hook_path)]

    if args.action == "install":
        hooks["PreToolUse"].append(
            {
                "matcher": "Write|Edit|NotebookEdit|MultiEdit|Bash",
                "hooks": [{"type": "command", "command": args.hook_path}],
            }
        )

    for event in ("PreToolUse", "UserPromptSubmit"):
        if not hooks.get(event):
            hooks.pop(event, None)
    if not hooks:
        settings.pop("hooks", None)

    write_settings(args.settings_path, settings)


if __name__ == "__main__":
    main()
