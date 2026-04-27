# worktree statusline - Output worktree info for Claude Code's statusLine
#
# Wire it up in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "worktree statusline" }
#
# Claude Code passes session JSON on stdin (we read .cwd from it). If stdin
# is empty or jq isn't available, falls back to $PWD.

_worktree_statusline() {
    local cwd=""

    if [ ! -t 0 ]; then
        local input
        input=$(cat)
        if [ -n "$input" ] && command -v jq &>/dev/null; then
            cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)
        fi
    fi

    [ -z "$cwd" ] && cwd="$PWD"

    local env_file="$cwd/.overmind.env"
    local dir_name
    dir_name=$(basename "$cwd")

    if [ ! -f "$env_file" ]; then
        printf '%s\n' "$dir_name"
        return 0
    fi

    local db_name port
    db_name=$(/usr/bin/grep "^DB_NAME=" "$env_file" 2>/dev/null | /usr/bin/cut -d= -f2-)
    port=$(/usr/bin/grep "^PORT=" "$env_file" 2>/dev/null | /usr/bin/cut -d= -f2-)

    printf '%s · db: %s · http://localhost:%s\n' "$dir_name" "$db_name" "$port"
}
