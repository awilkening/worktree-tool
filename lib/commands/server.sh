# worktree server commands - start/stop/restart/logs/connect

_worktree_start() {
    local DAEMONIZE=""
    if [ "$1" = "-D" ] || [ "$1" = "-d" ]; then
        DAEMONIZE="-D"
    fi

    # Check for .overmind.env
    if [ ! -f ".overmind.env" ]; then
        echo "Error: .overmind.env not found. Are you in a worktree created with 'worktree add'?"
        return 1
    fi

    # Check for Procfile.local
    if [ ! -f "Procfile.local" ]; then
        echo "Error: Procfile.local not found."
        echo "Set WORKTREE_PROCFILE_TEMPLATE in your .worktree.config"
        return 1
    fi

    # Source .overmind.env to get ports for display
    source .overmind.env

    echo "Starting dev server..."
    echo "  Rails: http://localhost:${PORT}"
    echo "  Vite:  http://localhost:${VITE_RUBY_PORT}"
    if [ -n "$DAEMONIZE" ]; then
        echo "  Mode:  daemonized (use 'worktree stop' to stop)"
    fi
    echo ""

    # Check for overmind or foreman
    if command -v overmind &> /dev/null; then
        # Use short names to avoid tmux path length limits
        local SHORT_ID=$(echo "$(pwd)" | md5sum 2>/dev/null || md5 -q 2>/dev/null)
        SHORT_ID="${SHORT_ID:0:8}"
        local OVERMIND_SOCK="./.overmind-${SHORT_ID}.sock"
        local TMUX_SOCK="/tmp/overmind-${SHORT_ID}"

        # Clean up stale socket if overmind isn't actually running
        if [ -e "$OVERMIND_SOCK" ]; then
            if ! OVERMIND_SOCKET="$OVERMIND_SOCK" overmind echo &>/dev/null; then
                echo "Cleaning up stale socket..."
                rm -f "$OVERMIND_SOCK"
            else
                echo "Error: Overmind is already running. Use 'worktree stop' first."
                return 1
            fi
        fi

        # Use Procfile.local which has env var substitution for ports
        # Use short title to avoid tmux socket path length limit
        OVERMIND_SOCKET="$OVERMIND_SOCK" overmind start -f Procfile.local -w "wt-${SHORT_ID}" $DAEMONIZE
    elif command -v foreman &> /dev/null; then
        if [ -n "$DAEMONIZE" ]; then
            echo "Warning: Foreman does not support daemonization. Running in foreground."
        fi
        foreman start -f Procfile.local --env .overmind.env
    else
        echo "Error: Neither overmind nor foreman found. Please install one."
        return 1
    fi
}

_worktree_stop() {
    # Use the same short socket names as start
    local SHORT_ID=$(echo "$(pwd)" | md5sum 2>/dev/null || md5 -q 2>/dev/null)
    SHORT_ID="${SHORT_ID:0:8}"
    local OVERMIND_SOCK="./.overmind-${SHORT_ID}.sock"

    if command -v overmind &> /dev/null && [ -e "$OVERMIND_SOCK" ]; then
        OVERMIND_SOCKET="$OVERMIND_SOCK" overmind quit
        echo "Stopped overmind."
    elif command -v overmind &> /dev/null && [ -e ".overmind.sock" ]; then
        # Fallback for old socket naming
        overmind quit
        echo "Stopped overmind."
    else
        echo "No running overmind process found."
        echo "If using foreman, press Ctrl+C in the terminal running it."
    fi
}

_worktree_restart() {
    _worktree_stop
    sleep 1
    _worktree_start "$@"
}

_worktree_logs() {
    local SHORT_ID=$(echo "$(pwd)" | md5sum 2>/dev/null || md5 -q 2>/dev/null)
    SHORT_ID="${SHORT_ID:0:8}"
    local OVERMIND_SOCK="./.overmind-${SHORT_ID}.sock"

    if [ ! -e "$OVERMIND_SOCK" ]; then
        echo "Error: Overmind is not running. Use 'worktree start' first."
        return 1
    fi

    OVERMIND_SOCKET="$OVERMIND_SOCK" overmind echo
}

_worktree_connect() {
    local PROCESS="$1"

    if [ -z "$PROCESS" ]; then
        echo "Usage: worktree connect <process>"
        echo "Processes: web, vite, worker"
        return 1
    fi

    local SHORT_ID=$(echo "$(pwd)" | md5sum 2>/dev/null || md5 -q 2>/dev/null)
    SHORT_ID="${SHORT_ID:0:8}"
    local OVERMIND_SOCK="./.overmind-${SHORT_ID}.sock"

    if [ ! -e "$OVERMIND_SOCK" ]; then
        echo "Error: Overmind is not running. Use 'worktree start' first."
        return 1
    fi

    OVERMIND_SOCKET="$OVERMIND_SOCK" overmind connect "$PROCESS"
}
