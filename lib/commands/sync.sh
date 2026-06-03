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

    local MAIN_REPO_ABS_PATH=$(git rev-parse --path-format=absolute --show-toplevel 2>/dev/null)
    local MAIN_REPO_REAL_PATH=$(cd "$MAIN_REPO_ABS_PATH" && pwd -P)
    local checked=0
    local procfiles=0

    # Iterate over worktrees (skip the main repo)
    while IFS= read -r wt_path; do
        if [ -d "$wt_path" ]; then
            local wt_real_path=$(cd "$wt_path" && pwd -P)
            [ "$wt_real_path" = "$MAIN_REPO_REAL_PATH" ] && continue

            echo "Syncing: $(basename "$wt_path")"

            if [ -n "$WORKTREE_PROCFILE_TEMPLATE" ]; then
                echo "$WORKTREE_PROCFILE_TEMPLATE" > "$wt_path/Procfile.local"
                procfiles=$((procfiles + 1))
            fi

            _worktree_mirror_project_config_dir "$MAIN_REPO_ABS_PATH" "$wt_path" ".claude"
            _worktree_mirror_project_config_dir "$MAIN_REPO_ABS_PATH" "$wt_path" ".codex"
            checked=$((checked + 1))
        fi
    done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')

    echo ""
    if [ -n "$WORKTREE_PROCFILE_TEMPLATE" ]; then
        echo "Synced Procfile.local to $procfiles worktree(s)."
    else
        echo "Skipped Procfile.local: WORKTREE_PROCFILE_TEMPLATE not set."
    fi
    echo "Checked assistant config symlinks in $checked worktree(s)."
}
