# worktree info commands - info/list/cd/prune/run/console/open

_worktree_info() {
    # Check for .overmind.env
    if [ ! -f ".overmind.env" ]; then
        if _worktree_is_main_repo; then
            echo "You're in the main repo. Use 'worktree list' to see all worktrees."
        else
            echo "Error: .overmind.env not found. Are you in a worktree created with 'worktree add'?"
        fi
        return 1
    fi

    # Source .overmind.env to get config
    source .overmind.env

    local BRANCH=$(git branch --show-current)

    echo ""
    echo "Worktree: $(basename "$(pwd)")"
    echo "Branch:   $BRANCH"
    echo ""
    echo "URL:      http://localhost:${PORT}"
    echo ""
    echo "Database: $DB_NAME"
    echo "Test DB:  $TEST_DB_NAME"
    echo "Vite:     http://localhost:${VITE_RUBY_PORT}"
    echo ""
}

_worktree_list() {
    local show_all=false
    if [ "$1" = "-a" ] || [ "$1" = "--all" ]; then
        show_all=true
    fi

    if [ ! -f "$WORKTREE_PORT_REGISTRY" ] || [ ! -s "$WORKTREE_PORT_REGISTRY" ]; then
        echo "No worktrees registered."
        return 0
    fi

    # Determine current project name for filtering
    local current_project=""
    if ! $show_all && git rev-parse --is-inside-work-tree &>/dev/null; then
        if _worktree_is_main_repo; then
            current_project=$(basename "$(pwd)")
        else
            current_project=$(basename "$(_worktree_get_main_repo)")
        fi
    fi

    local line path slot rails_port vite_port db_name short_path max_path_len=4
    local has_entries=false

    # First pass: find the longest path name (filtered)
    while read -r line; do
        path="${line%%:*}"
        if [ -d "$path" ]; then
            short_path="${path##*/}"
            # Filter by project if not showing all
            if [ -n "$current_project" ] && [[ "$short_path" != "${current_project}-"* ]]; then
                continue
            fi
            has_entries=true
            if [ ${#short_path} -gt $max_path_len ]; then
                max_path_len=${#short_path}
            fi
        fi
    done < "$WORKTREE_PORT_REGISTRY"

    if ! $has_entries; then
        if [ -n "$current_project" ]; then
            echo "No worktrees for $current_project. Use 'worktree list -a' to see all."
        else
            echo "No worktrees registered."
        fi
        return 0
    fi

    echo "Worktrees${current_project:+ for $current_project}:"
    echo ""

    # Print header with dynamic width
    printf "  %-${max_path_len}s  %-12s %-12s %s\n" "PATH" "RAILS PORT" "VITE PORT" "DATABASE"
    printf "  %-${max_path_len}s  %-12s %-12s %s\n" "----" "----------" "---------" "--------"

    # Second pass: print the data (filtered)
    while read -r line; do
        path="${line%%:*}"
        slot="${line#*:}"
        if [ -d "$path" ]; then
            short_path="${path##*/}"
            # Filter by project if not showing all
            if [ -n "$current_project" ] && [[ "$short_path" != "${current_project}-"* ]]; then
                continue
            fi

            rails_port=$((WORKTREE_BASE_RAILS_PORT + slot))
            vite_port=$((WORKTREE_BASE_VITE_PORT + slot))
            db_name=""

            # Try to read DB name from .overmind.env
            if [ -f "$path/.overmind.env" ]; then
                db_name=$(/usr/bin/grep "^DB_NAME=" "$path/.overmind.env" 2>/dev/null | /usr/bin/cut -d= -f2)
            fi

            printf "  %-${max_path_len}s  %-12s %-12s %s\n" "$short_path" "$rails_port" "$vite_port" "$db_name"
        fi
    done < "$WORKTREE_PORT_REGISTRY"

    echo ""
}

_worktree_cd() {
    local INPUT="$1"

    if [ -z "$INPUT" ]; then
        echo "Usage: worktree cd <worktree-name>"
        return 1
    fi

    # Find the worktree path from registry
    if [ ! -f "$WORKTREE_PORT_REGISTRY" ]; then
        echo "Error: No worktrees registered."
        return 1
    fi

    local line path short_path found=""
    while read -r line; do
        path="${line%%:*}"
        short_path="${path##*/}"
        if [ "$short_path" = "$INPUT" ]; then
            if [ -d "$path" ]; then
                found="$path"
                break
            fi
        fi
    done < "$WORKTREE_PORT_REGISTRY"

    if [ -z "$found" ]; then
        echo "Error: Worktree '$INPUT' not found."
        echo "Use 'worktree list' to see available worktrees."
        return 1
    fi

    cd "$found"
}

_worktree_prune() {
    if [ ! -f "$WORKTREE_PORT_REGISTRY" ]; then
        echo "No worktrees registered."
        return 0
    fi

    local line path removed=0
    local temp_file="${WORKTREE_PORT_REGISTRY}.tmp"
    > "$temp_file"

    while read -r line; do
        path="${line%%:*}"
        if [ -d "$path" ]; then
            echo "$line" >> "$temp_file"
        else
            echo "Removing stale entry: ${path##*/}"
            removed=$((removed + 1))
        fi
    done < "$WORKTREE_PORT_REGISTRY"

    mv "$temp_file" "$WORKTREE_PORT_REGISTRY"
    echo "Pruned $removed stale entries."
}

_worktree_run() {
    if [ $# -eq 0 ]; then
        echo "Usage: worktree run <command>"
        echo "Example: worktree run bin/rails db:migrate"
        return 1
    fi

    # Check for .overmind.env
    if [ ! -f ".overmind.env" ]; then
        echo "Error: .overmind.env not found. Are you in a worktree created with 'worktree add'?"
        return 1
    fi

    # Run in a subshell to avoid leaking env vars into the parent shell
    (
        set -a
        source .overmind.env
        set +a
        "$@"
    )
}

_worktree_console() {
    _worktree_run bin/rails console "$@"
}

_worktree_open() {
    # Check for .overmind.env
    if [ ! -f ".overmind.env" ]; then
        echo "Error: .overmind.env not found. Are you in a worktree created with 'worktree add'?"
        return 1
    fi

    source .overmind.env
    local url="http://localhost:${PORT}"
    echo "Opening $url"

    # Cross-platform open
    if command -v open &>/dev/null; then
        open "$url"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$url"
    else
        echo "Could not detect browser opener. Visit: $url"
    fi
}
