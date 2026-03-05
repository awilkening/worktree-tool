# worktree clean - Remove orphaned worktree databases

_worktree_clean() {
    local FLAG="$1"

    # Load project-specific config
    _worktree_load_project_config

    local DEV_PREFIX="$WORKTREE_DEV_DB_PREFIX"
    local TEST_PREFIX="$WORKTREE_TEST_DB_PREFIX"

    # Get all databases matching worktree prefixes
    local ALL_DBS
    ALL_DBS=$(psql -lqt | cut -d \| -f 1 | sed 's/^ *//' | sed 's/ *$//' | grep -E "^(${DEV_PREFIX}_|${TEST_PREFIX}_)")

    if [ -z "$ALL_DBS" ]; then
        echo "No worktree databases found."
        return 0
    fi

    # Get active worktree paths
    local ACTIVE_BRANCHES=()
    while IFS= read -r line; do
        # Each worktree list line has: path  commit  [branch]
        local branch=$(echo "$line" | awk '{print $NF}' | sed 's/\[//;s/\]//' | sed 's|.*/||')
        if [ -n "$branch" ]; then
            local sanitized=$(_worktree_sanitize_branch "$branch")
            ACTIVE_BRANCHES+=("$sanitized")
        fi
    done < <(git worktree list)

    # Find orphaned databases
    local ORPHANED_DBS=()
    local ACTIVE_DBS=()

    while IFS= read -r db; do
        [ -z "$db" ] && continue
        local is_active=false

        for branch in "${ACTIVE_BRANCHES[@]}"; do
            if [ "$db" = "${DEV_PREFIX}_${branch}" ] || [ "$db" = "${TEST_PREFIX}_${branch}" ]; then
                is_active=true
                break
            fi
        done

        if $is_active; then
            ACTIVE_DBS+=("$db")
        else
            ORPHANED_DBS+=("$db")
        fi
    done <<< "$ALL_DBS"

    # Show summary
    if [ ${#ACTIVE_DBS[@]} -gt 0 ]; then
        echo "Active worktree databases (${#ACTIVE_DBS[@]}):"
        for db in "${ACTIVE_DBS[@]}"; do
            echo "  $db"
        done
        echo ""
    fi

    if [ ${#ORPHANED_DBS[@]} -eq 0 ]; then
        echo "No orphaned databases found."
        return 0
    fi

    echo "Orphaned databases (${#ORPHANED_DBS[@]}):"
    for db in "${ORPHANED_DBS[@]}"; do
        local size=$(psql -tc "SELECT pg_size_pretty(pg_database_size('$db'));" 2>/dev/null | xargs)
        echo "  $db ($size)"
    done

    if [ "$FLAG" = "--dry-run" ]; then
        return 0
    fi

    echo ""
    if [ "$FLAG" = "--force" ]; then
        local confirm="y"
    else
        read "?Drop all orphaned databases? [y/N]: " confirm 2>/dev/null || read -p "Drop all orphaned databases? [y/N]: " confirm
    fi

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for db in "${ORPHANED_DBS[@]}"; do
            dropdb "$db" && echo "Dropped: $db" || echo "Failed to drop: $db"
        done
        echo ""
        echo "Cleanup complete."
    else
        echo "Aborted."
    fi
}
