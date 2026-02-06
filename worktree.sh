#!/usr/bin/env bash
# worktree.sh - Git worktree management for Rails development
# https://github.com/awilkening/worktree-tool
#
# Usage: Source this file in your .zshrc or .bashrc
#   source /path/to/worktree.sh
#
# Then use: worktree <command> [options]

# Determine the directory where this script lives
WORKTREE_TOOL_DIR="${BASH_SOURCE[0]:-$0}"
WORKTREE_TOOL_DIR="$(cd "$(dirname "$WORKTREE_TOOL_DIR")" && pwd)"

# Source all the parts
source "$WORKTREE_TOOL_DIR/lib/config.sh"
source "$WORKTREE_TOOL_DIR/lib/helpers.sh"
source "$WORKTREE_TOOL_DIR/lib/commands/init.sh"
source "$WORKTREE_TOOL_DIR/lib/commands/add.sh"
source "$WORKTREE_TOOL_DIR/lib/commands/setup.sh"
source "$WORKTREE_TOOL_DIR/lib/commands/server.sh"
source "$WORKTREE_TOOL_DIR/lib/commands/info.sh"
source "$WORKTREE_TOOL_DIR/lib/commands/remove.sh"
source "$WORKTREE_TOOL_DIR/lib/completions.sh"

# Main function
worktree() {
    local ACTION="$1"
    shift

    case "$ACTION" in
        init)       _worktree_init "$@" ;;
        add)        _worktree_add "$@" ;;
        setup)      _worktree_setup "$@" ;;
        start)      _worktree_start "$@" ;;
        stop)       _worktree_stop "$@" ;;
        restart)    _worktree_restart "$@" ;;
        info|status) _worktree_info "$@" ;;
        run)        _worktree_run "$@" ;;
        console)    _worktree_console "$@" ;;
        open)       _worktree_open "$@" ;;
        logs)       _worktree_logs "$@" ;;
        connect)    _worktree_connect "$@" ;;
        cd)         _worktree_cd "$@" ;;
        list|ls)    _worktree_list "$@" ;;
        prune)      _worktree_prune "$@" ;;
        remove|rm)  _worktree_remove "$@" ;;
        help|--help|-h|"") _worktree_usage ;;
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
  list [-a]               List worktrees for current project (-a for all)
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
