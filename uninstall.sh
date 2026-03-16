#!/usr/bin/env bash

# Coqui Uninstaller
# https://github.com/AgentCoqui/coqui
#
# Removes Coqui and optionally PHP/Composer from your system.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/uninstall.sh | bash
#
# Or run locally:
#   ./uninstall.sh [flags]

set -eu

# ─── Configuration (override via environment variables) ──────────────────────

COQUI_INSTALL_DIR="${COQUI_INSTALL_DIR:-$HOME/.coqui}"

# PHP version that was installed by the Coqui installer
PHP_MAJOR=8
PHP_MINOR=4

# ─── Mode flags (set via CLI arguments) ──────────────────────────────────────

REMOVE_WORKSPACE=false # true when --remove-workspace is passed
FORCE_MODE=false       # true when --force is passed (skip prompts)
ALL_MODE=false         # true when --all is passed (also remove PHP/Composer)
QUIET_MODE=false       # true when --quiet is passed (minimal output)

# ─── Argument parsing ────────────────────────────────────────────────────────

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --remove-workspace)
                REMOVE_WORKSPACE=true; shift ;;
            --force)
                FORCE_MODE=true; shift ;;
            --all)
                ALL_MODE=true; shift ;;
            --quiet|-q)
                QUIET_MODE=true; shift ;;
            --help|-h)
                show_usage; exit 0 ;;
            *)
                error "Unknown argument: $1"
                echo "  Run '$0 --help' for usage."
                exit 1 ;;
        esac
    done
}

show_usage() {
    echo "Usage: $0 [flags]"
    echo ""
    echo "Removes Coqui and associated files from your system."
    echo ""
    echo "Flags:"
    echo "  --remove-workspace     Delete the workspace directory (~/.coqui/.workspace)"
    echo "  --force                Skip all confirmation prompts"
    echo "  --all                  Also remove PHP and Composer installed by Coqui"
    echo "  --quiet, -q            Minimal output (milestones and errors only)"
    echo "  --help, -h             Show this help"
    echo ""
    echo "By default, the uninstaller preserves workspace data and does NOT remove PHP or Composer."
    echo ""
    echo "Environment variables:"
    echo "  COQUI_INSTALL_DIR      Install path (default: \$HOME/.coqui)"
    echo ""
    echo "Examples:"
    echo "  # Interactive uninstall (workspace preserved by default)"
    echo "  ./uninstall.sh"
    echo ""
    echo "  # Remove workspace data too"
    echo "  ./uninstall.sh --remove-workspace"
    echo ""
    echo "  # Remove everything without prompts"
    echo "  ./uninstall.sh --force"
    echo ""
    echo "  # Remove everything including PHP and Composer"
    echo "  ./uninstall.sh --force --all"
}

# ─── Output helpers ──────────────────────────────────────────────────────────

BOLD="$( (tput bold 2>/dev/null) || echo '' )"
RED="$( (tput setaf 1 2>/dev/null) || echo '' )"
GREEN="$( (tput setaf 2 2>/dev/null) || echo '' )"
YELLOW="$( (tput setaf 3 2>/dev/null) || echo '' )"
CYAN="$( (tput setaf 6 2>/dev/null) || echo '' )"
RESET="$( (tput sgr0 2>/dev/null) || echo '' )"

TICK="${GREEN}✓${RESET}"
CROSS="${RED}✗${RESET}"
ARROW="${CYAN}▸${RESET}"

status()   { [ "$QUIET_MODE" = true ] && return; echo "  ${ARROW} $*"; }
success()  { [ "$QUIET_MODE" = true ] && return; echo "  ${TICK} $*"; }
warn()     { echo "  ${YELLOW}! $*${RESET}"; }
error()    { echo "  ${CROSS} ${RED}$*${RESET}" >&2; }
fatal()    { error "$@"; exit 1; }
progress() { echo "  ${ARROW} $*"; }  # always prints, even in quiet mode

# ─── Utility functions ───────────────────────────────────────────────────────

available() { command -v "$1" >/dev/null 2>&1; }

# Prompt user for confirmation. Second arg sets the default: "yes" or "no".
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-yes}"
    local reply

    # Force mode — assume yes
    if [ "$FORCE_MODE" = true ]; then
        return 0
    fi

    # Piped input (curl | bash) — use default
    if [ ! -t 0 ]; then
        if [ "$default" = "no" ]; then
            return 1
        fi
        return 0
    fi

    if [ "$default" = "no" ]; then
        printf "  %s %s [y/N] " "${ARROW}" "${prompt}"
        read -r reply
        case "${reply}" in
            [yY]|[yY][eE][sS]) return 0 ;;
            *) return 1 ;;
        esac
    else
        printf "  %s %s [Y/n] " "${ARROW}" "${prompt}"
        read -r reply
        case "${reply}" in
            [nN]|[nN][oO]) return 1 ;;
            *) return 0 ;;
        esac
    fi
}

# Determine sudo requirement
setup_sudo() {
    SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        if available sudo; then
            SUDO="sudo"
        fi
    fi
}

# ─── OS detection ────────────────────────────────────────────────────────────

# shellcheck disable=SC2034
detect_os() {
    OS="$(uname -s)"
    DISTRO=""
    PKG_MANAGER=""

    case "$OS" in
        Linux)
            if [ -f /etc/os-release ]; then
                # shellcheck disable=SC1091
                . /etc/os-release
                DISTRO="${ID:-unknown}"
            fi

            if available apt-get; then
                PKG_MANAGER="apt"
            elif available dnf; then
                PKG_MANAGER="dnf"
            elif available yum; then
                PKG_MANAGER="yum"
            elif available pacman; then
                PKG_MANAGER="pacman"
            elif available apk; then
                PKG_MANAGER="apk"
            elif available nix-env || available nix; then
                PKG_MANAGER="nix"
            fi
            ;;
        Darwin)
            DISTRO="macos"
            if available brew; then
                PKG_MANAGER="brew"
            elif available nix-env || available nix; then
                PKG_MANAGER="nix"
            fi
            ;;
        *)
            warn "Unsupported OS: $OS. Will remove files manually."
            ;;
    esac
}

# ─── Installation detection ─────────────────────────────────────────────────

is_dev_installed() {
    [ -d "$COQUI_INSTALL_DIR" ] && [ -d "$COQUI_INSTALL_DIR/.git" ]
}

is_release_installed() {
    [ -d "$COQUI_INSTALL_DIR" ] && [ -f "$COQUI_INSTALL_DIR/.coqui-version" ]
}

is_installed() {
    is_dev_installed || is_release_installed
}

get_installed_version() {
    if [ -f "$COQUI_INSTALL_DIR/.coqui-version" ]; then
        cat "$COQUI_INSTALL_DIR/.coqui-version"
    else
        echo ""
    fi
}

# ─── Symlink removal ────────────────────────────────────────────────────────

remove_symlinks() {
    status "Checking for Coqui symlinks..."

    local found=false

    # Check all possible bin directories the installer might have used
    local bin_dirs="/opt/homebrew/bin /usr/local/bin $HOME/.local/bin"

    for dir in $bin_dirs; do
        local link="${dir}/coqui"
        if [ -L "$link" ]; then
            # Verify the symlink points into the Coqui install dir
            local target
            target="$(readlink "$link" 2>/dev/null || true)"
            if echo "$target" | grep -q "$COQUI_INSTALL_DIR"; then
                status "Removing symlink: ${link}"
                rm -f "$link"
                success "Removed symlink: ${link}"
                found=true
            fi
        elif [ -f "$link" ] && ! [ -L "$link" ]; then
            # Regular file (not a symlink) — might be a manually copied script
            warn "Found ${link} but it is not a symlink. Skipping."
        fi
    done

    if [ "$found" = false ]; then
        status "No Coqui symlinks found"
    fi
}

# ─── Install directory removal ───────────────────────────────────────────────

remove_install_dir() {
    if [ ! -d "$COQUI_INSTALL_DIR" ]; then
        status "Install directory not found: ${COQUI_INSTALL_DIR}"
        return
    fi

    local version_info=""
    if is_dev_installed; then
        version_info=" (dev mode)"
    elif is_release_installed; then
        local version
        version="$(get_installed_version)"
        if [ -n "$version" ]; then
            version_info=" v${version}"
        fi
    fi

    status "Found Coqui installation${version_info} at ${COQUI_INSTALL_DIR}"

    local workspace_dir="${COQUI_INSTALL_DIR}/.workspace"
    local delete_workspace=false

    if [ "$REMOVE_WORKSPACE" = true ]; then
        # Explicit flag: remove workspace
        delete_workspace=true
    elif [ -d "$workspace_dir" ]; then
        status "Workspace will be preserved (use --remove-workspace to delete)"
    fi

    if [ "$delete_workspace" = true ]; then
        # Delete the entire install directory
        status "Removing ${COQUI_INSTALL_DIR}..."
        rm -rf "$COQUI_INSTALL_DIR"
        success "Removed ${COQUI_INSTALL_DIR}"
    else
        # Keep workspace: remove everything except .workspace
        status "Removing Coqui files (preserving workspace)..."

        if [ -d "$workspace_dir" ]; then
            # Move workspace to a temp location, delete dir, move workspace back
            local tmp_workspace
            tmp_workspace="$(mktemp -d)"
            mv "$workspace_dir" "${tmp_workspace}/.workspace"

            rm -rf "$COQUI_INSTALL_DIR"

            mkdir -p "$COQUI_INSTALL_DIR"
            mv "${tmp_workspace}/.workspace" "$workspace_dir"
            rm -rf "$tmp_workspace"

            success "Removed Coqui files (workspace preserved at ${workspace_dir})"
        else
            # No workspace directory exists — safe to remove everything
            rm -rf "$COQUI_INSTALL_DIR"
            success "Removed ${COQUI_INSTALL_DIR}"
        fi
    fi
}

# ─── PHP removal ────────────────────────────────────────────────────────────

remove_php() {
    if ! available php; then
        status "PHP is not installed"
        return
    fi

    local php_version
    php_version="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || echo "unknown")"

    if [ "$FORCE_MODE" = false ]; then
        echo ""
        warn "PHP ${php_version} is installed on your system."
        echo "  Other applications may depend on PHP. Removing it could break them."
        echo ""
        if ! confirm "Remove PHP ${php_version}?" "no"; then
            status "Keeping PHP"
            return
        fi
    fi

    status "Removing PHP..."

    case "$PKG_MANAGER" in
        apt)
            local phpv="${PHP_MAJOR}.${PHP_MINOR}"
            # shellcheck disable=SC2086
            $SUDO apt-get remove -y "php${phpv}-*" 2>/dev/null || true
            $SUDO apt-get autoremove -y 2>/dev/null || true
            success "PHP packages removed via apt"
            ;;
        brew)
            brew uninstall "php@${PHP_MAJOR}.${PHP_MINOR}" 2>/dev/null || brew uninstall php 2>/dev/null || true
            success "PHP removed via Homebrew"
            ;;
        dnf|yum)
            # shellcheck disable=SC2086
            $SUDO ${PKG_MANAGER} remove -y "php-*" 2>/dev/null || true
            success "PHP packages removed via ${PKG_MANAGER}"
            ;;
        pacman)
            $SUDO pacman -R --noconfirm php php-sqlite php-intl 2>/dev/null || true
            success "PHP removed via pacman"
            ;;
        apk)
            local phpv="${PHP_MAJOR}${PHP_MINOR}"
            # shellcheck disable=SC2086
            $SUDO apk del "php${phpv}"* 2>/dev/null || true
            success "PHP removed via apk"
            ;;
        nix)
            local phpv="${PHP_MAJOR}${PHP_MINOR}"
            if available nix-env; then
                nix-env -e "php${phpv}" 2>/dev/null || nix-env -e php 2>/dev/null || true
            elif available nix; then
                nix profile remove "nixpkgs#php${phpv}" 2>/dev/null || nix profile remove nixpkgs#php 2>/dev/null || true
            fi
            success "PHP removed via Nix"
            ;;
        *)
            warn "Could not determine how to remove PHP on this system."
            echo "  Please remove PHP manually."
            ;;
    esac
}

# ─── Composer removal ────────────────────────────────────────────────────────

remove_composer() {
    if ! available composer; then
        status "Composer is not installed"
        return
    fi

    if [ "$FORCE_MODE" = false ]; then
        echo ""
        warn "Composer is installed on your system."
        echo "  Other PHP projects may depend on Composer."
        echo ""
        if ! confirm "Remove Composer?" "no"; then
            status "Keeping Composer"
            return
        fi
    fi

    status "Removing Composer..."

    # Find and remove the Composer binary from common locations
    local composer_path
    composer_path="$(command -v composer 2>/dev/null || true)"

    if [ -n "$composer_path" ]; then
        # Handle symlinks
        if [ -L "$composer_path" ]; then
            composer_path="$(readlink "$composer_path" 2>/dev/null || echo "$composer_path")"
        fi

        if [ -w "$composer_path" ]; then
            rm -f "$composer_path"
            success "Removed Composer: ${composer_path}"
        elif [ -n "$SUDO" ]; then
            $SUDO rm -f "$composer_path"
            success "Removed Composer: ${composer_path}"
        else
            warn "Cannot remove ${composer_path} (no write permission)"
        fi
    fi

    # Remove Composer cache directory
    local composer_home="${COMPOSER_HOME:-$HOME/.composer}"
    if [ -d "$composer_home" ]; then
        if [ "$FORCE_MODE" = true ]; then
            rm -rf "$composer_home"
            success "Removed Composer cache: ${composer_home}"
        else
            if confirm "Remove Composer cache (${composer_home})?" "no"; then
                rm -rf "$composer_home"
                success "Removed Composer cache: ${composer_home}"
            else
                status "Keeping Composer cache"
            fi
        fi
    fi
}

# ─── Banner ──────────────────────────────────────────────────────────────────

show_banner() {
    if [ "$QUIET_MODE" = true ]; then return; fi
    echo ""
    echo "  ${GREEN} ▄▄·       .▄▄▄  ▄• ▄▌▪  ▄▄▄▄·       ▄▄▄▄▄${RESET}"
    echo "  ${GREEN}▐█ ▌▪▪     ▐▀•▀█ █▪██▌██ ▐█ ▀█▪▪     •██  ${RESET}"
    echo "  ${GREEN}██ ▄▄ ▄█▀▄ █▌·.█▌█▌▐█▌▐█·▐█▀▀█▄ ▄█▀▄  ▐█.▪${RESET}"
    echo "  ${GREEN}▐███▌▐█▌.▐▌▐█▪▄█·▐█▄█▌▐█▌██▄▪▐█▐█▌.▐▌ ▐█▌·${RESET}"
    echo "  ${GREEN}·▀▀▀  ▀█▄▀▪·▀▀█.  ▀▀▀ ▀▀▀·▀▀▀▀  ▀█▄▀▪ ▀▀▀ ${RESET}"
    echo ""
    echo "  ${BOLD}Coqui Uninstaller${RESET}"
    echo ""
}

# ─── Summary ─────────────────────────────────────────────────────────────────

print_summary() {
    if [ "$QUIET_MODE" = true ]; then
        progress "Uninstall complete"
        return
    fi

    echo ""
    echo "  ──────────────────────────────────────────"
    echo "  ${BOLD}${GREEN}Uninstall complete!${RESET}"
    echo "  ──────────────────────────────────────────"

    if [ -d "${COQUI_INSTALL_DIR}/.workspace" ]; then
        echo ""
        echo "  ${BOLD}Workspace preserved:${RESET}"
        echo ""
        echo "    ${COQUI_INSTALL_DIR}/.workspace"
        echo ""
        echo "  To remove it later:"
        echo ""
        echo "    rm -rf ${COQUI_INSTALL_DIR}"
    fi

    if [ "$ALL_MODE" = false ]; then
        local has_note=false
        if available php; then
            if [ "$has_note" = false ]; then
                echo ""
                echo "  ${BOLD}Still installed:${RESET}"
                has_note=true
            fi
            echo "    PHP (re-run with --all to remove)"
        fi
        if available composer; then
            if [ "$has_note" = false ]; then
                echo ""
                echo "  ${BOLD}Still installed:${RESET}"
                has_note=true
            fi
            echo "    Composer (re-run with --all to remove)"
        fi
    fi

    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    show_banner

    detect_os
    setup_sudo

    # Check if Coqui is installed
    if ! [ -d "$COQUI_INSTALL_DIR" ]; then
        warn "Coqui is not installed at ${COQUI_INSTALL_DIR}"
        echo ""
        echo "  If you installed to a custom directory, set COQUI_INSTALL_DIR:"
        echo "    COQUI_INSTALL_DIR=/path/to/coqui $0"
        echo ""
        exit 0
    fi

    # Confirm uninstall (unless --force)
    if [ "$FORCE_MODE" = false ]; then
        echo "  ${BOLD}This will remove Coqui from:${RESET} ${COQUI_INSTALL_DIR}"
        echo ""
        if ! confirm "Proceed with uninstall?"; then
            echo ""
            echo "  Uninstall cancelled."
            echo ""
            exit 0
        fi
        echo ""
    fi

    # 1. Remove symlinks from bin directories
    remove_symlinks

    # 2. Remove the install directory (with workspace logic)
    remove_install_dir

    # 3. Optionally remove PHP and Composer (--all only)
    if [ "$ALL_MODE" = true ]; then
        remove_php
        remove_composer
    fi

    # 4. Print summary
    print_summary
}

# Wrap in main() so partial curl downloads don't execute incomplete script
main "$@"
