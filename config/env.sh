# Sourced by POSIX-like interactive shells. It defines a wrapper function; it
# does not start Claude. Argument handling lives in the standalone fable command.

_fable_run() { command "$HOME/.local/bin/fable" run "$@"; }
claude() { _fable_run "$@"; }

