# zsh-shell-setup

> **Version 1.2.0**

Automated setup script for zsh and oh-my-zsh with interactive plugin selection.

## Supported Operating Systems

- **macOS** (via Homebrew)
- **Ubuntu / Debian / Raspberry Pi OS** (via apt)
- **RHEL / CentOS / Rocky / Alma / Fedora** (via dnf/yum)

## Prerequisites

- `git` and `curl` (the script will install these if missing)
- **macOS:** [Homebrew](https://brew.sh) must be installed
- **Linux:** Root or sudo access for package installation

## What It Does

1. Detects your OS and package manager
2. Installs prerequisites (`git`, `curl`) if missing
3. Installs zsh (the Z shell)
4. Installs [oh-my-zsh](https://ohmyz.sh/) (community-driven zsh framework)
5. Prompts you to select plugins from the catalog below
6. Configures your `.zshrc` with selected plugins
7. Adds SSH hostname detection to your prompt (shows hostname in yellow when connected via SSH)
8. Sets zsh as your default shell

## Usage

```bash
# Install for current user
./setup-zsh.sh

# Install for a specific user
./setup-zsh.sh --user chris

# Preview what would happen without making changes
./setup-zsh.sh --dry-run

# Install for another user (requires root)
sudo ./setup-zsh.sh --user deploy

# Show help with full plugin descriptions
./setup-zsh.sh --help
```

### Uninstall

```bash
# Uninstall for current user (revert to bash)
./setup-zsh.sh --uninstall

# Uninstall for a specific user
./setup-zsh.sh --uninstall --user chris

# Preview what uninstall would do
./setup-zsh.sh --uninstall --dry-run
```

The uninstall will:
1. Switch the default shell back to `/bin/bash`
2. Remove the `~/.oh-my-zsh` directory (including all external plugins)
3. Restore `.zshrc` from backup if available, or remove it
4. Optionally prompt to uninstall `fzf` and `zsh` packages

### Options

| Flag | Description |
|------|-------------|
| `-u`, `--user <username>` | Target user (default: current user) |
| `-n`, `--dry-run` | Show what would be done without making changes |
| `--uninstall` | Uninstall zsh setup and revert to bash |
| `-h`, `--help` | Show help message with full plugin descriptions |

## Available Plugins

### Bundled (included with oh-my-zsh)

| Plugin | Description |
|--------|-------------|
| [git](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/git) | Git aliases and functions (`ga`, `gco`, `gp`, etc.) |
| [z](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/z) | Jump to frequently used directories by partial name |
| [extract](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/extract) | Extract any archive with a single command |
| [sudo](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/sudo) | Press ESC twice to prepend sudo to last command |
| [colored-man-pages](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/colored-man-pages) | Colorized man pages for easier reading |
| [docker](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/docker) | Docker command completions and aliases |
| [docker-compose](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/docker-compose) | Docker Compose command completions |
| [npm](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/npm) | npm command completions and aliases |
| [history-substring-search](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/history-substring-search) | Fish-like history search with arrow keys |
| [aws](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/aws) | AWS CLI command completions and aliases |
| [kubectl](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/kubectl) | Kubectl command completions and aliases |
| [kube-ps1](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/kube-ps1) | Show Kubernetes context/namespace in prompt |
| [command-not-found](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/command-not-found) | Suggest packages when a command is not found |
| [helm](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/helm) | Helm command completions and aliases |
| [terraform](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/terraform) | Terraform command completions and aliases |
| [macos](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/macos) | macOS utilities (`ofd`, `cdf`, etc.) — macOS only |

### External (cloned via git)

| Plugin | Description |
|--------|-------------|
| [fzf-tab](https://github.com/Aloxaf/fzf-tab) | Replace zsh completion menu with fzf (requires fzf) |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | Suggests commands as you type based on history |
| [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | Real-time syntax highlighting while typing |
| [you-should-use](https://github.com/MichaelAquilina/zsh-you-should-use) | Reminds you when a command has a shorter alias |

> **Note:** `fzf-tab` must load before `zsh-autosuggestions` and `zsh-syntax-highlighting`. The script handles this ordering automatically.
