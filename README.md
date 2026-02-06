# worktree-tool

A comprehensive CLI tool for managing Git worktrees in Rails development environments. Run multiple branches simultaneously with isolated databases, unique ports, and full process management.

## Features

- **Worktree lifecycle management** - Create, setup, and remove worktrees with a single command
- **Database isolation** - Each worktree gets its own cloned database (dev + test)
- **Automatic port assignment** - Unique Rails and Vite ports per worktree to avoid collisions
- **Process management** - Start/stop/restart dev servers with overmind or foreman
- **Environment isolation** - Per-worktree environment variables via `.overmind.env`
- **Tab completion** - Full zsh and bash completion support
- **Convenient aliases** - Quick shortcuts for common operations

## Requirements

- Git 2.5+ (for worktree support)
- PostgreSQL (for database cloning)
- [overmind](https://github.com/DarthSim/overmind) or [foreman](https://github.com/ddollar/foreman)
- Bash or Zsh shell

## Installation

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/awilkening/worktree-tool/main/install.sh | bash
```

### Manual Install

1. Clone the repository:
   ```bash
   git clone https://github.com/awilkening/worktree-tool.git ~/.worktree-tool
   ```

2. Create a symlink and add to your shell config (`~/.zshrc` or `~/.bashrc`):
   ```bash
   ln -s ~/.worktree-tool/worktree.sh ~/.worktree.sh
   echo 'source "$HOME/.worktree.sh"' >> ~/.zshrc
   ```

3. Reload your shell:
   ```bash
   source ~/.worktree.sh
   ```

## Configuration

Create `.worktree.config` in your project root:

```bash
# .worktree.config
WORKTREE_DEV_DB_PREFIX="myapp_development"
WORKTREE_TEST_DB_PREFIX="myapp_test"
WORKTREE_SOURCE_DB="myapp_development"

# Your Procfile template - use ${PORT} for the Rails port
WORKTREE_PROCFILE_TEMPLATE='web: bin/rails s -p ${PORT:-3000}
vite: bin/vite dev --clobber
worker: bin/sidekiq'
```

### All Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `WORKTREE_DEV_DB_PREFIX` | `myapp_development` | Development database prefix |
| `WORKTREE_TEST_DB_PREFIX` | `myapp_test` | Test database prefix |
| `WORKTREE_SOURCE_DB` | `myapp_development` | Database to clone from |
| `WORKTREE_SETUP_COMMAND` | `bin/update` | Command to run during setup |
| `WORKTREE_PROCFILE_TEMPLATE` | *(none)* | Procfile.local template (required for `worktree start`) |

## Usage

### First Time Setup

Run `worktree init` in your project to create `.worktree.config`:

```bash
cd ~/projects/myapp
worktree init
# Prompts for DB prefix, detects processes, creates config
```

### Basic Workflow

```bash
worktree add my-feature      # Create worktree, cd into it
worktree setup               # Clone DB, install deps
worktree start               # Start dev server
worktree info                # Show URL and config
worktree remove my-feature   # Clean up when done
```

### Quick Start (All-in-One)

```bash
worktree add my-feature --setup
worktree start -D  # -D to daemonize
```

### Commands

| Command | Description |
|---------|-------------|
| `worktree init` | Initialize `.worktree.config` for current project |
| `worktree add <branch> [--setup]` | Create a new worktree (optionally run full setup) |
| `worktree setup` | Clone DB and run setup command |
| `worktree start [-D]` | Start dev server (-D to daemonize) |
| `worktree stop` | Stop dev server |
| `worktree restart` | Restart dev server |
| `worktree info` | Show current worktree config |
| `worktree run <cmd>` | Run command with worktree env vars |
| `worktree console` | Open Rails console |
| `worktree open` | Open app in browser |
| `worktree logs` | View server logs |
| `worktree connect <process>` | Connect to overmind process |
| `worktree cd <name>` | Jump to a worktree |
| `worktree list [-a]` | List worktrees for current project (-a for all) |
| `worktree prune` | Clean up stale port registry entries |
| `worktree remove <branch>` | Remove worktree (offers --wip or --force) |
| `worktree help` | Show help message |

### Aliases

| Alias | Command |
|-------|---------|
| `wt` | `worktree` |
| `wtin` | `worktree init` |
| `wta` | `worktree add` |
| `wts` | `worktree start` |
| `wtp` | `worktree stop` |
| `wtrs` | `worktree restart` |
| `wtr` | `worktree run` |
| `wtc` | `worktree console` |
| `wto` | `worktree open` |
| `wtlg` | `worktree logs` |
| `wtcn` | `worktree connect` |
| `wtcd` | `worktree cd` |
| `wti` | `worktree info` |
| `wtl` | `worktree list` |
| `wtpr` | `worktree prune` |
| `wtrm` | `worktree remove` |

## How It Works

### Port Assignment

Each worktree is assigned a unique "slot" (1-99). Ports are calculated as:
- Rails: `WORKTREE_BASE_RAILS_PORT + slot` (e.g., 3001, 3002, ...)
- Vite: `WORKTREE_BASE_VITE_PORT + slot` (e.g., 3037, 3038, ...)

Port assignments are stored in `~/.worktree-ports`.

### Database Naming

Database names follow the pattern: `{prefix}_{sanitized_branch}`

For example, branch `feature/user-auth` becomes:
- Dev: `myapp_development_feature_user_auth`
- Test: `myapp_test_feature_user_auth`

Long branch names are truncated with a hash suffix to stay under PostgreSQL's 63-character limit.

### Environment Variables

Each worktree gets an `.overmind.env` file with:
```bash
DB_NAME=myapp_development_feature_branch
TEST_DB_NAME=myapp_test_feature_branch
PORT=3001
VITE_RUBY_PORT=3037
```

Use `worktree run` to execute commands with these variables loaded.

### Credentials

Rails credentials `.key` files (which are gitignored) are automatically symlinked from the main repo to each worktree.

## Tips

### Running Tests

Tests automatically use the worktree's isolated test database:
```bash
worktree run bin/rails test
```

### Multiple Worktrees Simultaneously

You can run multiple worktrees at the same time, each with its own:
- Dev server (unique ports)
- Database (isolated data)
- Environment variables

Just make sure to use different browser sessions or incognito windows to avoid session/cookie collisions.

### Removing Worktrees with Uncommitted Changes

When removing a worktree with changes, you'll be prompted to:
1. Create a WIP commit (recommended)
2. Force remove (discard changes)
3. Cancel

Note: Git stashes are per-worktree and will be lost when removing.

## Troubleshooting

### "Overmind is already running"

If you see this error but the server isn't actually running:
```bash
# The socket file may be stale - worktree start will clean it up automatically
# Or manually remove it:
rm .overmind-*.sock
```

### Port Already in Use

Run `worktree prune` to clean up stale port registry entries, then try again.

### Database Doesn't Exist

Run `worktree setup` to clone the source database.

## Project Structure

```
worktree.sh              # Entry point (sources lib files)
lib/
  config.sh              # Configuration defaults and loading
  helpers.sh             # Helper functions (sanitize, slots, etc.)
  completions.sh         # Tab completions and aliases
  commands/
    init.sh              # worktree init
    add.sh               # worktree add
    setup.sh             # worktree setup
    server.sh            # start/stop/restart/logs/connect
    info.sh              # info/list/cd/prune/run/console/open
    remove.sh            # worktree remove
```

## License

MIT License - see [LICENSE](LICENSE) file.
