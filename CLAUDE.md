# CLAUDE.md — Project Guidelines for zsh-shell-setup

## Project Overview

A single-file bash script (`setup-zsh.sh`) that automates installing zsh, oh-my-zsh, and popular plugins across macOS, RHEL/CentOS, and Ubuntu for a specified user.

## Version

Current version: **1.1.0** — defined in `setup-zsh.sh` as `readonly VERSION="1.1.0"` (line 4). When bumping the version, update both `setup-zsh.sh` and `README.md`.

## Repository Structure

```
setup-zsh.sh      Main setup script (bash, executable)
README.md          Usage docs, supported OS list, plugin catalog
CLAUDE.md          This file — project rules and conventions
.gitignore         Ignore patterns for macOS, editors, backups
```

## Coding Conventions

- **Shell:** Bash (`#!/usr/bin/env bash`), must be bash 3 compatible (no associative arrays — macOS ships bash 3)
- **Strict mode:** `set -euo pipefail` at the top of the script
- **Linting:** Must pass `bash -n` and `shellcheck` with zero warnings
- **Plugin arrays:** Use pipe-delimited strings in indexed arrays:
  - Bundled: `"name|description|os_filter"`
  - External: `"name|repo_url|description"`
- **OS-specific plugins:** Use the `os_filter` field (`all` or `darwin`)
- **Colors:** Use the defined constants (`RED`, `GREEN`, `YELLOW`, `BLUE`, `BOLD`, `NC`). No raw ANSI codes elsewhere.
- **Logging:** Use `info()`, `success()`, `warn()`, `error()`, `fatal()` — never raw `echo` for status messages
- **Dry-run:** All system-modifying commands must go through `run_cmd` or `run_as_user`, which respect `DRY_RUN`
- **sed compatibility:** Always use `sed -i.tmp` (works on both BSD and GNU sed), clean up `.tmp` file after

## Adding a New Plugin

1. **Bundled plugin:** Add entry to `BUNDLED_PLUGINS` array in `setup-zsh.sh`
2. **External plugin:** Add entry to `EXTERNAL_PLUGINS` array in `setup-zsh.sh`
3. **Update `usage()`** in `setup-zsh.sh` — add the plugin to the appropriate help section
4. **Update `README.md`** — add the plugin to the appropriate table
5. Run `shellcheck setup-zsh.sh` to verify

## Key Design Decisions

- **Single file:** Everything lives in `setup-zsh.sh` for easy distribution (`curl | bash` friendly)
- **Interactive plugin selection:** Numbered menu with `all`, `none`, or space-separated numbers
- **git plugin always included:** Auto-added if user doesn't select it
- **oh-my-zsh unattended install:** Uses `RUNZSH=no CHSH=no KEEP_ZSHRC=yes` with `--unattended`
- **Backup before modifying .zshrc:** Creates timestamped `.bak` files
- **Permissions check:** Fails early if installing for another user without root
- **Plugin load order:** External plugins array order matters — `fzf-tab` must come before `zsh-autosuggestions` and `zsh-syntax-highlighting`
- **Plugin-specific dependencies:** `fzf-tab` auto-installs `fzf` if not present
- **Uninstall mode:** `--uninstall` reverses setup; shell change and oh-my-zsh removal are automatic, but zsh/fzf package removal is opt-in (prompted) to avoid breaking other tools

## Testing

- `bash -n setup-zsh.sh` — syntax check
- `shellcheck setup-zsh.sh` — lint check (must be zero warnings)
- `./setup-zsh.sh --help` — verify help output shows all plugins
- `./setup-zsh.sh --dry-run` — full end-to-end dry run (no system changes)
- `./setup-zsh.sh --uninstall --dry-run` — dry run of uninstall mode
