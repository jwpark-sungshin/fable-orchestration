#!/usr/bin/env python3
"""Limit direct main-agent code edits while Fable mode is enabled.

This is a workflow guard, not a security sandbox. Subagents are allowed because
delegation is the intended execution path. Unexpected hook failures fail open so
a configuration error cannot make Claude Code unusable.
"""

import json
import os
import re
import sys
import time
import fcntl

LIMIT = 2
STATE_FILE = os.path.expanduser("~/.claude/.fable-state")
GATE_STATE_DIR = os.path.expanduser("~/.claude/fable/state")
CODE_EXTS = {
    "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go", "rs", "java",
    "kt", "kts", "swift", "c", "h", "cc", "cpp", "hpp", "cs", "rb",
    "php", "vue", "svelte", "astro", "css", "scss", "sass", "less",
    "html", "sh", "bash", "zsh", "sql", "lua", "dart", "scala", "ex",
    "exs", "zig", "ipynb",
}
EXT_RE = "|".join(sorted(CODE_EXTS))


def allow():
    raise SystemExit(0)


def deny(message):
    sys.stderr.write(message + "\n")
    raise SystemExit(2)


def is_code(path):
    return "." in path and path.rsplit(".", 1)[-1].lower() in CODE_EXTS


def session_paths(data):
    session = re.sub(r"[^a-zA-Z0-9-]", "", data.get("session_id", "nosession"))
    base = os.path.join(GATE_STATE_DIR, session)
    return base + ".json", base + ".lock"


def save_gate(path, gate):
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(gate, handle)
    os.replace(temporary, path)


def clean_old_state():
    now = time.time()
    for filename in os.listdir(GATE_STATE_DIR):
        candidate = os.path.join(GATE_STATE_DIR, filename)
        try:
            if now - os.path.getmtime(candidate) > 86400:
                os.remove(candidate)
        except OSError:
            pass


def main():
    try:
        with open(STATE_FILE, encoding="utf-8") as handle:
            enabled = handle.read().strip() == "on"
    except OSError:
        enabled = False

    if not enabled:
        allow()

    data = json.load(sys.stdin)

    if data.get("agent_id") or data.get("agent_type"):
        allow()

    os.makedirs(GATE_STATE_DIR, exist_ok=True)
    gate_file, lock_file = session_paths(data)

    if data.get("hook_event_name") == "UserPromptSubmit":
        with open(lock_file, "a", encoding="utf-8") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            save_gate(gate_file, {"files": []})
        clean_old_state()
        allow()

    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}

    if tool == "Bash":
        command = tool_input.get("command", "")
        inplace = re.search(r"\b(sed|perl)\s+[^|;&]*-\w*i", command)
        redirect = re.search(
            r"(?:>>?|\btee\b(?:\s+-\w+)*)\s*['\"]?[^\s'\"|;&<>]+\.(?:%s)\b"
            % EXT_RE,
            command,
        )
        mentions_code = re.search(r"\.(?:%s)\b" % EXT_RE, command)
        if redirect or (inplace and mentions_code):
            deny(
                "[fable gate] The main agent cannot modify code through Bash. "
                "Delegate engineering to executor, research-grade work to "
                "researcher, explanations to explainer, or mechanical work to runner."
            )
        allow()

    if tool not in ("Edit", "Write", "NotebookEdit", "MultiEdit"):
        allow()

    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if not path or not is_code(path):
        allow()

    with open(lock_file, "a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        gate = {"files": []}
        try:
            with open(gate_file, encoding="utf-8") as handle:
                saved = json.load(handle)
            if isinstance(saved.get("files"), list):
                gate = saved
        except (OSError, ValueError):
            pass

        if path in gate["files"]:
            allow()

        if len(gate["files"]) < LIMIT:
            gate["files"].append(path)
            save_gate(gate_file, gate)
            allow()

        deny(
            "[fable gate] The main agent already edited %d code files this turn (%s). "
            "Delegate the attempted change (%s) to a named subagent."
            % (LIMIT, ", ".join(gate["files"]), path)
        )


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        raise SystemExit(0)
