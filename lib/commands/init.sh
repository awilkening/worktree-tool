# worktree init - Initialize .worktree.config for a project

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
    local setup_cmd=""
    if [ -f "$git_root/bin/update" ]; then
        setup_cmd="bin/update"
    elif [ -f "$git_root/bin/setup" ]; then
        setup_cmd="bin/setup"
    fi

    if [ -n "$setup_cmd" ]; then
        read "?Setup command [$setup_cmd]: " input_setup 2>/dev/null || read -p "Setup command [$setup_cmd]: " input_setup
        setup_cmd="${input_setup:-$setup_cmd}"
    else
        echo "No bin/update or bin/setup found."
        read "?Setup command (or leave empty to skip): " input_setup 2>/dev/null || read -p "Setup command (or leave empty to skip): " input_setup
        setup_cmd="$input_setup"
    fi

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
    echo "Press Enter to accept, or type custom (separate processes with \\\\n):"
    local input_procfile
    read "?> " input_procfile 2>/dev/null || read -p "> " input_procfile

    local procfile_template
    if [ -z "$input_procfile" ]; then
        procfile_template="$default_procfile"
    else
        # Convert \n to actual newlines
        procfile_template=$(echo -e "$input_procfile")
    fi

    # Check for gitignored .env* files
    local symlink_env_files="false"
    local env_files=()
    for f in "$git_root"/.env*; do
        if [ -f "$f" ] && git check-ignore -q "$f" 2>/dev/null; then
            env_files+=("$(basename "$f")")
        fi
    done

    if [ ${#env_files[@]} -gt 0 ]; then
        echo ""
        echo "Found gitignored env files: ${env_files[*]}"
        local symlink_env
        read "?Symlink these to worktrees? [Y/n]: " symlink_env 2>/dev/null || read -p "Symlink these to worktrees? [Y/n]: " symlink_env
        if [[ ! "$symlink_env" =~ ^[Nn]$ ]]; then
            symlink_env_files="true"
        fi
    fi

    # Write config file
    cat > "$config_file" << EOF
# worktree-tool configuration
# Generated by 'worktree init'

WORKTREE_DEV_DB_PREFIX="$dev_db_prefix"
WORKTREE_TEST_DB_PREFIX="$test_db_prefix"
WORKTREE_SOURCE_DB="$source_db"
WORKTREE_SETUP_COMMAND="$setup_cmd"
WORKTREE_SYMLINK_ENV_FILES="$symlink_env_files"

WORKTREE_PROCFILE_TEMPLATE='$procfile_template'
EOF

    echo ""
    echo "Created: $config_file"
    echo ""
    cat "$config_file"
    echo ""
    echo "You can now run: worktree add <branch-name>"
}
