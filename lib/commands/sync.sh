# worktree sync - Regenerate config-derived files across all worktrees

_worktree_sync() {
    # Load project-specific config
    _worktree_load_project_config

    # Must be run from the main repo
    if ! _worktree_is_main_repo; then
        echo "Error: Run 'worktree sync' from the main repository."
        echo "  cd $(_worktree_get_main_repo)"
        return 1
    fi

    if [ -z "$WORKTREE_PROCFILE_TEMPLATE" ]; then
        echo "Error: WORKTREE_PROCFILE_TEMPLATE not set in .worktree.config"
        return 1
    fi

    local CURRENT_DIR=$(basename "$(pwd)")
    local updated=0
    local skipped=0

    # Iterate over worktrees (skip the main repo)
    while IFS= read -r wt_path; do
        [ "$wt_path" = "$(pwd)" ] && continue

        if [ -d "$wt_path" ]; then
            echo "$WORKTREE_PROCFILE_TEMPLATE" > "$wt_path/Procfile.local"
            echo "Updated: $(basename "$wt_path")"
            updated=$((updated + 1))
        fi
    done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')

    echo ""
    echo "Synced Procfile.local to $updated worktree(s)."
}
