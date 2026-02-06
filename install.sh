#!/usr/bin/env bash
#
# worktree-tool installer
# https://github.com/awilkening/worktree-tool
#

set -e

INSTALL_DIR="${WORKTREE_INSTALL_DIR:-$HOME/.worktree-tool}"
REPO_URL="https://github.com/awilkening/worktree-tool.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}==>${NC} $1"
}

success() {
    echo -e "${GREEN}==>${NC} $1"
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

error() {
    echo -e "${RED}Error:${NC} $1"
    exit 1
}

# Detect shell
detect_shell() {
    if [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    else
        # Fallback to checking $SHELL
        case "$SHELL" in
            */zsh) echo "zsh" ;;
            */bash) echo "bash" ;;
            *) echo "unknown" ;;
        esac
    fi
}

# Get shell config file
get_shell_config() {
    local shell="$1"
    case "$shell" in
        zsh)
            if [ -f "$HOME/.zshrc" ]; then
                echo "$HOME/.zshrc"
            else
                echo "$HOME/.zprofile"
            fi
            ;;
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            else
                echo "$HOME/.bash_profile"
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

main() {
    echo ""
    echo "  worktree-tool installer"
    echo "  ========================"
    echo ""

    # Check for git
    if ! command -v git &>/dev/null; then
        error "Git is required but not installed."
    fi

    # Check for required tools
    info "Checking dependencies..."

    local missing_deps=()

    if ! command -v psql &>/dev/null; then
        missing_deps+=("postgresql")
    fi

    if ! command -v overmind &>/dev/null && ! command -v foreman &>/dev/null; then
        missing_deps+=("overmind or foreman")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        warn "Missing optional dependencies: ${missing_deps[*]}"
        echo "  These are required for full functionality."
        echo ""
    fi

    # Clone or update repository
    if [ -d "$INSTALL_DIR" ]; then
        info "Updating existing installation..."
        cd "$INSTALL_DIR"
        git pull --quiet origin main 2>/dev/null || git pull --quiet origin master
    else
        info "Cloning worktree-tool to $INSTALL_DIR..."
        git clone --quiet "$REPO_URL" "$INSTALL_DIR"
    fi

    # Make script executable
    chmod +x "$INSTALL_DIR/worktree.sh"

    # Detect shell and config file
    local shell=$(detect_shell)
    local config_file=$(get_shell_config "$shell")

    # Add to shell config if not already present
    local source_line="source \"$INSTALL_DIR/worktree.sh\""

    if [ -n "$config_file" ]; then
        if grep -qF "worktree.sh" "$config_file" 2>/dev/null; then
            info "Already configured in $config_file"
        else
            info "Adding to $config_file..."
            echo "" >> "$config_file"
            echo "# worktree-tool - Git worktree management" >> "$config_file"
            echo "$source_line" >> "$config_file"
        fi
    fi

    echo ""
    success "Installation complete!"
    echo ""
    echo "  Next steps:"
    echo ""
    echo "  1. Reload your shell:"
    if [ -n "$config_file" ]; then
        echo "     source $config_file"
    else
        echo "     source $INSTALL_DIR/worktree.sh"
    fi
    echo ""
    echo "  2. Initialize your project:"
    echo "     cd ~/your-rails-project"
    echo "     worktree init"
    echo ""
    echo "  3. Create your first worktree:"
    echo "     worktree add my-feature --setup"
    echo ""
    echo "  For more info: worktree help"
    echo ""
}

main "$@"
