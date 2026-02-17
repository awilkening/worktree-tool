# worktree setup - Clone DB and run setup command

_worktree_setup() {
    # Load project-specific config
    _worktree_load_project_config

    # Check for .overmind.env (created by worktree add)
    if [ ! -f ".overmind.env" ]; then
        echo "Error: .overmind.env not found. Are you in a worktree created with 'worktree add'?"
        return 1
    fi

    # Run in a subshell to avoid leaking env vars into the parent shell
    (
        # Source .overmind.env and export all variables for child processes
        set -a
        source .overmind.env
        set +a

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
            createdb "$TARGET_DB" || exit 1

            # Dump and restore
            pg_dump "$SOURCE_DB" | psql -q "$TARGET_DB" || exit 1

            echo "Database cloned successfully."
        fi

        # Run setup command
        if [ -n "$WORKTREE_SETUP_COMMAND" ]; then
            echo ""
            echo "Running $WORKTREE_SETUP_COMMAND..."
            eval "$WORKTREE_SETUP_COMMAND" || exit 1
        fi

        echo ""
        echo "Setup complete!"
        echo "Run 'worktree start' to start the dev server."
    )
}
