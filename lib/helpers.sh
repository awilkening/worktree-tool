# Helper functions for worktree-tool

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

# Copy Claude Code MCP server config from main repo to worktree
_worktree_copy_claude_mcp_config() {
    local MAIN_REPO_PATH="$1"
    local WORKTREE_PATH="$2"
    local CLAUDE_CONFIG="$HOME/.claude.json"

    # Check if jq is available and claude.json exists
    if ! command -v jq &>/dev/null || [ ! -f "$CLAUDE_CONFIG" ]; then
        return 0
    fi

    # Check if main repo has MCP servers configured
    local MAIN_MCP_SERVERS
    MAIN_MCP_SERVERS=$(jq -r --arg path "$MAIN_REPO_PATH" '.projects[$path].mcpServers // empty' "$CLAUDE_CONFIG" 2>/dev/null)

    if [ -n "$MAIN_MCP_SERVERS" ] && [ "$MAIN_MCP_SERVERS" != "{}" ] && [ "$MAIN_MCP_SERVERS" != "null" ]; then
        # Copy MCP servers config to worktree project
        local TEMP_FILE=$(mktemp)
        jq --arg main "$MAIN_REPO_PATH" --arg wt "$WORKTREE_PATH" '
            .projects[$wt] = (.projects[$wt] // {}) |
            .projects[$wt].mcpServers = .projects[$main].mcpServers
        ' "$CLAUDE_CONFIG" > "$TEMP_FILE" && mv "$TEMP_FILE" "$CLAUDE_CONFIG"
        echo "Copied Claude MCP config to worktree"
    fi
}
