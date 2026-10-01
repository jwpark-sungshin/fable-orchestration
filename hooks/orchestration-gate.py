#!/usr/bin/env python3
"""Restrict direct tool execution by the main Fable orchestrator."""

import fcntl
import json
import os
import re
import sys
import time

LIMIT = 2
STATE_FILE = os.path.expanduser("~/.claude/.fable-state")
GATE_STATE_DIR = os.path.expanduser("~/.claude/fable/state")

CODE_EXTENSIONS = {
    "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go", "rs", "java", "kt",
    "kts", "swift", "c", "h", "cc", "cpp", "hpp", "cs", "rb", "php", "vue",
    "svelte", "astro", "css", "scss", "sass", "less", "html", "sh", "bash",
    "zsh", "sql", "lua", "dart", "scala", "ex", "exs", "zig", "ipynb",
}


def allow():
    sys.exit(0)


def deny(message):
    sys.stderr.write(message)
    sys.exit(2)


def is_code_file(path):
    if "." not in path:
        return False
    return path.rsplit(".", 1)[-1].lower() in CODE_EXTENSIONS


def cleanup_old_state():
    now = time.time()

    try:
        entries = os.scandir(GATE_STATE_DIR)
    except OSError:
        return

    with entries:
        for entry in entries:
            try:
                if entry.is_file() and now - entry.stat().st_mtime > 86400:
                    os.remove(entry.path)
            except OSError:
                pass


def main():
    try:
        enabled = open(STATE_FILE, encoding="utf-8").read().strip() == "on"
    except OSError:
        enabled = False

    if not enabled:
        allow()

    data = json.load(sys.stdin)

    # Subagents are the intended execution path and are not restricted.
    if data.get("agent_id") or data.get("agent_type"):
        allow()

    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}

    if tool == "Bash":
        deny(
            "[Fable gate] The main orchestrator cannot run Bash directly. "
            "Delegate commands and inspection to runner, ordinary code work to "
            "executor, and research-grade work to researcher."
        )

    if tool not in {"Edit", "Write", "NotebookEdit", "MultiEdit"}:
        allow()

    path = (
        tool_input.get("file_path")
        or tool_input.get("notebook_path")
        or ""
    )

    if not path or not is_code_file(path):
        allow()

    # prompt_id requires a recent Claude Code version. Fail open when absent.
    prompt_id = data.get("prompt_id")
    if not prompt_id:
        allow()

    session_id = re.sub(
        r"[^a-zA-Z0-9-]",
        "",
        data.get("session_id", "nosession"),
    )
    normalized_path = os.path.realpath(os.path.expanduser(path))

    os.makedirs(GATE_STATE_DIR, exist_ok=True)
    cleanup_old_state()

    state_path = os.path.join(GATE_STATE_DIR, f"{session_id}.json")
    blocked_files = []

    with open(state_path, "a+", encoding="utf-8") as state_file:
        fcntl.flock(state_file.fileno(), fcntl.LOCK_EX)
        state_file.seek(0)

        try:
            state = json.load(state_file)
        except (ValueError, OSError):
            state = {}

        if state.get("prompt_id") != prompt_id:
            state = {"prompt_id": prompt_id, "files": []}

        files = state.setdefault("files", [])

        if normalized_path in files:
            allow()

        if len(files) < LIMIT:
            files.append(normalized_path)
            state_file.seek(0)
            state_file.truncate()
            json.dump(state, state_file)
            state_file.flush()
            allow()

        blocked_files = list(files)

    deny(
        "[Fable gate] The main orchestrator already edited "
        f"{LIMIT} code files in this turn: {', '.join(blocked_files)}. "
        f"Delegate the remaining change ({normalized_path}) to executor or "
        "researcher."
    )


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)
