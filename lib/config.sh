# Configuration for worktree-tool
# Project-specific settings go in .worktree.config in your project root.

# Global defaults
WORKTREE_PORT_REGISTRY="$HOME/.worktree-ports"
WORKTREE_BASE_RAILS_PORT=3000
WORKTREE_BASE_VITE_PORT=3036
WORKTREE_MAX_DB_NAME_LENGTH=63

# Load project-specific config (called by commands that need it)
_worktree_load_project_config() {
    # Reset to defaults
    WORKTREE_DEV_DB_PREFIX="myapp_development"
    WORKTREE_TEST_DB_PREFIX="myapp_test"
    WORKTREE_SOURCE_DB="myapp_development"
    WORKTREE_SETUP_COMMAND="bin/update"
    WORKTREE_SYMLINK_ENV_FILES="false"
    WORKTREE_PROCFILE_TEMPLATE=""  # Must be set per-project

    # Load project config if it exists
    # When in a worktree, look for config in the main repo
    local config_dir
    if _worktree_is_main_repo; then
        config_dir=$(git rev-parse --show-toplevel 2>/dev/null)
    else
        config_dir=$(_worktree_get_main_repo)
    fi

    if [ -n "$config_dir" ] && [ -f "$config_dir/.worktree.config" ]; then
        source "$config_dir/.worktree.config"
    fi
}
