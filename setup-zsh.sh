#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_VERSION="1.1.0"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

readonly OHMYZSH_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

# Bundled plugins: "name|description|os_filter"
BUNDLED_PLUGINS=(
    "git|Git aliases and functions|all"
    "z|Directory jumping by frecency|all"
    "extract|Universal archive extraction|all"
    "sudo|Press ESC twice to prepend sudo|all"
    "colored-man-pages|Colorized man pages|all"
    "docker|Docker completions and aliases|all"
    "docker-compose|Docker Compose completions|all"
    "npm|npm completions and aliases|all"
    "history-substring-search|Fish-like history search|all"
    "aws|AWS CLI completions and aliases|all"
    "kubectl|Kubectl completions and aliases|all"
    "kube-ps1|Kubernetes context/namespace in prompt|all"
    "command-not-found|Suggest packages when command not found|all"
    "helm|Helm completions and aliases|all"
    "terraform|Terraform completions and aliases|all"
    "macos|macOS-specific utilities|darwin"
)

# External plugins: "name|repo_url|description"
EXTERNAL_PLUGINS=(
    "fzf-tab|https://github.com/Aloxaf/fzf-tab.git|Replace zsh completion menu with fzf (requires fzf)"
    "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git|Fish-like autosuggestions"
    "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git|Syntax highlighting at the prompt"
    "you-should-use|https://github.com/MichaelAquilina/zsh-you-should-use.git|Reminds you of existing aliases"
)

# Globals set during execution
TARGET_USER=""
TARGET_HOME=""
OS_TYPE=""
PKG_MANAGER=""
DRY_RUN=false
UNINSTALL_MODE=false
SELECTED_PLUGINS=()

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

fatal() {
    error "$*"
    exit 1
}

run_as_user() {
    local target_user="$1"
    shift
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} (as $target_user) $*"
        return 0
    fi
    if [[ "$(whoami)" == "$target_user" ]]; then
        bash -c "$*"
    else
        sudo -H -u "$target_user" bash -c "$*"
    fi
}

run_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} $*"
        return 0
    fi
    "$@"
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Installs zsh, oh-my-zsh, and popular plugins for a specified user.

This script will:
  1. Detect your OS and package manager
  2. Install prerequisites (git, curl) if missing
  3. Install zsh (the Z shell)
  4. Install oh-my-zsh (community-driven zsh framework)
  5. Prompt you to select plugins from the list below
  6. Configure your .zshrc with selected plugins
  7. Optionally install Starship prompt (shows hostname on SSH)
  8. Set zsh as your default shell

Options:
  -u, --user <username>   Target user (default: current user)
  -n, --dry-run           Show what would be done without making changes
      --uninstall         Uninstall zsh setup and revert to bash
  -h, --help              Show this help message

Supported operating systems:
  - macOS (via Homebrew)
  - Ubuntu / Debian / Raspberry Pi OS (via apt)
  - RHEL / CentOS / Rocky / Alma / Fedora (via dnf/yum)

Available plugins (bundled with oh-my-zsh):
  git                     Git aliases and functions (ga, gco, gp, etc.)
  z                       Jump to frequently used directories by partial name
  extract                 Extract any archive with a single command
  sudo                    Press ESC twice to prepend sudo to last command
  colored-man-pages       Colorized man pages for easier reading
  docker                  Docker command completions and aliases
  docker-compose          Docker Compose command completions
  npm                     npm command completions and aliases
  history-substring-search  Fish-like history search with arrow keys
  aws                     AWS CLI command completions and aliases
  kubectl                 Kubectl command completions and aliases
  kube-ps1                Show Kubernetes context/namespace in prompt
  command-not-found       Suggest packages when a command is not found
  helm                    Helm command completions and aliases
  terraform               Terraform command completions and aliases
  macos                   macOS utilities (ofd, cdf, etc.) [macOS only]

Available plugins (external, cloned via git):
  fzf-tab                 Replace zsh completion menu with fzf (requires fzf)
  zsh-autosuggestions     Suggests commands as you type based on history
  zsh-syntax-highlighting Real-time syntax highlighting while typing
  you-should-use          Reminds you when a command has a shorter alias

Note: fzf-tab must load before zsh-autosuggestions and zsh-syntax-highlighting.
      The script handles this ordering automatically.

Uninstall mode (--uninstall):
  Reverts the setup by switching the default shell back to bash,
  removing oh-my-zsh and its plugins, and restoring any .zshrc backup.
  Does NOT remove zsh or fzf packages by default (prompted separately).

Examples:
  $(basename "$0")                  # Install for current user
  $(basename "$0") -u chris         # Install for user 'chris'
  $(basename "$0") --dry-run        # Preview what would happen
  sudo $(basename "$0") -u deploy   # Install for another user (requires root)
  $(basename "$0") --uninstall      # Uninstall and revert to bash
  $(basename "$0") --uninstall -n   # Preview what uninstall would do
EOF
}

# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--user)
                [[ -n "${2:-}" ]] || fatal "Option $1 requires a username argument"
                TARGET_USER="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --uninstall)
                UNINSTALL_MODE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fatal "Unknown option: $1 (see --help)"
                ;;
        esac
    done

    # Default to current user if not specified
    if [[ -z "$TARGET_USER" ]]; then
        read -rp "Enter target username [$(whoami)]: " TARGET_USER
        TARGET_USER="${TARGET_USER:-$(whoami)}"
    fi

    # Validate user exists
    if ! id "$TARGET_USER" &>/dev/null; then
        fatal "User '$TARGET_USER' does not exist"
    fi

    # Resolve home directory
    TARGET_HOME="$(eval echo "~$TARGET_USER")"

    # Check permissions
    if [[ "$(whoami)" != "$TARGET_USER" && "$(id -u)" -ne 0 ]]; then
        fatal "Installing for another user requires root. Run: sudo $0 --user $TARGET_USER"
    fi

    info "Target user: $TARGET_USER (home: $TARGET_HOME)"

    if [[ "$DRY_RUN" == true ]]; then
        warn "Dry-run mode enabled — no changes will be made"
    fi
}

# ---------------------------------------------------------------------------
# detect_os
# ---------------------------------------------------------------------------

detect_os() {
    case "$OSTYPE" in
        darwin*)
            OS_TYPE="macos"
            PKG_MANAGER="brew"
            ;;
        linux*)
            if [[ -f /etc/os-release ]]; then
                # shellcheck source=/dev/null
                . /etc/os-release
                case "$ID" in
                    ubuntu|debian|raspbian)
                        OS_TYPE="ubuntu"
                        PKG_MANAGER="apt"
                        ;;
                    rhel|centos|rocky|alma|fedora)
                        OS_TYPE="rhel"
                        if command -v dnf &>/dev/null; then
                            PKG_MANAGER="dnf"
                        else
                            PKG_MANAGER="yum"
                        fi
                        ;;
                    *)
                        fatal "Unsupported Linux distribution: $ID"
                        ;;
                esac
            else
                fatal "Cannot detect Linux distribution: /etc/os-release not found"
            fi
            ;;
        *)
            fatal "Unsupported operating system: $OSTYPE"
            ;;
    esac

    success "Detected OS: $OS_TYPE (package manager: $PKG_MANAGER)"
}

# ---------------------------------------------------------------------------
# check_prerequisites
# ---------------------------------------------------------------------------

check_prerequisites() {
    # On macOS, verify Homebrew is available
    if [[ "$PKG_MANAGER" == "brew" ]] && ! command -v brew &>/dev/null; then
        fatal "Homebrew is not installed. Install it first: https://brew.sh"
    fi

    local missing=()
    command -v git  &>/dev/null || missing+=(git)
    command -v curl &>/dev/null || missing+=(curl)

    if [[ ${#missing[@]} -gt 0 ]]; then
        info "Installing missing prerequisites: ${missing[*]}"
        case "$PKG_MANAGER" in
            brew) run_cmd brew install "${missing[@]}" ;;
            apt)  run_cmd sudo apt-get update -qq && run_cmd sudo apt-get install -y -qq "${missing[@]}" ;;
            yum)  run_cmd sudo yum install -y -q "${missing[@]}" ;;
            dnf)  run_cmd sudo dnf install -y -q "${missing[@]}" ;;
        esac
    fi

    success "Prerequisites satisfied (git, curl)"
}

# ---------------------------------------------------------------------------
# install_zsh
# ---------------------------------------------------------------------------

install_zsh() {
    if command -v zsh &>/dev/null; then
        success "zsh is already installed: $(zsh --version | head -1)"
        return 0
    fi

    info "Installing zsh..."
    case "$PKG_MANAGER" in
        brew) run_cmd brew install zsh ;;
        apt)  run_cmd sudo apt-get update -qq && run_cmd sudo apt-get install -y -qq zsh ;;
        yum)  run_cmd sudo yum install -y -q zsh ;;
        dnf)  run_cmd sudo dnf install -y -q zsh ;;
    esac

    if [[ "$DRY_RUN" == false ]] && ! command -v zsh &>/dev/null; then
        fatal "zsh installation failed"
    fi

    success "zsh installed: $(zsh --version | head -1)"
}

# ---------------------------------------------------------------------------
# install_ohmyzsh
# ---------------------------------------------------------------------------

install_ohmyzsh() {
    local ohmyzsh_dir="$TARGET_HOME/.oh-my-zsh"

    if [[ -d "$ohmyzsh_dir" ]]; then
        warn "oh-my-zsh is already installed at $ohmyzsh_dir"
        if [[ "$DRY_RUN" == true ]]; then
            info "Would prompt to reinstall (skipping in dry-run)"
        else
            read -rp "Reinstall? (y/N): " reinst
            if [[ "$reinst" != [yY]* ]]; then
                info "Keeping existing oh-my-zsh installation"
                return 0
            fi
            run_as_user "$TARGET_USER" "rm -rf '$ohmyzsh_dir'"
        fi
    fi

    info "Installing oh-my-zsh for user '$TARGET_USER'..."
    run_as_user "$TARGET_USER" \
        "export RUNZSH=no CHSH=no KEEP_ZSHRC=yes; sh -c \"\$(curl -fsSL $OHMYZSH_INSTALL_URL)\" \"\" --unattended"

    if [[ "$DRY_RUN" == false && ! -d "$ohmyzsh_dir" ]]; then
        fatal "oh-my-zsh installation failed"
    fi

    success "oh-my-zsh installed at $ohmyzsh_dir"
}

# ---------------------------------------------------------------------------
# prompt_plugins
# ---------------------------------------------------------------------------

prompt_plugins() {
    SELECTED_PLUGINS=()
    local index=1
    local plugin_map=()

    echo ""
    echo -e "${BOLD}=== Plugin Selection ===${NC}"
    echo ""

    # Bundled plugins
    echo -e "${BOLD}Bundled plugins (included with oh-my-zsh):${NC}"
    for entry in "${BUNDLED_PLUGINS[@]}"; do
        IFS='|' read -r name desc os_filter <<< "$entry"
        if [[ "$os_filter" == "darwin" && "$OS_TYPE" != "macos" ]]; then
            continue
        fi
        printf "  %2d) %-30s %s\n" "$index" "$name" "$desc"
        plugin_map+=("bundled|$name|")
        ((index++))
    done

    echo ""
    echo -e "${BOLD}External plugins (will be cloned via git):${NC}"
    for entry in "${EXTERNAL_PLUGINS[@]}"; do
        IFS='|' read -r name repo desc <<< "$entry"
        printf "  %2d) %-30s %s\n" "$index" "$name" "$desc"
        plugin_map+=("external|$name|$repo")
        ((index++))
    done

    echo ""
    echo -e "Enter plugin numbers separated by spaces, ${BOLD}'all'${NC} for everything, or ${BOLD}'none'${NC} to skip."
    read -rp "Selection [all]: " selection
    selection="${selection:-all}"

    if [[ "$selection" == "none" ]]; then
        SELECTED_PLUGINS=("bundled|git|")
        info "Only the 'git' plugin will be enabled"
        return
    fi

    if [[ "$selection" == "all" ]]; then
        SELECTED_PLUGINS=("${plugin_map[@]}")
        info "All plugins selected"
        return
    fi

    # Parse space-separated numbers
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]]; then
            local idx=$((num - 1))
            if [[ $idx -ge 0 && $idx -lt ${#plugin_map[@]} ]]; then
                SELECTED_PLUGINS+=("${plugin_map[$idx]}")
            else
                warn "Ignoring invalid selection: $num"
            fi
        else
            warn "Ignoring non-numeric input: $num"
        fi
    done

    # Always include git
    local has_git=false
    for entry in "${SELECTED_PLUGINS[@]}"; do
        IFS='|' read -r _ pname _ <<< "$entry"
        if [[ "$pname" == "git" ]]; then
            has_git=true
            break
        fi
    done
    if [[ "$has_git" == false ]]; then
        SELECTED_PLUGINS=("bundled|git|" "${SELECTED_PLUGINS[@]}")
        info "Auto-added 'git' plugin (always recommended)"
    fi

    # Show summary
    local names=()
    for entry in "${SELECTED_PLUGINS[@]}"; do
        IFS='|' read -r _ pname _ <<< "$entry"
        names+=("$pname")
    done
    info "Selected plugins: ${names[*]}"
}

# ---------------------------------------------------------------------------
# install_external_plugin
# ---------------------------------------------------------------------------

install_external_plugin() {
    local name="$1"
    local repo_url="$2"
    local plugin_dir="$TARGET_HOME/.oh-my-zsh/custom/plugins/$name"

    # fzf-tab requires fzf to be installed
    if [[ "$name" == "fzf-tab" ]] && ! command -v fzf &>/dev/null; then
        info "Installing fzf (required by fzf-tab)..."
        case "$PKG_MANAGER" in
            brew) run_cmd brew install fzf ;;
            apt)  run_cmd sudo apt-get install -y -qq fzf ;;
            yum)  run_cmd sudo yum install -y -q fzf ;;
            dnf)  run_cmd sudo dnf install -y -q fzf ;;
        esac
    fi

    if [[ -d "$plugin_dir" ]]; then
        info "External plugin '$name' already exists, updating..."
        run_as_user "$TARGET_USER" "cd '$plugin_dir' && git pull --quiet"
    else
        info "Cloning external plugin '$name'..."
        run_as_user "$TARGET_USER" "git clone --depth=1 '$repo_url' '$plugin_dir'"
    fi
}

# ---------------------------------------------------------------------------
# configure_plugins
# ---------------------------------------------------------------------------

configure_plugins() {
    local zshrc="$TARGET_HOME/.zshrc"
    local plugin_names=()

    for entry in "${SELECTED_PLUGINS[@]}"; do
        IFS='|' read -r ptype pname prepo <<< "$entry"
        if [[ "$ptype" == "external" ]]; then
            install_external_plugin "$pname" "$prepo"
        fi
        plugin_names+=("$pname")
    done

    # Build the plugins line
    local plugins_line="plugins=(${plugin_names[*]})"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would set in .zshrc: $plugins_line"
        success "Would configure plugins: ${plugin_names[*]}"
        return 0
    fi

    if [[ ! -f "$zshrc" ]]; then
        fatal ".zshrc not found at $zshrc after oh-my-zsh install"
    fi

    # Back up existing .zshrc
    local backup
    backup="${zshrc}.bak.$(date +%Y%m%d%H%M%S)"
    run_as_user "$TARGET_USER" "cp '$zshrc' '$backup'"
    info "Backed up .zshrc to $backup"

    # Replace or append plugins line
    if grep -q '^plugins=' "$zshrc"; then
        sed -i.tmp "s/^plugins=(.*)/$plugins_line/" "$zshrc"
        rm -f "${zshrc}.tmp"
    else
        echo "$plugins_line" >> "$zshrc"
    fi

    success "Configured plugins in $zshrc: ${plugin_names[*]}"
}

# ---------------------------------------------------------------------------
# set_default_shell
# ---------------------------------------------------------------------------

set_default_shell() {
    local zsh_path
    zsh_path="$(command -v zsh || true)"

    if [[ -z "$zsh_path" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            zsh_path="/usr/bin/zsh"
            info "zsh not found; assuming $zsh_path for dry run"
        else
            fatal "zsh not found in PATH"
        fi
    fi

    # Get current shell for target user
    local current_shell=""
    if [[ "$OS_TYPE" == "macos" ]]; then
        current_shell="$(dscl . -read "/Users/$TARGET_USER" UserShell 2>/dev/null | awk '{print $2}' || true)"
    else
        current_shell="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7 || true)"
    fi

    if [[ "$current_shell" == "$zsh_path" ]]; then
        success "zsh is already the default shell for '$TARGET_USER'"
        return 0
    fi

    # Ensure zsh is in /etc/shells
    if [[ -f /etc/shells ]] && ! grep -qx "$zsh_path" /etc/shells; then
        info "Adding $zsh_path to /etc/shells"
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${YELLOW}[DRY RUN]${NC} echo '$zsh_path' >> /etc/shells"
        else
            echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        fi
    fi

    info "Setting default shell to zsh for '$TARGET_USER'..."
    if [[ "$(whoami)" == "$TARGET_USER" ]]; then
        run_cmd chsh -s "$zsh_path"
    else
        run_cmd sudo chsh -s "$zsh_path" "$TARGET_USER"
    fi

    success "Default shell set to $zsh_path for '$TARGET_USER'"
}

# ---------------------------------------------------------------------------
# install_starship
# ---------------------------------------------------------------------------

install_starship() {
    echo ""
    echo -e "${BOLD}=== Starship Prompt ===${NC}"
    echo ""
    info "Starship is a modern cross-shell prompt that shows hostname"
    info "automatically when SSH'd into a remote host."
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would prompt to install Starship"
    else
        read -rp "Install Starship prompt? (Y/n): " install_star
        if [[ "$install_star" == [nN]* ]]; then
            info "Skipping Starship installation"
            return 0
        fi
    fi

    # Install starship binary
    if command -v starship &>/dev/null; then
        success "Starship is already installed: $(starship --version | head -1)"
    else
        info "Installing Starship..."
        case "$PKG_MANAGER" in
            brew) run_cmd brew install starship ;;
            *)
                # Use the official installer for Linux distros
                if [[ "$DRY_RUN" == true ]]; then
                    echo -e "${YELLOW}[DRY RUN]${NC} curl -sS https://starship.rs/install.sh | sh -s -- -y"
                else
                    curl -sS https://starship.rs/install.sh | sh -s -- -y
                fi
                ;;
        esac

        if [[ "$DRY_RUN" == false ]] && ! command -v starship &>/dev/null; then
            warn "Starship installation failed — skipping configuration"
            return 0
        fi
        success "Starship installed"
    fi

    # Configure .zshrc for Starship
    local zshrc="$TARGET_HOME/.zshrc"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would set ZSH_THEME=\"\" in $zshrc"
        echo -e "${YELLOW}[DRY RUN]${NC} Would append 'eval \"\$(starship init zsh)\"' to $zshrc"
        echo -e "${YELLOW}[DRY RUN]${NC} Would create config at $TARGET_HOME/.config/starship.toml"
        success "Would configure Starship in $zshrc"
        return 0
    fi

    if [[ ! -f "$zshrc" ]]; then
        warn ".zshrc not found at $zshrc — skipping Starship configuration"
        return 0
    fi

    # Disable oh-my-zsh theme (Starship replaces it)
    if grep -q '^ZSH_THEME=' "$zshrc"; then
        sed -i.tmp 's/^ZSH_THEME=.*/ZSH_THEME=""/' "$zshrc"
        rm -f "${zshrc}.tmp"
        info "Set ZSH_THEME=\"\" (Starship replaces the oh-my-zsh theme)"
    fi

    # Add starship init at the end of .zshrc (if not already present)
    if ! grep -q 'starship init zsh' "$zshrc"; then
        {
            echo ''
            echo '# Starship prompt (shows hostname on SSH automatically)'
            # shellcheck disable=SC2016
            echo 'eval "$(starship init zsh)"'
        } >> "$zshrc"
        success "Added Starship init to $zshrc"
    else
        success "Starship init already present in $zshrc"
    fi

    # Create default starship.toml config
    local config_dir="$TARGET_HOME/.config"
    local config_file="$config_dir/starship.toml"

    run_as_user "$TARGET_USER" "mkdir -p '$config_dir'"

    if [[ -f "$config_file" ]]; then
        info "Starship config already exists at $config_file — not overwriting"
    else
        cat > "$config_file" << 'STARSHIP_EOF'
# Starship prompt configuration
# See: https://starship.rs/config/

# Prompt format — show git info prominently
format = """
$hostname\
$directory\
$git_branch\
$git_status\
$kubernetes\
$terraform\
$docker_context\
$line_break\
$character"""

# Only show hostname when SSH'd into a remote host
[hostname]
ssh_only = true
format = "[$hostname](bold yellow) "
trim_at = "."

# Git branch
[git_branch]
format = "[$symbol$branch(:$remote_branch)]($style) "

# Git status — show modified, staged, untracked counts
[git_status]
format = '([$all_status$ahead_behind]($style) )'

# Directory — show up to 3 levels deep
[directory]
truncation_length = 3

# AWS — only show when explicitly set via AWS_PROFILE env var
[aws]
format = '[$symbol($profile)(\($region\))]($style) '
disabled = true

# Kubernetes — only show when a kubeconfig is active
[kubernetes]
disabled = false
format = '[$symbol$context(\($namespace\))]($style) '
detect_files = []

# Docker — only show inside Docker projects
[docker_context]
disabled = false

# Terraform — only show in directories with .tf files
[terraform]
disabled = false
STARSHIP_EOF
        chown "$(id -u "$TARGET_USER"):$(id -g "$TARGET_USER")" "$config_file" 2>/dev/null || true
        success "Created Starship config at $config_file"
    fi
}

# ---------------------------------------------------------------------------
# Uninstall functions
# ---------------------------------------------------------------------------

confirm_uninstall() {
    if [[ "$DRY_RUN" == true ]]; then
        warn "Dry-run mode: showing what uninstall would do"
        return 0
    fi

    echo ""
    warn "This will remove oh-my-zsh, its plugins, and revert '$TARGET_USER' to bash."
    read -rp "Are you sure you want to proceed? (y/N): " confirm
    if [[ "$confirm" != [yY]* ]]; then
        info "Uninstall cancelled."
        exit 0
    fi
}

uninstall_default_shell() {
    local bash_path="/bin/bash"

    # Get current shell for target user
    local current_shell=""
    if [[ "$OS_TYPE" == "macos" ]]; then
        current_shell="$(dscl . -read "/Users/$TARGET_USER" UserShell 2>/dev/null | awk '{print $2}' || true)"
    else
        current_shell="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7 || true)"
    fi

    if [[ "$current_shell" == "$bash_path" ]]; then
        success "Default shell is already bash for '$TARGET_USER'"
        return 0
    fi

    info "Changing default shell to $bash_path for '$TARGET_USER'..."
    if [[ "$(whoami)" == "$TARGET_USER" ]]; then
        run_cmd chsh -s "$bash_path"
    else
        run_cmd sudo chsh -s "$bash_path" "$TARGET_USER"
    fi

    success "Default shell changed to $bash_path for '$TARGET_USER'"
}

uninstall_ohmyzsh() {
    local ohmyzsh_dir="$TARGET_HOME/.oh-my-zsh"

    if [[ "$DRY_RUN" == false && ! -d "$ohmyzsh_dir" ]]; then
        info "oh-my-zsh directory not found at $ohmyzsh_dir, nothing to remove"
        return 0
    fi

    info "Removing oh-my-zsh directory: $ohmyzsh_dir"
    run_as_user "$TARGET_USER" "rm -rf '$ohmyzsh_dir'"
    success "Removed $ohmyzsh_dir (including all external plugins)"
}

uninstall_zshrc() {
    local zshrc="$TARGET_HOME/.zshrc"

    if [[ "$DRY_RUN" == false && ! -f "$zshrc" ]]; then
        info "No .zshrc found at $zshrc, nothing to restore"
        return 0
    fi

    # Find the most recent .zshrc backup (filenames are .zshrc.bak.YYYYMMDDHHMMSS)
    local latest_backup=""
    local -a backups=()
    while IFS= read -r -d '' f; do
        backups+=("$f")
    done < <(find "$TARGET_HOME" -maxdepth 1 -name '.zshrc.bak.*' -print0 2>/dev/null)
    if [[ ${#backups[@]} -gt 0 ]]; then
        IFS=$'\n' read -r latest_backup < <(printf '%s\n' "${backups[@]}" | sort -r | head -1)
    fi

    if [[ -n "$latest_backup" ]]; then
        info "Found .zshrc backup: $latest_backup"
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${YELLOW}[DRY RUN]${NC} Would restore $latest_backup -> $zshrc"
            return 0
        fi
        read -rp "Restore .zshrc from backup? (Y/n): " restore
        if [[ "$restore" != [nN]* ]]; then
            run_as_user "$TARGET_USER" "cp '$latest_backup' '$zshrc'"
            success "Restored .zshrc from $latest_backup"
        else
            run_as_user "$TARGET_USER" "rm -f '$zshrc'"
            success "Removed $zshrc (backup preserved at $latest_backup)"
        fi
    else
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${YELLOW}[DRY RUN]${NC} Would remove $zshrc (no backup found)"
            return 0
        fi
        info "No .zshrc backup found; removing oh-my-zsh-generated .zshrc"
        run_as_user "$TARGET_USER" "rm -f '$zshrc'"
        success "Removed $zshrc"
    fi
}

uninstall_starship() {
    if ! command -v starship &>/dev/null; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would prompt to uninstall Starship"
        return 0
    fi

    warn "Starship prompt is installed"
    read -rp "Uninstall Starship? (y/N): " remove_star
    if [[ "$remove_star" == [yY]* ]]; then
        info "Removing Starship..."
        case "$PKG_MANAGER" in
            brew) run_cmd brew uninstall starship ;;
            *)
                # The official installer puts the binary in /usr/local/bin
                if [[ -f /usr/local/bin/starship ]]; then
                    run_cmd sudo rm -f /usr/local/bin/starship
                fi
                ;;
        esac
        success "Starship removed"
    else
        info "Keeping Starship installed"
    fi

    # Remove starship config if it exists
    local starship_config="$TARGET_HOME/.config/starship.toml"
    if [[ -f "$starship_config" ]]; then
        run_as_user "$TARGET_USER" "rm -f '$starship_config'"
        info "Removed $starship_config"
    fi
}

uninstall_packages() {
    # Warn about /etc/shells entry
    local zsh_path
    zsh_path="$(command -v zsh 2>/dev/null || true)"
    if [[ -n "$zsh_path" && -f /etc/shells ]] && grep -qx "$zsh_path" /etc/shells; then
        warn "$zsh_path is listed in /etc/shells"
        warn "Skipping removal — other users may depend on this entry."
        info "To remove manually: sudo sed -i.tmp '\\|^${zsh_path}\$|d' /etc/shells"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would prompt to optionally uninstall fzf and zsh packages"
        return 0
    fi

    # Optionally uninstall fzf
    if command -v fzf &>/dev/null; then
        warn "fzf is still installed (may have been installed for fzf-tab plugin)"
        read -rp "Uninstall fzf? (y/N): " remove_fzf
        if [[ "$remove_fzf" == [yY]* ]]; then
            info "Removing fzf..."
            case "$PKG_MANAGER" in
                brew) run_cmd brew uninstall fzf ;;
                apt)  run_cmd sudo apt-get remove -y fzf ;;
                yum)  run_cmd sudo yum remove -y fzf ;;
                dnf)  run_cmd sudo dnf remove -y fzf ;;
            esac
            success "fzf removed"
        else
            info "Keeping fzf installed"
        fi
    fi

    # Optionally uninstall zsh
    if command -v zsh &>/dev/null; then
        warn "zsh is still installed on the system"
        warn "Other users or scripts may depend on zsh. Only remove if you are certain."
        read -rp "Uninstall zsh? (y/N): " remove_zsh
        if [[ "$remove_zsh" == [yY]* ]]; then
            info "Removing zsh..."
            case "$PKG_MANAGER" in
                brew) run_cmd brew uninstall zsh ;;
                apt)  run_cmd sudo apt-get remove -y zsh ;;
                yum)  run_cmd sudo yum remove -y zsh ;;
                dnf)  run_cmd sudo dnf remove -y zsh ;;
            esac
            success "zsh removed"
        else
            info "Keeping zsh installed"
        fi
    fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
    echo -e "${BOLD}zsh + oh-my-zsh Setup Script v${SCRIPT_VERSION}${NC}"
    echo "============================================"
    echo ""

    parse_args "$@"
    detect_os

    if [[ "$UNINSTALL_MODE" == true ]]; then
        confirm_uninstall
        uninstall_default_shell
        uninstall_ohmyzsh
        uninstall_zshrc
        uninstall_starship
        uninstall_packages

        echo ""
        echo "============================================"
        success "Uninstall complete for user '$TARGET_USER'!"
        info "Log out and back in to return to bash."
        echo "============================================"
    else
        check_prerequisites
        install_zsh
        install_ohmyzsh
        prompt_plugins
        configure_plugins
        install_starship
        set_default_shell

        echo ""
        echo "============================================"
        success "Setup complete for user '$TARGET_USER'!"
        info "Log out and back in, or run: exec zsh"
        echo "============================================"
    fi
}

main "$@"
