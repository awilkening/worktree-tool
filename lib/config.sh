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
    WORKTREE_PROCFILE_TEMPLATE=""  # Must be set per-project

    # Load project config if it exists
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$git_root" ] && [ -f "$git_root/.worktree.config" ]; then
        source "$git_root/.worktree.config"
    fi
}
