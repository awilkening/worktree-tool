# Shell completions and aliases for worktree-tool

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
                            local line path
                            while read -r line; do
                                path="${line%%:*}"
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
                        local line path
                        while read -r line; do
                            path="${line%%:*}"
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

# Aliases
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
