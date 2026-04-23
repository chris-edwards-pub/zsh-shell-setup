#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_VERSION="0.1.0"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

readonly BASH_IT_REPO_URL="https://github.com/Bash-it/bash-it.git"
readonly KUBE_PS1_REPO_URL="https://github.com/jonmosco/kube-ps1.git"
readonly KUBECTX_REPO_URL="https://github.com/ahmetb/kubectx.git"

# Candidate components: "type|name|description|os_filter"
# type: alias, completion, plugin
COMPONENT_CANDIDATES=(
    "alias|general|Useful everyday aliases|all"
    "alias|git|Git aliases and helpers|all"
    "alias|docker|Docker aliases|all"
    "alias|kubectl|kubectl aliases (k, kgp, kgn, etc.)|all"
    "alias|homebrew|Homebrew aliases|darwin"
    "alias|apt|APT aliases|linux"
    "completion|bash-it|Core Bash-it completion helpers|all"
    "completion|git|Git completion|all"
    "completion|ssh|SSH completion|all"
    "completion|docker|Docker completion|all"
    "completion|kubectl|kubectl tab completion|all"
    "completion|helm|Helm tab completion|all"
    "completion|system|System service completion|linux"
    "plugin|base|Core Bash-it features|all"
    "plugin|dirs|Directory navigation helpers|all"
    "plugin|history|History helpers|all"
    "plugin|alias-completion|Tab-complete aliases|all"
)

# External repos selected during prompt_components
INSTALL_KUBE_PS1=false
INSTALL_KUBECTX=false

TARGET_USER=""
TARGET_HOME=""
OS_TYPE=""
PKG_MANAGER=""
DRY_RUN=false
UNINSTALL_MODE=false

AVAILABLE_COMPONENTS=()
SELECTED_COMPONENTS=()

# External components presented alongside bash-it components in the menu
EXTERNAL_CANDIDATES=(
    "external|kube-ps1|Kubernetes context/namespace in prompt (kubeon/kubeoff)|all"
    "external|kubectx|Fast context (kubectx) and namespace (kubens) switcher|all"
)

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

fatal() {
    error "$*"
    exit 1
}

run_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} $*"
        return 0
    fi
    "$@"
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

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Installs and configures a Bash shell environment with Bash-it and selectable components.

This script will:
  1. Detect your OS and package manager
  2. Install prerequisites (git, curl)
  3. Ensure bash is installed
  4. Install Bash-it for the target user
  5. Prompt you to select aliases/completions/plugins
  6. Configure .bashrc (managed block)
  7. Add SSH hostname detection to your prompt
  8. Set bash as your default shell

Options:
  -u, --user <username>   Target user (default: current user)
  -n, --dry-run           Show what would happen without making changes
      --uninstall         Remove Bash-it setup and managed .bashrc block
  -h, --help              Show this help message

Supported operating systems:
  - macOS (via Homebrew)
  - Ubuntu / Debian / Raspberry Pi OS (via apt)
  - RHEL / CentOS / Rocky / Alma / Fedora (via dnf/yum)

Examples:
  $(basename "$0")
  $(basename "$0") --user chris
  $(basename "$0") --dry-run
  sudo $(basename "$0") --user deploy
  $(basename "$0") --uninstall
EOF
}

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

    if [[ -z "$TARGET_USER" ]]; then
        TARGET_USER="$(whoami)"
    fi

    if ! id "$TARGET_USER" &>/dev/null; then
        fatal "User '$TARGET_USER' does not exist"
    fi

    TARGET_HOME="$(eval echo "~$TARGET_USER")"

    if [[ "$(whoami)" != "$TARGET_USER" && "$(id -u)" -ne 0 ]]; then
        fatal "Installing for another user requires root. Run: sudo $0 --user $TARGET_USER"
    fi

    info "Target user: $TARGET_USER (home: $TARGET_HOME)"
    if [[ "$DRY_RUN" == true ]]; then
        warn "Dry-run mode enabled - no changes will be made"
    fi
}

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

install_prerequisites() {
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

install_bash() {
    if command -v bash &>/dev/null; then
        success "bash is already installed: $(bash --version | head -1)"
        return 0
    fi

    info "Installing bash"
    case "$PKG_MANAGER" in
        brew) run_cmd brew install bash ;;
        apt)  run_cmd sudo apt-get update -qq && run_cmd sudo apt-get install -y -qq bash ;;
        yum)  run_cmd sudo yum install -y -q bash ;;
        dnf)  run_cmd sudo dnf install -y -q bash ;;
    esac

    if [[ "$DRY_RUN" == false ]] && ! command -v bash &>/dev/null; then
        fatal "bash installation failed"
    fi

    success "bash installed"
}

install_bash_completion() {
    if command -v brew &>/dev/null && brew list bash-completion@2 &>/dev/null; then
        success "bash-completion@2 already installed"
        return 0
    fi

    if [[ -f /usr/share/bash-completion/bash_completion ]] || [[ -f /etc/bash_completion ]]; then
        success "bash completion already available"
        return 0
    fi

    info "Installing bash completion package"
    case "$PKG_MANAGER" in
        brew) run_cmd brew install bash-completion@2 ;;
        apt)  run_cmd sudo apt-get install -y -qq bash-completion ;;
        yum)  run_cmd sudo yum install -y -q bash-completion ;;
        dnf)  run_cmd sudo dnf install -y -q bash-completion ;;
    esac

    success "bash completion package installed"
}

install_bash_it() {
    local bash_it_dir="$TARGET_HOME/.bash_it"

    if [[ -d "$bash_it_dir" ]]; then
        warn "Bash-it already exists at $bash_it_dir"
        if [[ "$DRY_RUN" == true ]]; then
            info "Would prompt to reinstall (skipping in dry-run)"
            return 0
        fi

        read -rp "Reinstall Bash-it? (y/N): " reinstall
        if [[ "$reinstall" == [yY]* ]]; then
            run_as_user "$TARGET_USER" "rm -rf '$bash_it_dir'"
        else
            info "Keeping existing Bash-it installation"
            return 0
        fi
    fi

    info "Installing Bash-it for user '$TARGET_USER'"
    run_as_user "$TARGET_USER" "git clone --depth=1 '$BASH_IT_REPO_URL' '$bash_it_dir'"

    if [[ "$DRY_RUN" == false && ! -d "$bash_it_dir" ]]; then
        fatal "Bash-it installation failed"
    fi

    success "Bash-it installed at $bash_it_dir"
}

component_exists() {
    local ctype="$1"
    local cname="$2"
    local base_dir="$TARGET_HOME/.bash_it"

    case "$ctype" in
        alias)
            [[ -f "$base_dir/aliases/available/${cname}.aliases.bash" ]]
            ;;
        completion)
            [[ -f "$base_dir/completion/available/${cname}.completion.bash" ]]
            ;;
        plugin)
            [[ -f "$base_dir/plugins/available/${cname}.plugin.bash" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

build_component_catalog() {
    AVAILABLE_COMPONENTS=()

    local entry=""
    local ctype=""
    local cname=""
    local cdesc=""
    local os_filter=""

    for entry in "${COMPONENT_CANDIDATES[@]}"; do
        IFS='|' read -r ctype cname cdesc os_filter <<< "$entry"

        if [[ "$os_filter" == "darwin" && "$OS_TYPE" != "macos" ]]; then
            continue
        fi
        if [[ "$os_filter" == "linux" && "$OS_TYPE" == "macos" ]]; then
            continue
        fi

        if [[ "$DRY_RUN" == true ]] || component_exists "$ctype" "$cname"; then
            AVAILABLE_COMPONENTS+=("$entry")
        fi
    done

    # Always append external candidates (os filter only)
    for entry in "${EXTERNAL_CANDIDATES[@]}"; do
        IFS='|' read -r ctype cname cdesc os_filter <<< "$entry"
        if [[ "$os_filter" == "darwin" && "$OS_TYPE" != "macos" ]]; then
            continue
        fi
        if [[ "$os_filter" == "linux" && "$OS_TYPE" == "macos" ]]; then
            continue
        fi
        AVAILABLE_COMPONENTS+=("$entry")
    done

    if [[ ${#AVAILABLE_COMPONENTS[@]} -eq 0 ]]; then
        fatal "No Bash-it components available to select"
    fi
}

prompt_components() {
    SELECTED_COMPONENTS=()
    build_component_catalog

    echo ""
    echo -e "${BOLD}=== Bash-it Component Selection ===${NC}"
    echo ""

    local idx=1
    local entry=""
    local ctype=""
    local cname=""
    local cdesc=""
    local _os=""

    for entry in "${AVAILABLE_COMPONENTS[@]}"; do
        IFS='|' read -r ctype cname cdesc _os <<< "$entry"
        printf "  %2d) %-12s %-24s %s\n" "$idx" "$ctype" "$cname" "$cdesc"
        ((idx++))
    done

    echo ""
    echo -e "Enter numbers separated by spaces, ${BOLD}all${NC}, or ${BOLD}none${NC}."
    read -rp "Selection [all]: " selection
    selection="${selection:-all}"

    if [[ "$selection" == "none" ]]; then
        SELECTED_COMPONENTS=("plugin|base|Core Bash-it features|all")
        info "Only plugin 'base' will be enabled"
        return
    fi

    if [[ "$selection" == "all" ]]; then
        SELECTED_COMPONENTS=("${AVAILABLE_COMPONENTS[@]}")
    else
        local token=""
        for token in $selection; do
            if [[ "$token" =~ ^[0-9]+$ ]]; then
                local array_idx=$((token - 1))
                if [[ $array_idx -ge 0 && $array_idx -lt ${#AVAILABLE_COMPONENTS[@]} ]]; then
                    SELECTED_COMPONENTS+=("${AVAILABLE_COMPONENTS[$array_idx]}")
                else
                    warn "Ignoring invalid selection: $token"
                fi
            else
                warn "Ignoring non-numeric input: $token"
            fi
        done
    fi

    # Always include plugin base.
    local has_base=false
    for entry in "${SELECTED_COMPONENTS[@]}"; do
        IFS='|' read -r ctype cname _cdesc _os <<< "$entry"
        if [[ "$ctype" == "plugin" && "$cname" == "base" ]]; then
            has_base=true
            break
        fi
    done
    if [[ "$has_base" == false ]]; then
        SELECTED_COMPONENTS=("plugin|base|Core Bash-it features|all" "${SELECTED_COMPONENTS[@]}")
        info "Auto-added plugin 'base'"
    fi

    # Extract external flags and strip them from SELECTED_COMPONENTS
    INSTALL_KUBE_PS1=false
    INSTALL_KUBECTX=false
    local filtered=()
    for entry in "${SELECTED_COMPONENTS[@]}"; do
        IFS='|' read -r ctype cname _cdesc _os <<< "$entry"
        if [[ "$ctype" == "external" && "$cname" == "kube-ps1" ]]; then
            INSTALL_KUBE_PS1=true
        elif [[ "$ctype" == "external" && "$cname" == "kubectx" ]]; then
            INSTALL_KUBECTX=true
        else
            filtered+=("$entry")
        fi
    done
    SELECTED_COMPONENTS=("${filtered[@]}")

    local summary=()
    for entry in "${SELECTED_COMPONENTS[@]}"; do
        IFS='|' read -r ctype cname _cdesc _os <<< "$entry"
        summary+=("${ctype}:${cname}")
    done
    [[ "$INSTALL_KUBE_PS1" == true ]] && summary+=("external:kube-ps1")
    [[ "$INSTALL_KUBECTX" == true ]] && summary+=("external:kubectx/kubens")
    info "Selected components: ${summary[*]}"
}

build_managed_block() {
    local aliases=""
    local completions=""
    local plugins=""

    local entry=""
    local ctype=""
    local cname=""
    local _desc=""
    local _os=""

    for entry in "${SELECTED_COMPONENTS[@]}"; do
        IFS='|' read -r ctype cname _desc _os <<< "$entry"
        case "$ctype" in
            alias)
                aliases+="${cname} "
                ;;
            completion)
                completions+="${cname} "
                ;;
            plugin)
                plugins+="${cname} "
                ;;
        esac
    done

    local kube_ps1_block=""
    if [[ "$INSTALL_KUBE_PS1" == true ]]; then
        kube_ps1_block=$'\n# kube-ps1: Kubernetes context/namespace in prompt (kubeon/kubeoff to toggle)\nKUBE_PS1_DIR="$HOME/.kube-ps1"\nif [[ -f "$KUBE_PS1_DIR/kube-ps1.sh" ]]; then\n  source "$KUBE_PS1_DIR/kube-ps1.sh"\n  PS1=\'$(kube_ps1) \'"$PS1"\nfi'
    fi

    local kubectx_block=""
    if [[ "$INSTALL_KUBECTX" == true ]]; then
        kubectx_block=$'\n# kubectx/kubens: fast context and namespace switching\nKUBECTX_DIR="$HOME/.kubectx"\nif [[ -d "$KUBECTX_DIR" ]]; then\n  export PATH="$KUBECTX_DIR:$PATH"\nfi'
    fi

    cat <<EOF
# >>> setup-bash.sh >>>
# Managed by setup-bash.sh. Changes in this block may be overwritten.
export BASH_IT="\$HOME/.bash_it"
export BASH_IT_THEME='barbuk'
# BarbUk prompt segments — ansible removed (shows /etc/ansible/ansible.cfg on systems
# where Ansible is installed system-wide, which is just noise on a managed host).
# git-upstream-remote-logo removed — requires a Nerd Font to render correctly;
# without one it shows a garbled glyph in the terminal.
# Full segment list: git-upstream-remote-logo ssh path scm python_venv uv ruby node
#                   bun docker pre_commit terraform mysql ansible cloud duration exit
export BARBUK_PROMPT="ssh path scm docker terraform cloud duration exit"
# Show short hostname instead of in SSH prompt.
export BARBUK_HOST_INFO="short"

bash_it_aliases=( ${aliases} )
bash_it_completions=( ${completions} )
bash_it_plugins=( ${plugins} )

if [[ -f "\$BASH_IT/bash_it.sh" ]]; then
  source "\$BASH_IT/bash_it.sh"
fi

# Shorten the prompt path to show only the current directory name (\W = basename,
# ~ for home) instead of the full path (\w = full path).
# BarbUk renders the path via __path_prompt() which hardcodes \w.  We re-declare
# the function here (after bash-it loads) to swap \w for \W without touching the
# theme file itself, so theme updates won't silently revert this.
# If this stops working after a bash-it update, check __path_prompt() in
# ~/.bash_it/themes/barbuk/barbuk.theme.bash and verify it still uses \w.
if declare -f __path_prompt > /dev/null 2>&1; then
  eval "\$(declare -f __path_prompt | sed 's/\\\\w/\\\\W/g')"
fi
${kube_ps1_block}
${kubectx_block}
# Show hostname in yellow when connected via SSH.
if [[ -n "\$SSH_CLIENT" || -n "\$SSH_TTY" ]]; then
  PS1='\[\e[1;33m\]\h\[\e[0m\] '"\$PS1"
fi
# <<< setup-bash.sh <<<
EOF
}

strip_managed_block() {
    local file_path="$1"
    local tmp_path="$2"

    local in_block=false
    local line=""

    : > "$tmp_path"

    if [[ -f "$file_path" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == "# >>> setup-bash.sh >>>" ]]; then
                in_block=true
                continue
            fi
            if [[ "$line" == "# <<< setup-bash.sh <<<" ]]; then
                in_block=false
                continue
            fi
            if [[ "$in_block" == false ]]; then
                printf '%s\n' "$line" >> "$tmp_path"
            fi
        done < "$file_path"
    fi
}

backup_and_fix_owner() {
    local file_path="$1"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} cp '$file_path' '${file_path}.bak.<timestamp>'"
        return 0
    fi

    if [[ -f "$file_path" ]]; then
        local backup="${file_path}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$file_path" "$backup"
        success "Backed up $file_path to $backup"
    fi

    if [[ "$(id -u)" -eq 0 ]]; then
        local target_group
        target_group="$(id -gn "$TARGET_USER")"
        chown "$TARGET_USER:$target_group" "$file_path" 2>/dev/null || true
    fi
}

configure_bashrc() {
    local bashrc="$TARGET_HOME/.bashrc"
    local tmpfile
    tmpfile="$(mktemp)"

    strip_managed_block "$bashrc" "$tmpfile"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would update managed block in $bashrc"
        rm -f "$tmpfile"
        return 0
    fi

    local block
    block="$(build_managed_block)"

    # Ensure trailing newline before appending block.
    if [[ -s "$tmpfile" ]]; then
        printf '\n' >> "$tmpfile"
    fi
    printf '%s\n' "$block" >> "$tmpfile"

    if [[ -f "$bashrc" ]]; then
        backup_and_fix_owner "$bashrc"
    fi

    mv "$tmpfile" "$bashrc"

    if [[ "$(id -u)" -eq 0 ]]; then
        local target_group
        target_group="$(id -gn "$TARGET_USER")"
        chown "$TARGET_USER:$target_group" "$bashrc" 2>/dev/null || true
    fi

    success "Configured managed Bash-it block in $bashrc"
}

set_default_shell() {
    local bash_path
    bash_path="$(command -v bash || true)"

    if [[ -z "$bash_path" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            bash_path="/bin/bash"
            info "bash not found; assuming $bash_path for dry-run"
        else
            fatal "bash not found in PATH"
        fi
    fi

    local current_shell=""
    if [[ "$OS_TYPE" == "macos" ]]; then
        current_shell="$(dscl . -read "/Users/$TARGET_USER" UserShell 2>/dev/null | awk '{print $2}' || true)"
    else
        # getent passwd may return a different path than command -v bash on SSSD/AD
        # systems (e.g. /bin/bash vs /usr/bin/bash).  Also fall back to $SHELL for
        # the current user so we don't prompt unnecessarily when already in bash.
        current_shell="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7 || true)"
        if [[ -z "$current_shell" && "$(whoami)" == "$TARGET_USER" ]]; then
            current_shell="$SHELL"
        fi
    fi

    # Resolve symlinks on both sides before comparing so /bin/bash == /usr/bin/bash
    # on systems where one is a symlink to the other (common on RHEL with usrmerge).
    local current_shell_real bash_path_real
    current_shell_real="$(readlink -f "$current_shell" 2>/dev/null || echo "$current_shell")"
    bash_path_real="$(readlink -f "$bash_path" 2>/dev/null || echo "$bash_path")"

    if [[ "$current_shell_real" == "$bash_path_real" ]]; then
        success "bash is already the default shell for '$TARGET_USER'"
        return 0
    fi

    if [[ -f /etc/shells ]] && ! grep -qx "$bash_path" /etc/shells; then
        info "Adding $bash_path to /etc/shells"
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${YELLOW}[DRY RUN]${NC} echo '$bash_path' >> /etc/shells"
        else
            echo "$bash_path" | sudo tee -a /etc/shells >/dev/null
        fi
    fi

    info "Setting default shell to bash for '$TARGET_USER'"
    if [[ "$(whoami)" == "$TARGET_USER" ]]; then
        run_cmd chsh -s "$bash_path"
    else
        run_cmd sudo chsh -s "$bash_path" "$TARGET_USER"
    fi

    success "Default shell set to $bash_path for '$TARGET_USER'"
}

confirm_uninstall() {
    if [[ "$DRY_RUN" == true ]]; then
        warn "Dry-run mode: showing what uninstall would do"
        return 0
    fi

    echo ""
    warn "This will remove Bash-it and the setup-bash.sh managed block from .bashrc."
    read -rp "Are you sure you want to proceed? (y/N): " confirm
    if [[ "$confirm" != [yY]* ]]; then
        info "Uninstall cancelled"
        exit 0
    fi
}

install_kube_ps1() {
    local kube_ps1_dir="$TARGET_HOME/.kube-ps1"

    if [[ "$INSTALL_KUBE_PS1" != true ]]; then
        return 0
    fi

    if [[ -d "$kube_ps1_dir" ]]; then
        info "Updating kube-ps1..."
        run_as_user "$TARGET_USER" "cd '$kube_ps1_dir' && git pull --quiet"
    else
        info "Cloning kube-ps1..."
        run_as_user "$TARGET_USER" "git clone --depth=1 '$KUBE_PS1_REPO_URL' '$kube_ps1_dir'"
    fi

    if [[ "$DRY_RUN" == false && ! -d "$kube_ps1_dir" ]]; then
        fatal "kube-ps1 installation failed"
    fi

    success "kube-ps1 installed at $kube_ps1_dir"
}

install_kubectx() {
    local kubectx_dir="$TARGET_HOME/.kubectx"

    if [[ "$INSTALL_KUBECTX" != true ]]; then
        return 0
    fi

    if [[ -d "$kubectx_dir" ]]; then
        info "Updating kubectx/kubens..."
        run_as_user "$TARGET_USER" "cd '$kubectx_dir' && git pull --quiet"
    else
        info "Cloning kubectx/kubens..."
        run_as_user "$TARGET_USER" "git clone --depth=1 '$KUBECTX_REPO_URL' '$kubectx_dir'"
    fi

    if [[ "$DRY_RUN" == false && ! -d "$kubectx_dir" ]]; then
        fatal "kubectx installation failed"
    fi

    success "kubectx/kubens installed at $kubectx_dir"
}

uninstall_kube_ps1() {
    local kube_ps1_dir="$TARGET_HOME/.kube-ps1"

    if [[ "$DRY_RUN" == false && ! -d "$kube_ps1_dir" ]]; then
        return 0
    fi

    info "Removing kube-ps1 directory: $kube_ps1_dir"
    run_as_user "$TARGET_USER" "rm -rf '$kube_ps1_dir'"
    success "Removed $kube_ps1_dir"
}

uninstall_kubectx() {
    local kubectx_dir="$TARGET_HOME/.kubectx"

    if [[ "$DRY_RUN" == false && ! -d "$kubectx_dir" ]]; then
        return 0
    fi

    info "Removing kubectx/kubens directory: $kubectx_dir"
    run_as_user "$TARGET_USER" "rm -rf '$kubectx_dir'"
    success "Removed $kubectx_dir"
}

uninstall_bash_it() {
    local bash_it_dir="$TARGET_HOME/.bash_it"

    if [[ "$DRY_RUN" == false && ! -d "$bash_it_dir" ]]; then
        info "Bash-it directory not found at $bash_it_dir, nothing to remove"
        return 0
    fi

    info "Removing Bash-it directory: $bash_it_dir"
    run_as_user "$TARGET_USER" "rm -rf '$bash_it_dir'"
    success "Removed $bash_it_dir"
}

uninstall_bashrc_block() {
    local bashrc="$TARGET_HOME/.bashrc"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would remove setup-bash.sh managed block from $bashrc"
        return 0
    fi

    if [[ ! -f "$bashrc" ]]; then
        info "$bashrc not found, nothing to clean"
        return 0
    fi

    local tmpfile
    tmpfile="$(mktemp)"

    strip_managed_block "$bashrc" "$tmpfile"
    backup_and_fix_owner "$bashrc"
    mv "$tmpfile" "$bashrc"

    if [[ "$(id -u)" -eq 0 ]]; then
        local target_group
        target_group="$(id -gn "$TARGET_USER")"
        chown "$TARGET_USER:$target_group" "$bashrc" 2>/dev/null || true
    fi

    success "Removed setup-bash.sh managed block from $bashrc"
}

main() {
    echo -e "${BOLD}Bash + Bash-it Setup Script v${SCRIPT_VERSION}${NC}"
    echo "==========================================="

    parse_args "$@"
    detect_os

    if [[ "$UNINSTALL_MODE" == true ]]; then
        confirm_uninstall
        uninstall_bash_it
        uninstall_kube_ps1
        uninstall_kubectx
        uninstall_bashrc_block

        echo ""
        echo "==========================================="
        success "Uninstall complete for user '$TARGET_USER'"
        info "Start a new shell session to apply changes"
        echo "==========================================="
        return 0
    fi

    install_prerequisites
    install_bash
    install_bash_completion
    install_bash_it
    prompt_components
    install_kube_ps1
    install_kubectx
    configure_bashrc
    set_default_shell

    echo ""
    echo "==========================================="
    success "Setup complete for user '$TARGET_USER'"
    info "Start a new shell session, or run: exec bash"
    echo "==========================================="
}

main "$@"
