# worktree remove - Remove a worktree

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
