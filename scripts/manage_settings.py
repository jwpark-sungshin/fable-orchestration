#!/usr/bin/env python3
"""Install or remove only the Fable orchestration hook entries."""

import argparse
import json
import os


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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "remove"))
    parser.add_argument("settings_path")
    parser.add_argument("hook_path")
    args = parser.parse_args()

    settings = load_settings(args.settings_path)
    hooks = settings.setdefault("hooks", {})
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
        hooks["UserPromptSubmit"].append(
            {"hooks": [{"type": "command", "command": args.hook_path}]}
        )

    for event in ("PreToolUse", "UserPromptSubmit"):
        if not hooks.get(event):
            hooks.pop(event, None)
    if not hooks:
        settings.pop("hooks", None)

    os.makedirs(os.path.dirname(args.settings_path), exist_ok=True)
    temporary = args.settings_path + ".fable.tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(settings, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(temporary, args.settings_path)


if __name__ == "__main__":
    main()
