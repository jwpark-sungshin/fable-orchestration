# Sourced by Fish. Defines a wrapper function; it does not start Claude.
function claude
    command "$HOME/.local/bin/fable" run $argv
end
