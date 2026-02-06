#!/usr/bin/env bash
# worktree.sh - Git worktree management for Rails development
# https://github.com/awilkening/worktree-tool
#
# Usage: Source this file in your .zshrc or .bashrc
#   source /path/to/worktree.sh
#
# Then use: worktree <command> [options]

# ============================================================================
# CONFIGURATION
# ============================================================================
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

# ============================================================================
# MAIN FUNCTION
# ============================================================================

worktree() {
    local ACTION="$1"
    shift

    case "$ACTION" in
        init)
            _worktree_init "$@"
            ;;
        add)
            _worktree_add "$@"
            ;;
        setup)
            _worktree_setup "$@"
            ;;
        start)
            _worktree_start "$@"
            ;;
        stop)
            _worktree_stop "$@"
            ;;
        restart)
            _worktree_restart "$@"
            ;;
        info|status)
            _worktree_info "$@"
            ;;
        run)
            _worktree_run "$@"
            ;;
        console)
            _worktree_console "$@"
            ;;
        open)
            _worktree_open "$@"
            ;;
        logs)
            _worktree_logs "$@"
            ;;
        connect)
            _worktree_connect "$@"
            ;;
        cd)
            _worktree_cd "$@"
            ;;
        list|ls)
            _worktree_list "$@"
            ;;
        prune)
            _worktree_prune "$@"
            ;;
        remove|rm)
            _worktree_remove "$@"
            ;;
        help|--help|-h|"")
            _worktree_usage
            ;;
        *)
            echo "Unknown command: $ACTION"
            echo ""
            _worktree_usage
            return 1
            ;;
    esac
}

_worktree_usage() {
    cat << 'EOF'
Usage: worktree <command> [options]

Commands:
  init                    Initialize .worktree.config for current project
  add <branch> [--setup]  Create a new worktree (optionally run full setup)
  setup                   Clone DB and run setup command (run from within worktree)
  start [-D]              Start dev server with unique ports (-D to daemonize)
  stop                    Stop dev server (overmind)
  restart                 Stop and start dev server
  info                    Show current worktree's URL and config
  run <command>           Run a command with worktree env vars loaded
  console                 Open Rails console with worktree env
  open                    Open Rails URL in browser
  logs                    View overmind logs
  connect <process>       Connect to overmind process (web, vite, worker)
  cd <name>               Jump to a worktree by name
  list                    List all worktrees with their ports and databases
  prune                   Clean up stale entries from port registry
  remove <branch>         Remove worktree [--wip|--force]
  help                    Show this help message

Workflow:
  worktree init                # First time: create .worktree.config
  worktree add my-feature      # Create worktree, cd into it
  worktree setup               # Clone DB, run setup command
  worktree start               # Start Rails + Vite on unique ports
  worktree info                # Show URL and config
  worktree remove my-feature   # Remove worktree, optionally drop DB

Quick start:
  worktree init                      # Configure project (first time only)
  worktree add my-feature --setup    # Create + full setup in one command
EOF
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Sanitize branch name for use in database name
_worktree_sanitize_branch() {
    local sanitized=$(echo "$1" | sed 's/[^a-zA-Z0-9]/_/g')

    # Calculate max branch length based on the longer of dev/test prefixes
    local dev_prefix_len=${#WORKTREE_DEV_DB_PREFIX}
    local test_prefix_len=${#WORKTREE_TEST_DB_PREFIX}
    local prefix_len=$((dev_prefix_len > test_prefix_len ? dev_prefix_len : test_prefix_len))
    local max_branch_length=$((WORKTREE_MAX_DB_NAME_LENGTH - prefix_len - 1)) # -1 for underscore

    if [ ${#sanitized} -gt $max_branch_length ]; then
        # Use first part + hash of full name for uniqueness
        local hash=$(echo "$1" | md5sum 2>/dev/null || md5 -q 2>/dev/null)
        hash="${hash:0:8}"
        local truncated_length=$((max_branch_length - 9)) # 8 for hash + 1 for underscore
        sanitized="${sanitized:0:$truncated_length}_${hash}"
    fi

    echo "$sanitized"
}

# Get or assign a port slot for a worktree
_worktree_get_slot() {
    local WORKTREE_PATH="$1"
    local SLOT

    # Create registry if it doesn't exist
    touch "$WORKTREE_PORT_REGISTRY"

    # Check if this worktree already has a slot (use exact match with delimiter)
    SLOT=$(awk -F: -v path="$WORKTREE_PATH" '$1 == path {print $2}' "$WORKTREE_PORT_REGISTRY")

    if [ -z "$SLOT" ]; then
        # Find the next available slot (1-99)
        SLOT=1
        while awk -F: '{print $2}' "$WORKTREE_PORT_REGISTRY" | grep -qx "$SLOT"; do
            SLOT=$((SLOT + 1))
        done
        # Register this worktree
        echo "${WORKTREE_PATH}:${SLOT}" >> "$WORKTREE_PORT_REGISTRY"
    fi

    echo "$SLOT"
}

# Remove a worktree from the port registry
_worktree_release_slot() {
    local WORKTREE_PATH="$1"
    if [ -f "$WORKTREE_PORT_REGISTRY" ]; then
        awk -F: -v path="$WORKTREE_PATH" '$1 != path' "$WORKTREE_PORT_REGISTRY" > "${WORKTREE_PORT_REGISTRY}.tmp"
        mv "${WORKTREE_PORT_REGISTRY}.tmp" "$WORKTREE_PORT_REGISTRY"
    fi
}

# Check if we're in the main repo (not a worktree)
_worktree_is_main_repo() {
    local git_dir=$(git rev-parse --git-dir 2>/dev/null)
    # In a worktree, git-dir is .git/worktrees/<name>, in main repo it's .git
    [[ "$git_dir" == ".git" ]]
}

# Get the main repo path from a worktree
_worktree_get_main_repo() {
    git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's/\/.git$//'
}

# ============================================================================
# COMMAND IMPLEMENTATIONS
# ============================================================================

_worktree_init() {
    # Check if we're in a git repo
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "Error: Not inside a git repository"
        return 1
    fi

    local git_root=$(git rev-parse --show-toplevel)
    local config_file="$git_root/.worktree.config"

    # Check if config already exists
    if [ -f "$config_file" ]; then
        echo "Config already exists: $config_file"
        cat "$config_file"
        echo ""
        local overwrite
        read "?Overwrite? [y/N]: " overwrite 2>/dev/null || read -p "Overwrite? [y/N]: " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            return 0
        fi
    fi

    # Try to detect database name from database.yml
    local detected_db=""
    local db_yml="$git_root/config/database.yml"
    if [ -f "$db_yml" ]; then
        # Look for development database name
        detected_db=$(grep -A5 "^development:" "$db_yml" 2>/dev/null | grep "database:" | head -1 | sed 's/.*database: *//' | sed 's/ *#.*//' | tr -d '[:space:]')
        # Handle ERB: <%= ... %>
        if [[ "$detected_db" == *"<%"* ]]; then
            detected_db=""
        fi
    fi

    # Prompt for database prefix
    local dev_db_prefix
    if [ -n "$detected_db" ]; then
        echo "Detected database: $detected_db"
        read "?Development DB prefix [$detected_db]: " dev_db_prefix 2>/dev/null || read -p "Development DB prefix [$detected_db]: " dev_db_prefix
        dev_db_prefix="${dev_db_prefix:-$detected_db}"
    else
        read "?Development DB prefix: " dev_db_prefix 2>/dev/null || read -p "Development DB prefix: " dev_db_prefix
        if [ -z "$dev_db_prefix" ]; then
            echo "Error: DB prefix is required"
            return 1
        fi
    fi

    # Derive test DB prefix (replace _development with _test, or append _test)
    local test_db_prefix
    if [[ "$dev_db_prefix" == *"_development"* ]]; then
        test_db_prefix="${dev_db_prefix/_development/_test}"
    else
        test_db_prefix="${dev_db_prefix}_test"
    fi
    read "?Test DB prefix [$test_db_prefix]: " input_test_db 2>/dev/null || read -p "Test DB prefix [$test_db_prefix]: " input_test_db
    test_db_prefix="${input_test_db:-$test_db_prefix}"

    # Source DB (usually same as dev prefix)
    read "?Source DB to clone [$dev_db_prefix]: " source_db 2>/dev/null || read -p "Source DB to clone [$dev_db_prefix]: " source_db
    source_db="${source_db:-$dev_db_prefix}"

    # Setup command
    local setup_cmd="bin/update"
    if [ ! -f "$git_root/bin/update" ]; then
        setup_cmd="bin/setup"
    fi
    read "?Setup command [$setup_cmd]: " input_setup 2>/dev/null || read -p "Setup command [$setup_cmd]: " input_setup
    setup_cmd="${input_setup:-$setup_cmd}"

    # Procfile template
    echo ""
    echo "Procfile template (processes to run with 'worktree start')"
    echo "Use \${PORT} for Rails port, \${VITE_RUBY_PORT} for Vite port"
    echo ""

    # Detect what processes might be needed
    local has_vite=false
    local has_sidekiq=false
    local has_good_job=false
    [ -f "$git_root/config/vite.json" ] || [ -f "$git_root/vite.config.js" ] || [ -f "$git_root/vite.config.ts" ] && has_vite=true
    [ -f "$git_root/config/sidekiq.yml" ] && has_sidekiq=true
    grep -q "good_job" "$git_root/Gemfile" 2>/dev/null && has_good_job=true

    local default_procfile="web: bin/rails s -p \${PORT:-3000}"
    if $has_vite; then
        default_procfile="$default_procfile
vite: bin/vite dev --clobber"
    fi
    if $has_sidekiq; then
        default_procfile="$default_procfile
worker: bin/sidekiq"
    elif $has_good_job; then
        default_procfile="$default_procfile
worker: bin/good_job"
    fi

    echo "Suggested template:"
    echo "$default_procfile"
    echo ""
    echo "Press Enter to accept, or type your own (use \\n for newlines):"
    local input_procfile
    read "?> " input_procfile 2>/dev/null || read -p "> " input_procfile

    local procfile_template
    if [ -z "$input_procfile" ]; then
        procfile_template="$default_procfile"
    else
        # Convert \n to actual newlines
        procfile_template=$(echo -e "$input_procfile")
    fi

    # Write config file
    cat > "$config_file" << EOF
# worktree-tool configuration
# Generated by 'worktree init'

WORKTREE_DEV_DB_PREFIX="$dev_db_prefix"
WORKTREE_TEST_DB_PREFIX="$test_db_prefix"
WORKTREE_SOURCE_DB="$source_db"
WORKTREE_SETUP_COMMAND="$setup_cmd"

WORKTREE_PROCFILE_TEMPLATE='$procfile_template'
EOF

    echo ""
    echo "Created: $config_file"
    echo ""
    cat "$config_file"
    echo ""
    echo "You can now run: worktree add <branch-name>"
}

_worktree_add() {
    local BRANCH_NAME="$1"
    local FLAG="$2"

    if [ -z "$BRANCH_NAME" ]; then
        echo "Usage: worktree add <branch-name> [--setup]"
        return 1
    fi

    # Load project-specific config
    _worktree_load_project_config

    # Check if we're in a git repo
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "Error: Not inside a git repository"
        return 1
    fi

    # Check if we're in the main repo, not a worktree
    if ! _worktree_is_main_repo; then
        echo "Error: You're inside a worktree, not the main repository."
        echo "Please run 'worktree add' from the main repository:"
        echo "  cd $(_worktree_get_main_repo)"
        return 1
    fi

    local CURRENT_DIR=$(basename "$(pwd)")
    local WORKTREE_PATH="../${CURRENT_DIR}-${BRANCH_NAME}"
    local MAIN_BRANCH
    local CURRENT_BRANCH

    # Determine the main branch (master or main)
    if git show-ref --verify --quiet refs/heads/main; then
        MAIN_BRANCH="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        MAIN_BRANCH="master"
    else
        echo "Error: Could not find 'main' or 'master' branch"
        return 1
    fi

    # Check if we're on the main branch
    CURRENT_BRANCH=$(git branch --show-current)
    if [ "$CURRENT_BRANCH" != "$MAIN_BRANCH" ]; then
        echo "Switching to $MAIN_BRANCH branch..."
        git checkout "$MAIN_BRANCH" || return 1
    fi

    # Check if worktree path already exists
    if [ -d "$WORKTREE_PATH" ]; then
        echo "Error: Worktree path already exists: $WORKTREE_PATH"
        return 1
    fi

    # Create worktree with new or existing branch
    if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        echo "Branch '$BRANCH_NAME' exists, checking it out..."
        git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" || return 1
    else
        echo "Creating new branch '$BRANCH_NAME'..."
        git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" || return 1
    fi

    # Symlink .key files from config/credentials (they're gitignored)
    local CREDENTIALS_DIR="config/credentials"
    if [ -d "$CREDENTIALS_DIR" ]; then
        for keyfile in "$CREDENTIALS_DIR"/*.key; do
            if [ -f "$keyfile" ]; then
                local keyfile_name=$(basename "$keyfile")
                local keyfile_abs=$(cd "$CREDENTIALS_DIR" && pwd)/"$keyfile_name"
                ln -s "$keyfile_abs" "$WORKTREE_PATH/$CREDENTIALS_DIR/$keyfile_name"
                echo "Symlinked: $keyfile_name"
            fi
        done
    fi

    # Create .overmind.env with port and DB config
    local WORKTREE_ABS_PATH=$(cd "$WORKTREE_PATH" && pwd)
    local SLOT=$(_worktree_get_slot "$WORKTREE_ABS_PATH")
    local RAILS_PORT=$((WORKTREE_BASE_RAILS_PORT + SLOT))
    local VITE_PORT=$((WORKTREE_BASE_VITE_PORT + SLOT))
    local SANITIZED_BRANCH=$(_worktree_sanitize_branch "$BRANCH_NAME")
    local DEV_DB="${WORKTREE_DEV_DB_PREFIX}_${SANITIZED_BRANCH}"
    local TEST_DB="${WORKTREE_TEST_DB_PREFIX}_${SANITIZED_BRANCH}"

    cat > "$WORKTREE_PATH/.overmind.env" << EOF
# Worktree-specific configuration (auto-generated by worktree add)
DB_NAME=$DEV_DB
TEST_DB_NAME=$TEST_DB
PORT=$RAILS_PORT
VITE_RUBY_PORT=$VITE_PORT
EOF

    # Create Procfile.local if template is provided
    if [ -n "$WORKTREE_PROCFILE_TEMPLATE" ]; then
        echo "$WORKTREE_PROCFILE_TEMPLATE" > "$WORKTREE_PATH/Procfile.local"
    fi

    echo ""
    echo "Worktree created at: $WORKTREE_PATH"
    echo "Branch: $BRANCH_NAME"
    echo "  Database: $DEV_DB"
    echo "  Test DB:  $TEST_DB"
    echo "  Rails port: $RAILS_PORT"
    echo "  Vite port: $VITE_PORT"

    if [ -z "$WORKTREE_PROCFILE_TEMPLATE" ]; then
        echo ""
        echo "Warning: WORKTREE_PROCFILE_TEMPLATE not set in .worktree.config"
        echo "You'll need to create Procfile.local manually before running 'worktree start'"
        echo "Use \${PORT} for Rails port and \${VITE_RUBY_PORT} for Vite port"
    fi

    # Change to the new worktree directory
    cd "$WORKTREE_PATH"

    # Run setup if --setup flag provided
    if [ "$FLAG" = "--setup" ]; then
        echo ""
        _worktree_setup
    else
        echo ""
        echo "Run 'worktree setup' to clone the dev database and install dependencies."
    fi
}

_worktree_setup() {
    # Load project-specific config
    _worktree_load_project_config

    # Check for .overmind.env (created by worktree add)
    if [ ! -f ".overmind.env" ]; then
        echo "Error: .overmind.env not found. Are you in a worktree created with 'worktree add'?"
        return 1
    fi

    # Source .overmind.env to get DB name
    source .overmind.env

    local SOURCE_DB="$WORKTREE_SOURCE_DB"
    local TARGET_DB="$DB_NAME"

    echo "Setting up worktree..."
    echo "  Cloning database: $TARGET_DB"
    echo ""

    # Check if target database already exists
    if psql -lqt | cut -d \| -f 1 | grep -qw "$TARGET_DB"; then
        echo "Database '$TARGET_DB' already exists, skipping clone."
    else
        echo "Cloning database '$SOURCE_DB' to '$TARGET_DB'..."

        # Create the database
        createdb "$TARGET_DB" || return 1

        # Dump and restore
        pg_dump "$SOURCE_DB" | psql -q "$TARGET_DB" || return 1

        echo "Database cloned successfully."
    fi

    # Run setup command
    if [ -n "$WORKTREE_SETUP_COMMAND" ]; then
        echo ""
        echo "Running $WORKTREE_SETUP_COMMAND..."
        eval "$WORKTREE_SETUP_COMMAND" || return 1
    fi

    echo ""
    echo "Setup complete!"
    echo "Run 'worktree start' to start the dev server."
}

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

    local path slot found=""
    while IFS=: read -r path slot; do
        local short_path="${path##*/}"
        if [ "$short_path" = "$INPUT" ] || [ "${path##*/}" = "$INPUT" ]; then
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

    local path slot removed=0
    local temp_file="${WORKTREE_PORT_REGISTRY}.tmp"
    > "$temp_file"

    while IFS=: read -r path slot; do
        if [ -d "$path" ]; then
            echo "${path}:${slot}" >> "$temp_file"
        else
            echo "Removing stale entry: ${path##*/}"
            removed=$((removed + 1))
        fi
    done < "$WORKTREE_PORT_REGISTRY"

    mv "$temp_file" "$WORKTREE_PORT_REGISTRY"
    echo "Pruned $removed stale entries."
}

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

    # Source .overmind.env and export all variables, then run the command
    set -a
    source .overmind.env
    set +a
    "$@"
}

_worktree_list() {
    echo "Worktrees:"
    echo ""

    if [ ! -f "$WORKTREE_PORT_REGISTRY" ] || [ ! -s "$WORKTREE_PORT_REGISTRY" ]; then
        echo "  No worktrees registered."
        return 0
    fi

    local path slot rails_port vite_port db_name short_path max_path_len=4

    # First pass: find the longest path name
    while IFS=: read -r path slot; do
        if [ -d "$path" ]; then
            short_path="${path##*/}"
            if [ ${#short_path} -gt $max_path_len ]; then
                max_path_len=${#short_path}
            fi
        fi
    done < "$WORKTREE_PORT_REGISTRY"

    # Print header with dynamic width
    printf "  %-${max_path_len}s  %-12s %-12s %s\n" "PATH" "RAILS PORT" "VITE PORT" "DATABASE"
    printf "  %-${max_path_len}s  %-12s %-12s %s\n" "----" "----------" "---------" "--------"

    # Second pass: print the data
    while IFS=: read -r path slot; do
        if [ -d "$path" ]; then
            rails_port=$((WORKTREE_BASE_RAILS_PORT + slot))
            vite_port=$((WORKTREE_BASE_VITE_PORT + slot))
            db_name=""

            # Try to read DB name from .overmind.env
            if [ -f "$path/.overmind.env" ]; then
                db_name=$(/usr/bin/grep "^DB_NAME=" "$path/.overmind.env" 2>/dev/null | /usr/bin/cut -d= -f2)
            fi

            # Shorten path for display
            short_path="${path##*/}"

            printf "  %-${max_path_len}s  %-12s %-12s %s\n" "$short_path" "$rails_port" "$vite_port" "$db_name"
        fi
    done < "$WORKTREE_PORT_REGISTRY"

    echo ""
}

_worktree_remove() {
    local INPUT="$1"
    local FLAG="$2"

    if [ -z "$INPUT" ]; then
        echo "Usage: worktree remove <branch-name|worktree-dir> [--wip|--force]"
        return 1
    fi

    # Load project-specific config
    _worktree_load_project_config

    local CURRENT_DIR=$(basename "$(pwd)")
    local WORKTREE_PATH
    local MAIN_REPO_PATH
    local BRANCH_NAME
    local HAD_CHANGES=false

    # Determine the main repo name (either current dir or derived from worktree name)
    local MAIN_REPO_NAME
    if _worktree_is_main_repo; then
        MAIN_REPO_NAME="$CURRENT_DIR"
    else
        # We're in a worktree, get main repo name
        MAIN_REPO_NAME=$(basename "$(_worktree_get_main_repo)")
    fi

    # Check if input is a full directory name (starts with main repo prefix)
    if [[ "$INPUT" == "${MAIN_REPO_NAME}-"* ]]; then
        # Extract branch name by removing the prefix
        BRANCH_NAME="${INPUT#${MAIN_REPO_NAME}-}"
    else
        BRANCH_NAME="$INPUT"
    fi

    # Check if we're in the worktree we want to remove
    if [[ "$CURRENT_DIR" == "${MAIN_REPO_NAME}-${BRANCH_NAME}" ]]; then
        # We're in the worktree, derive main repo path
        MAIN_REPO_PATH="../${MAIN_REPO_NAME}"
        WORKTREE_PATH="$(pwd)"

        echo "Currently in worktree, switching to main repo..."
        cd "$MAIN_REPO_PATH" || return 1
    else
        # We're in the main repo or a different worktree
        if _worktree_is_main_repo; then
            WORKTREE_PATH="../${CURRENT_DIR}-${BRANCH_NAME}"
            MAIN_REPO_PATH="$(pwd)"
        else
            MAIN_REPO_PATH="$(_worktree_get_main_repo)"
            WORKTREE_PATH="${MAIN_REPO_PATH}/../${MAIN_REPO_NAME}-${BRANCH_NAME}"
            cd "$MAIN_REPO_PATH" || return 1
        fi
    fi

    # Convert to absolute path for registry
    WORKTREE_PATH=$(cd "$WORKTREE_PATH" 2>/dev/null && pwd) || {
        echo "Error: Worktree does not exist"
        return 1
    }

    # Check for uncommitted changes
    if git -C "$WORKTREE_PATH" status --porcelain | grep -q .; then
        HAD_CHANGES=true

        # If no flag provided, show changes and prompt
        if [ -z "$FLAG" ]; then
            echo "Worktree has uncommitted changes:"
            git -C "$WORKTREE_PATH" status --short
            echo ""
            echo "WARNING: Any stashes in this worktree will be lost!"
            echo ""
            echo "How would you like to proceed?"
            echo "  1) wip    - Create a WIP commit before removing (recommended)"
            echo "  2) force  - Discard all changes and remove"
            echo "  3) cancel - Abort removal"
            echo ""
            read "?Choose [1-3]: " choice 2>/dev/null || read -p "Choose [1-3]: " choice

            case "$choice" in
                1|wip)    FLAG="--wip" ;;
                2|force)  FLAG="--force" ;;
                3|cancel) echo "Aborted."; return 0 ;;
                *)        echo "Invalid choice. Aborted."; return 1 ;;
            esac
        fi

        # Handle the flag
        case "$FLAG" in
            --wip)
                echo "Creating WIP commit..."
                git -C "$WORKTREE_PATH" add -A || return 1
                git -C "$WORKTREE_PATH" commit -m "WIP: Work in progress on $BRANCH_NAME" || return 1
                ;;
            --force)
                echo "Warning: Discarding uncommitted changes and any stashes"
                ;;
            *)
                echo "Unknown flag: $FLAG"
                echo "Use --wip or --force"
                return 1
                ;;
        esac
    fi

    # Check for worktree databases
    local SANITIZED_BRANCH=$(_worktree_sanitize_branch "$BRANCH_NAME")
    local WORKTREE_DB="${WORKTREE_DEV_DB_PREFIX}_${SANITIZED_BRANCH}"
    local WORKTREE_TEST_DB="${WORKTREE_TEST_DB_PREFIX}_${SANITIZED_BRANCH}"
    local DBS_TO_DROP=()

    if psql -lqt | cut -d \| -f 1 | grep -qw "$WORKTREE_DB"; then
        DBS_TO_DROP+=("$WORKTREE_DB")
    fi
    if psql -lqt | cut -d \| -f 1 | grep -qw "$WORKTREE_TEST_DB"; then
        DBS_TO_DROP+=("$WORKTREE_TEST_DB")
    fi

    if [ ${#DBS_TO_DROP[@]} -gt 0 ]; then
        echo ""
        echo "Found worktree databases:"
        for db in "${DBS_TO_DROP[@]}"; do
            echo "  - $db"
        done

        local drop_db
        read "?Drop these databases? [y/N]: " drop_db 2>/dev/null || read -p "Drop these databases? [y/N]: " drop_db

        if [[ "$drop_db" =~ ^[Yy]$ ]]; then
            for db in "${DBS_TO_DROP[@]}"; do
                dropdb "$db"
                echo "Dropped: $db"
            done
        else
            echo "Databases kept."
        fi
    fi

    # Release the port slot
    _worktree_release_slot "$WORKTREE_PATH"

    # Remove the worktree
    echo "Removing worktree at: $WORKTREE_PATH"
    if [ "$FLAG" = "--force" ]; then
        git worktree remove --force "$WORKTREE_PATH" || return 1
    else
        git worktree remove "$WORKTREE_PATH" || return 1
    fi

    echo ""
    echo "Worktree removed: $WORKTREE_PATH"
    echo "Branch '$BRANCH_NAME' still exists. To delete it: git branch -d $BRANCH_NAME"
}

# ============================================================================
# SHELL COMPLETIONS
# ============================================================================

# Zsh completions
if [ -n "$ZSH_VERSION" ]; then
    _worktree_completions() {
        local cmd="${words[2]}"

        case "$CURRENT" in
            2)
                # Complete commands
                compadd init add setup start stop restart info run console open logs connect cd list ls prune remove rm help
                ;;
            3)
                case "$cmd" in
                    remove|rm|cd)
                        # Complete with worktree directory names from registry
                        if [ -f "$WORKTREE_PORT_REGISTRY" ]; then
                            local worktrees=()
                            while IFS=: read -r path slot; do
                                if [ -d "$path" ]; then
                                    worktrees+=("${path##*/}")
                                fi
                            done < "$WORKTREE_PORT_REGISTRY"
                            [ ${#worktrees[@]} -gt 0 ] && compadd -a worktrees
                        fi
                        ;;
                    add)
                        # Complete with git branch names
                        local branches=($(git branch --format='%(refname:short)' 2>/dev/null))
                        [ ${#branches[@]} -gt 0 ] && compadd -a branches
                        ;;
                    connect)
                        # Complete with process names
                        compadd web vite worker
                        ;;
                esac
                ;;
        esac
    }

    compdef _worktree_completions worktree
fi

# Bash completions
if [ -n "$BASH_VERSION" ]; then
    _worktree_bash_completions() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local cmd="${COMP_WORDS[1]}"

        if [ "$COMP_CWORD" -eq 1 ]; then
            COMPREPLY=($(compgen -W "init add setup start stop restart info run console open logs connect cd list ls prune remove rm help" -- "$cur"))
        elif [ "$COMP_CWORD" -eq 2 ]; then
            case "$cmd" in
                remove|rm|cd)
                    if [ -f "$WORKTREE_PORT_REGISTRY" ]; then
                        local worktrees=""
                        while IFS=: read -r path slot; do
                            if [ -d "$path" ]; then
                                worktrees="$worktrees ${path##*/}"
                            fi
                        done < "$WORKTREE_PORT_REGISTRY"
                        COMPREPLY=($(compgen -W "$worktrees" -- "$cur"))
                    fi
                    ;;
                add)
                    local branches=$(git branch --format='%(refname:short)' 2>/dev/null)
                    COMPREPLY=($(compgen -W "$branches" -- "$cur"))
                    ;;
                connect)
                    COMPREPLY=($(compgen -W "web vite worker" -- "$cur"))
                    ;;
            esac
        fi
    }

    complete -F _worktree_bash_completions worktree
fi

# ============================================================================
# ALIASES
# ============================================================================

alias wt='worktree'
alias wtin='worktree init'
alias wta='worktree add'
alias wts='worktree start'
alias wtp='worktree stop'
alias wtrs='worktree restart'
alias wtr='worktree run'
alias wtc='worktree console'
alias wto='worktree open'
alias wtlg='worktree logs'
alias wtcn='worktree connect'
alias wtcd='worktree cd'
alias wti='worktree info'
alias wtl='worktree list'
alias wtpr='worktree prune'
alias wtrm='worktree remove'
