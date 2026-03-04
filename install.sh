#!/usr/bin/env bash

# Coqui Installer
# https://github.com/AgentCoqui/coqui
#
# Terminal AI agent with multi-model orchestration, persistent sessions,
# and runtime extensibility via Composer.
#
# Install with:
#   curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh | bash
#
# Windows:
#   irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | iex

set -eu

# ─── Configuration (override via environment variables) ──────────────────────

COQUI_REPO="${COQUI_REPO:-https://github.com/AgentCoqui/coqui.git}"
COQUI_INSTALL_DIR="${COQUI_INSTALL_DIR:-$HOME/.coqui}"
COQUI_VERSION="${COQUI_VERSION:-}"

# Minimum PHP version required
REQUIRED_PHP_MAJOR=8
REQUIRED_PHP_MINOR=4

# PHP extensions required by Coqui and php-agents
REQUIRED_EXTENSIONS="curl mbstring openssl pdo_sqlite xml zip"

# ─── Mode flags (set via CLI arguments) ──────────────────────────────────────

INSTALL_PHP=false
INSTALL_COMPOSER=false
INSTALL_COQUI=false
INSTALL_SERVICE=false
NON_INTERACTIVE=false
SELECTIVE_MODE=false   # true when any --install-* flag is passed

# ─── Service configuration ───────────────────────────────────────────────────

SERVICE_PORT="${COQUI_API_PORT:-3300}"
SERVICE_INSTALLED=false  # set to true when service is set up during this run

# ─── Argument parsing ────────────────────────────────────────────────────────

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --install-php)
                INSTALL_PHP=true; SELECTIVE_MODE=true; shift ;;
            --install-composer)
                INSTALL_COMPOSER=true; SELECTIVE_MODE=true; shift ;;
            --install-coqui)
                INSTALL_COQUI=true; SELECTIVE_MODE=true; shift ;;
            --install-service)
                INSTALL_SERVICE=true; SELECTIVE_MODE=true; shift ;;
            --non-interactive)
                NON_INTERACTIVE=true; shift ;;
            --help|-h)
                show_usage; exit 0 ;;
            *)
                error "Unknown argument: $1"
                echo "  Run '$0 --help' for usage."
                exit 1 ;;
        esac
    done

    # No --install-* flags → full install (backward compatible with curl | bash)
    if [ "$SELECTIVE_MODE" = false ]; then
        INSTALL_PHP=true
        INSTALL_COMPOSER=true
        INSTALL_COQUI=true
    fi
}

show_usage() {
    echo "Usage: $0 [flags]"
    echo ""
    echo "Flags:"
    echo "  --install-php          Install/check PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ and extensions"
    echo "  --install-composer     Install/check Composer"
    echo "  --install-coqui        Install/update Coqui and create symlink"
    echo "  --install-service      Install Coqui API as a background service"
    echo "  --non-interactive      Skip all confirmation prompts (assume yes)"
    echo "  --help, -h             Show this help"
    echo ""
    echo "When no --install-* flags are given, all components are installed (full setup)."
    echo ""
    echo "Environment variables:"
    echo "  COQUI_REPO             Git repo URL (default: ${COQUI_REPO})"
    echo "  COQUI_INSTALL_DIR      Install path (default: \$HOME/.coqui)"
    echo "  COQUI_VERSION          Git branch or tag (default: latest)"
    echo ""
    echo "Examples:"
    echo "  # Full install (default)"
    echo "  curl -fsSL https://...install.sh | bash"
    echo ""
    echo "  # PHP only, no prompts"
    echo "  ./install.sh --install-php --non-interactive"
    echo ""
    echo "  # PHP + Composer only"
    echo "  ./install.sh --install-php --install-composer"
    echo ""
    echo "  # Coqui only (user has PHP + Composer already)"
    echo "  ./install.sh --install-coqui"
    echo ""
    echo "  # Service only (Coqui already installed)"
    echo "  ./install.sh --install-service"
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

status()  { echo "  ${ARROW} $*"; }
success() { echo "  ${TICK} $*"; }
warn()    { echo "  ${YELLOW}! $*${RESET}"; }
error()   { echo "  ${CROSS} ${RED}$*${RESET}" >&2; }
fatal()   { error "$@"; exit 1; }

# ─── Utility functions ───────────────────────────────────────────────────────

available() { command -v "$1" >/dev/null 2>&1; }

# Prompt user for Y/n confirmation. Default is yes.
confirm() {
    local prompt="${1:-Continue?}"
    local reply

    # Non-interactive mode — assume yes
    if [ "$NON_INTERACTIVE" = true ]; then
        return 0
    fi

    # Piped input (curl | bash) — assume yes
    if [ ! -t 0 ]; then
        return 0
    fi

    printf "  %s %s [Y/n] " "${ARROW}" "${prompt}"
    read -r reply
    case "${reply}" in
        [nN]|[nN][oO]) return 1 ;;
        *) return 0 ;;
    esac
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

# Detect the best bin directory in PATH
detect_bin_dir() {
    # Prefer /usr/local/bin if it exists and is in PATH
    if echo "$PATH" | tr ':' '\n' | grep -qx '/usr/local/bin'; then
        BIN_DIR="/usr/local/bin"
        return
    fi

    # Fall back to ~/.local/bin
    BIN_DIR="$HOME/.local/bin"
}

# ─── OS detection ────────────────────────────────────────────────────────────

# shellcheck disable=SC2034
detect_os() {
    OS="$(uname -s)"
    # shellcheck disable=SC2034
    ARCH="$(uname -m)"
    DISTRO=""
    # shellcheck disable=SC2034
    DISTRO_VERSION=""
    # shellcheck disable=SC2034
    IS_WSL=false
    PKG_MANAGER=""

    case "$OS" in
        Linux)
            local kern
            kern="$(uname -r)"
            case "$kern" in
                *icrosoft*WSL2|*icrosoft*wsl2) IS_WSL=true ;;
                *icrosoft) fatal "WSL1 is not supported. Please upgrade to WSL2." ;;
            esac

            if [ -f /etc/os-release ]; then
                # shellcheck disable=SC1091
                . /etc/os-release
                # shellcheck disable=SC2034
                DISTRO="${ID:-unknown}"
                # shellcheck disable=SC2034
                DISTRO_VERSION="${VERSION_ID:-}"
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
            # shellcheck disable=SC2034
            DISTRO="macos"
            if available brew; then
                PKG_MANAGER="brew"
            elif available nix-env || available nix; then
                PKG_MANAGER="nix"
            fi
            ;;
        *)
            fatal "Unsupported operating system: $OS. Coqui supports Linux and macOS."
            ;;
    esac
}

# ─── PHP checks ──────────────────────────────────────────────────────────────

check_php() {
    status "Checking PHP..."

    if ! available php; then
        warn "PHP is not installed."
        install_php
        return
    fi

    local php_version
    php_version="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"
    local php_major php_minor
    php_major="$(echo "$php_version" | cut -d. -f1)"
    php_minor="$(echo "$php_version" | cut -d. -f2)"

    if [ "$php_major" -lt "$REQUIRED_PHP_MAJOR" ] || \
       { [ "$php_major" -eq "$REQUIRED_PHP_MAJOR" ] && [ "$php_minor" -lt "$REQUIRED_PHP_MINOR" ]; }; then
        warn "PHP $php_version found, but PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
        install_php
        return
    fi

    success "PHP $php_version"
}

install_php() {
    case "$PKG_MANAGER" in
        apt)
            if confirm "Install PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR} via Ondrej PPA?"; then
                status "Adding Ondrej PHP repository..."
                $SUDO apt-get update -qq
                $SUDO apt-get install -y -qq software-properties-common ca-certificates lsb-release >/dev/null
                $SUDO add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
                $SUDO apt-get update -qq

                local phpv="${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}"
                local packages="php${phpv}-cli php${phpv}-curl php${phpv}-mbstring php${phpv}-xml php${phpv}-zip php${phpv}-intl php${phpv}-readline php${phpv}-sqlite3"

                status "Installing PHP ${phpv} and extensions..."
                # shellcheck disable=SC2086
                $SUDO apt-get install -y -qq $packages >/dev/null
                success "PHP ${phpv} installed"
            else
                fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required. Install it and re-run the installer."
            fi
            ;;
        brew)
            if confirm "Install PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR} via Homebrew?"; then
                status "Installing PHP via Homebrew..."
                brew install php@${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR} >/dev/null
                brew link --force --overwrite php@${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR} >/dev/null
                success "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR} installed"
            else
                fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
            fi
            ;;
        dnf|yum)
            if confirm "Install PHP via ${PKG_MANAGER}?"; then
                status "Installing PHP via ${PKG_MANAGER}..."
                # shellcheck disable=SC2086
                $SUDO ${PKG_MANAGER} install -y php-cli php-curl php-mbstring php-xml php-zip php-intl php-pdo >/dev/null
                success "PHP installed"
            else
                fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
            fi
            ;;
        pacman)
            if confirm "Install PHP via pacman?"; then
                status "Installing PHP via pacman..."
                $SUDO pacman -S --noconfirm php php-sqlite php-intl >/dev/null
                success "PHP installed"
            else
                fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
            fi
            ;;
        apk)
            if confirm "Install PHP via apk?"; then
                status "Installing PHP via apk..."
                local phpv="${REQUIRED_PHP_MAJOR}${REQUIRED_PHP_MINOR}"
                $SUDO apk add --no-cache php${phpv} php${phpv}-cli php${phpv}-curl php${phpv}-mbstring php${phpv}-xml php${phpv}-zip php${phpv}-intl php${phpv}-pdo_sqlite >/dev/null
                success "PHP installed"
            else
                fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
            fi
            ;;
        nix)
            if confirm "Install PHP via Nix?"; then
                status "Installing PHP via Nix..."
                local phpv="${REQUIRED_PHP_MAJOR}${REQUIRED_PHP_MINOR}"
                if available nix-env; then
                    nix-env -iA nixpkgs.php${phpv} >/dev/null 2>&1 || nix-env -iA nixpkgs.php >/dev/null 2>&1
                elif available nix; then
                    nix profile install nixpkgs#php${phpv} >/dev/null 2>&1 || nix profile install nixpkgs#php >/dev/null 2>&1
                fi
                success "PHP installed"
            else
                fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
            fi
            ;;
        *)
            echo ""
            echo "  Please install PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ with the following extensions:"
            echo "    curl, mbstring, pdo_sqlite, xml, zip, intl"
            echo ""
            echo "  See: https://www.php.net/manual/en/install.php"
            echo ""
            fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
            ;;
    esac
}

# ─── Extension checks ────────────────────────────────────────────────────────

check_extensions() {
    status "Checking PHP extensions..."

    local missing=""
    local loaded
    loaded="$(php -m 2>/dev/null)"

    for ext in $REQUIRED_EXTENSIONS; do
        if ! echo "$loaded" | grep -qi "^${ext}$"; then
            missing="${missing} ${ext}"
        fi
    done

    if [ -z "$missing" ]; then
        success "All required extensions available"
        return
    fi

    warn "Missing PHP extensions:${missing}"

    if [ "$PKG_MANAGER" = "apt" ]; then
        local phpv
        phpv="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"

        # Map extension names to apt package names
        local packages=""
        for ext in $missing; do
            case "$ext" in
                pdo_sqlite) packages="${packages} php${phpv}-sqlite3" ;;
                *)          packages="${packages} php${phpv}-${ext}" ;;
            esac
        done

        if confirm "Install missing extensions via apt?"; then
            status "Installing:${packages}"
            # shellcheck disable=SC2086
            $SUDO apt-get install -y -qq $packages >/dev/null
            success "Extensions installed"
        else
            fatal "Required extensions missing:${missing}"
        fi
    elif [ "$PKG_MANAGER" = "dnf" ] || [ "$PKG_MANAGER" = "yum" ]; then
        local packages=""
        for ext in $missing; do
            case "$ext" in
                pdo_sqlite) packages="${packages} php-pdo" ;;
                *)          packages="${packages} php-${ext}" ;;
            esac
        done
        if confirm "Install missing extensions via ${PKG_MANAGER}?"; then
            status "Installing:${packages}"
            # shellcheck disable=SC2086
            $SUDO ${PKG_MANAGER} install -y $packages >/dev/null
            success "Extensions installed"
        else
            fatal "Required extensions missing:${missing}"
        fi
    elif [ "$PKG_MANAGER" = "apk" ]; then
        local phpv="${REQUIRED_PHP_MAJOR}${REQUIRED_PHP_MINOR}"
        local packages=""
        for ext in $missing; do
            packages="${packages} php${phpv}-${ext}"
        done
        if confirm "Install missing extensions via apk?"; then
            status "Installing:${packages}"
            # shellcheck disable=SC2086
            $SUDO apk add --no-cache $packages >/dev/null
            success "Extensions installed"
        else
            fatal "Required extensions missing:${missing}"
        fi
    elif [ "$PKG_MANAGER" = "nix" ]; then
        warn "Missing extensions:${missing}. Nix manages PHP extensions via its derivation configuration. Please ensure your Nix environment has these extensions enabled."
        if ! confirm "Ignore missing extensions warning and continue?"; then
             fatal "Required extensions missing:${missing}"
        fi
    else
        # pacman and brew generally bundle these extensions with their base php packages,
        # or require manual edits to php.ini to enable them.
        echo ""
        echo "  Please enable or install the following PHP extensions:${missing}"
        echo ""
        fatal "Required PHP extensions missing."
    fi
}

# ─── Git check ───────────────────────────────────────────────────────────────

check_git() {
    status "Checking git..."

    if available git; then
        success "git $(git --version | awk '{print $3}')"
        return
    fi

    case "$PKG_MANAGER" in
        apt)
            if confirm "Install git via apt?"; then
                $SUDO apt-get install -y -qq git >/dev/null
                success "git installed"
            else
                fatal "git is required."
            fi
            ;;
        brew)
            if confirm "Install git via Homebrew?"; then
                brew install git >/dev/null
                success "git installed"
            else
                fatal "git is required. Install it with: brew install git"
            fi
            ;;
        dnf|yum)
            if confirm "Install git via ${PKG_MANAGER}?"; then
                $SUDO ${PKG_MANAGER} install -y git >/dev/null
                success "git installed"
            else
                fatal "git is required."
            fi
            ;;
        pacman)
            if confirm "Install git via pacman?"; then
                $SUDO pacman -S --noconfirm git >/dev/null
                success "git installed"
            else
                fatal "git is required."
            fi
            ;;
        apk)
            if confirm "Install git via apk?"; then
                $SUDO apk add --no-cache git >/dev/null
                success "git installed"
            else
                fatal "git is required."
            fi
            ;;
        nix)
            if confirm "Install git via Nix?"; then
                if available nix-env; then
                    nix-env -iA nixpkgs.git >/dev/null 2>&1
                elif available nix; then
                    nix profile install nixpkgs#git >/dev/null 2>&1
                fi
                success "git installed"
            else
                fatal "git is required."
            fi
            ;;
        *)
            fatal "git is required. Please install it and re-run the installer."
            ;;
    esac
}

# ─── Composer check ──────────────────────────────────────────────────────────

check_composer() {
    status "Checking Composer..."

    if available composer; then
        success "Composer $(composer --version 2>/dev/null | awk '{print $NF}' | head -1)"
        return
    fi

    if confirm "Composer not found. Install it now?"; then
        install_composer
    else
        fatal "Composer is required."
    fi
}

install_composer() {
    status "Downloading Composer installer..."

    local expected_sig
    expected_sig="$(curl -fsSL https://composer.github.io/installer.sig)"

    php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"

    local actual_sig
    actual_sig="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"

    if [ "$expected_sig" != "$actual_sig" ]; then
        rm -f /tmp/composer-setup.php
        fatal "Composer installer signature mismatch. Download may be corrupted."
    fi

    status "Installing Composer..."
    php /tmp/composer-setup.php --quiet
    rm -f /tmp/composer-setup.php

    # Move composer.phar to a directory in PATH
    detect_bin_dir
    if [ "$BIN_DIR" = "/usr/local/bin" ] && [ "$(id -u)" -ne 0 ]; then
        $SUDO mv composer.phar "$BIN_DIR/composer"
    else
        mkdir -p "$BIN_DIR"
        mv composer.phar "$BIN_DIR/composer"
    fi

    success "Composer installed to $BIN_DIR/composer"
}

# ─── Coqui install / update ─────────────────────────────────────────────────

is_installed() {
    [ -d "$COQUI_INSTALL_DIR" ] && [ -d "$COQUI_INSTALL_DIR/.git" ]
}

install_coqui() {
    status "Cloning Coqui into ${COQUI_INSTALL_DIR}..."

    local clone_args="--depth 1"
    if [ -n "$COQUI_VERSION" ]; then
        clone_args="--branch $COQUI_VERSION --depth 1"
    fi

    # shellcheck disable=SC2086
    git clone $clone_args "$COQUI_REPO" "$COQUI_INSTALL_DIR" 2>/dev/null \
        || fatal "Failed to clone Coqui repository."

    success "Coqui cloned"

    run_composer_install
}

update_coqui() {
    status "Checking for updates..."

    cd "$COQUI_INSTALL_DIR"

    git fetch --quiet 2>/dev/null || fatal "Failed to fetch updates."

    local local_head remote_head
    local_head="$(git rev-parse HEAD)"
    remote_head="$(git rev-parse '@{u}' 2>/dev/null || echo "$local_head")"

    if [ "$local_head" = "$remote_head" ]; then
        success "Coqui is already up to date"

        # Still run composer install in case dependencies changed locally
        run_composer_install
        return
    fi

    if confirm "A new version of Coqui is available. Update now?"; then
        status "Updating Coqui..."
        git pull --ff-only --quiet 2>/dev/null || fatal "Failed to update. Try a clean install."
        success "Coqui updated"
        run_composer_install
    else
        success "Update skipped"
    fi
}

run_composer_install() {
    status "Installing dependencies..."

    cd "$COQUI_INSTALL_DIR"
    composer install --no-dev --optimize-autoloader --no-interaction --quiet 2>/dev/null \
        || fatal "Composer install failed."

    success "Dependencies installed"
}

# ─── Configuration ───────────────────────────────────────────────────────────

setup_config() {
    local config_file="${COQUI_INSTALL_DIR}/openclaw.json"

    if [ -f "$config_file" ]; then
        success "Configuration file exists (preserved)"
        return
    fi

    status "Creating default configuration..."

    cat > "$config_file" << 'CONFIGEOF'
{
    "agents": {
        "defaults": {
            "workspace": ".workspace",
            "models": {
                "ollama/qwen3:latest": { "alias": "qwen" },
                "ollama/qwen3-coder:latest": { "alias": "coder" },
                "ollama/glm-4.7-flash:latest": { "alias": "glm" },
                "ollama/llama3.2:latest": { "alias": "llama" }
            },
            "model": {
                "primary": "ollama/glm-4.7-flash:latest",
                "fallbacks": ["ollama/qwen3-coder:latest"]
            },
            "roles": {
                "orchestrator": "ollama/glm-4.7-flash:latest",
                "coder": "ollama/qwen3-coder:latest",
                "reviewer": "ollama/qwen3:latest"
            }
        }
    },
    "models": {
        "providers": {
            "ollama": {
                "baseUrl": "http://localhost:11434/v1",
                "apiKey": "ollama-local",
                "api": "openai-completions",
                "models": [
                    {
                        "id": "qwen3:latest",
                        "name": "Qwen 3",
                        "reasoning": false,
                        "input": ["text"],
                        "contextWindow": 128000,
                        "maxTokens": 8192
                    },
                    {
                        "id": "qwen3-coder:latest",
                        "name": "Qwen 3 Coder",
                        "reasoning": false,
                        "input": ["text"],
                        "contextWindow": 128000,
                        "maxTokens": 8192
                    },
                    {
                        "id": "glm-4.7-flash:latest",
                        "name": "GLM 4.7 Flash",
                        "reasoning": false,
                        "input": ["text"],
                        "contextWindow": 128000,
                        "maxTokens": 8192
                    },
                    {
                        "id": "llama3.2:latest",
                        "name": "Llama 3.2",
                        "reasoning": false,
                        "input": ["text"],
                        "contextWindow": 128000,
                        "maxTokens": 4096
                    }
                ]
            }
        }
    }
}
CONFIGEOF

    success "Default configuration created (Ollama local provider)"
}

# ─── Symlink ─────────────────────────────────────────────────────────────────

create_symlink() {
    detect_bin_dir

    local target="${COQUI_INSTALL_DIR}/bin/coqui"

    # Ensure the bin script is executable
    chmod +x "$target"

    status "Creating symlink in ${BIN_DIR}..."

    if [ "$BIN_DIR" = "/usr/local/bin" ]; then
        if [ -w "$BIN_DIR" ]; then
            ln -sf "$target" "$BIN_DIR/coqui"
        elif [ -n "$SUDO" ]; then
            $SUDO ln -sf "$target" "$BIN_DIR/coqui"
        else
            # Fall back to ~/.local/bin
            BIN_DIR="$HOME/.local/bin"
            mkdir -p "$BIN_DIR"
            ln -sf "$target" "$BIN_DIR/coqui"
        fi
    else
        mkdir -p "$BIN_DIR"
        ln -sf "$target" "$BIN_DIR/coqui"
    fi

    success "Symlink created: ${BIN_DIR}/coqui"

    # Warn if BIN_DIR is not in PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
        echo ""
        warn "${BIN_DIR} is not in your PATH."
        echo ""
        echo "  Add it to your shell profile:"
        echo ""
        echo "    echo 'export PATH=\"${BIN_DIR}:\$PATH\"' >> ~/.bashrc"
        echo ""
    fi
}

# ─── Service installation ────────────────────────────────────────────────────

# Detect init system for service management
detect_init_system() {
    INIT_SYSTEM=""
    case "$OS" in
        Linux)
            if available systemctl && [ -d /run/systemd/system ]; then
                INIT_SYSTEM="systemd"
            fi
            ;;
        Darwin)
            INIT_SYSTEM="launchd"
            ;;
    esac
}

# Generate a random 32-character hex API key
generate_api_key() {
    if available openssl; then
        openssl rand -hex 32
    else
        head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# Write the API key to the workspace .env file
write_api_key() {
    local api_key="$1"
    local workspace_dir="${COQUI_INSTALL_DIR}/.workspace"
    local env_file="${workspace_dir}/.env"

    mkdir -p "$workspace_dir"

    # Append or update the key in .env
    if [ -f "$env_file" ] && grep -q '^COQUI_API_KEY=' "$env_file"; then
        # Update existing key
        local tmp_file
        tmp_file="$(mktemp)"
        sed "s|^COQUI_API_KEY=.*|COQUI_API_KEY=${api_key}|" "$env_file" > "$tmp_file"
        mv "$tmp_file" "$env_file"
    else
        echo "COQUI_API_KEY=${api_key}" >> "$env_file"
    fi
}

# Check if the Coqui service is installed
is_service_installed() {
    detect_init_system
    case "$INIT_SYSTEM" in
        systemd)
            [ -f "${HOME}/.config/systemd/user/coqui.service" ]
            ;;
        launchd)
            [ -f "${HOME}/Library/LaunchAgents/bot.coqui.agent.plist" ]
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if the Coqui service is currently running
is_service_running() {
    detect_init_system
    case "$INIT_SYSTEM" in
        systemd)
            systemctl --user is-active --quiet coqui 2>/dev/null
            ;;
        launchd)
            launchctl list 2>/dev/null | grep -q "bot.coqui.agent"
            ;;
        *)
            return 1
            ;;
    esac
}

# Restart the service if it is running
restart_service() {
    detect_init_system
    case "$INIT_SYSTEM" in
        systemd)
            systemctl --user restart coqui 2>/dev/null
            ;;
        launchd)
            local plist_file="${HOME}/Library/LaunchAgents/bot.coqui.agent.plist"
            launchctl unload "$plist_file" 2>/dev/null || true
            launchctl load "$plist_file" 2>/dev/null
            ;;
    esac
}

# Generate and install the systemd user service unit
install_systemd_service() {
    local service_dir="${HOME}/.config/systemd/user"
    local service_file="${service_dir}/coqui.service"

    mkdir -p "$service_dir"

    cat > "$service_file" << SERVICEEOF
# Coqui — systemd user service
#
# Runs the Coqui API server as a background daemon.
# Managed by the Coqui installer.
#
# View logs:
#   journalctl --user -u coqui -f

[Unit]
Description=Coqui AI Agent — API Server
Documentation=https://github.com/AgentCoqui/coqui
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${COQUI_INSTALL_DIR}/bin/coqui-launcher --api-only --host 0.0.0.0 --port ${SERVICE_PORT}
WorkingDirectory=${COQUI_INSTALL_DIR}
Restart=on-failure
RestartSec=5
StartLimitBurst=3
StartLimitIntervalSec=60

# Environment
Environment=HOME=${HOME}
Environment=COQUI_INSTALL_DIR=${COQUI_INSTALL_DIR}

# Resource limits
LimitNOFILE=65536
MemoryMax=2G

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${COQUI_INSTALL_DIR}/.workspace ${COQUI_INSTALL_DIR}/openclaw.json
PrivateTmp=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=coqui

[Install]
WantedBy=default.target
SERVICEEOF

    success "Service file created: ${service_file}"

    systemctl --user daemon-reload

    status "Enabling service to start on boot..."
    systemctl --user enable coqui 2>/dev/null
    success "Service enabled"

    status "Starting the service..."
    systemctl --user start coqui 2>/dev/null
    sleep 1

    if systemctl --user is-active --quiet coqui 2>/dev/null; then
        success "Service started — API running on http://0.0.0.0:${SERVICE_PORT}"
    else
        warn "Service may not have started. Check: journalctl --user -u coqui -n 20"
    fi

    # Enable lingering so user services start on boot without login
    if available loginctl; then
        loginctl enable-linger "$(whoami)" 2>/dev/null || true
        success "Lingering enabled (service starts on boot without login)"
    fi
}

# Generate and install the launchd plist
install_launchd_service() {
    local plist_dir="${HOME}/Library/LaunchAgents"
    local plist_file="${plist_dir}/bot.coqui.agent.plist"

    mkdir -p "$plist_dir"

    cat > "$plist_file" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>bot.coqui.agent</string>

    <key>ProgramArguments</key>
    <array>
        <string>${COQUI_INSTALL_DIR}/bin/coqui-launcher</string>
        <string>--api-only</string>
        <string>--host</string>
        <string>0.0.0.0</string>
        <string>--port</string>
        <string>${SERVICE_PORT}</string>
    </array>

    <key>WorkingDirectory</key>
    <string>${COQUI_INSTALL_DIR}</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>COQUI_INSTALL_DIR</key>
        <string>${COQUI_INSTALL_DIR}</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>ThrottleInterval</key>
    <integer>5</integer>

    <key>StandardOutPath</key>
    <string>/tmp/coqui-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/coqui-stderr.log</string>

    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLISTEOF

    success "Plist created: ${plist_file}"

    status "Loading the service..."
    launchctl unload "$plist_file" 2>/dev/null || true
    launchctl load "$plist_file" 2>/dev/null

    sleep 1
    if launchctl list 2>/dev/null | grep -q "bot.coqui.agent"; then
        success "Service started — API running on http://0.0.0.0:${SERVICE_PORT}"
    else
        warn "Service may not have started. Check: tail -f /tmp/coqui-stderr.log"
    fi
}

# Uninstall the service
uninstall_service() {
    detect_init_system
    case "$INIT_SYSTEM" in
        systemd)
            local service_file="${HOME}/.config/systemd/user/coqui.service"
            if systemctl --user is-active --quiet coqui 2>/dev/null; then
                systemctl --user stop coqui 2>/dev/null
                success "Service stopped"
            fi
            if systemctl --user is-enabled --quiet coqui 2>/dev/null; then
                systemctl --user disable coqui 2>/dev/null
                success "Service disabled"
            fi
            if [ -f "$service_file" ]; then
                rm -f "$service_file"
                systemctl --user daemon-reload
                success "Service file removed"
            else
                warn "Service file not found (already removed?)"
            fi
            ;;
        launchd)
            local plist_file="${HOME}/Library/LaunchAgents/bot.coqui.agent.plist"
            if launchctl list 2>/dev/null | grep -q "bot.coqui.agent"; then
                launchctl unload "$plist_file" 2>/dev/null || true
                success "Service unloaded"
            fi
            if [ -f "$plist_file" ]; then
                rm -f "$plist_file"
                success "Plist removed"
            else
                warn "Plist not found (already removed?)"
            fi
            ;;
        *)
            warn "No supported init system detected."
            ;;
    esac
}

# Main service installation orchestrator
install_service() {
    detect_init_system

    if [ -z "$INIT_SYSTEM" ]; then
        warn "No supported init system detected (systemd or launchd required)."
        echo "  Service installation is not available on this system."
        return
    fi

    echo ""
    echo "  ${BOLD}Service Setup${RESET}"
    echo ""
    echo "  This will install Coqui as a background API service that:"
    echo "    • Starts automatically on boot"
    echo "    • Restarts on failure"
    echo "    • Binds to 0.0.0.0:${SERVICE_PORT} (network accessible)"
    echo "    • Requires API key authentication for security"
    echo ""

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        echo "  ${BOLD}Init system:${RESET} systemd (user-level, no root required)"
    elif [ "$INIT_SYSTEM" = "launchd" ]; then
        echo "  ${BOLD}Init system:${RESET} launchd (user agent, no root required)"
    fi
    echo ""

    # Generate and save the API key
    status "Generating API key for secure access..."
    local api_key
    api_key="$(generate_api_key)"
    write_api_key "$api_key"
    success "API key saved to ${COQUI_INSTALL_DIR}/.workspace/.env"

    echo ""
    echo "  ┌──────────────────────────────────────────────────────────────────┐"
    echo "  │  ${BOLD}Your API Key${RESET} (save this — shown only once):                     │"
    echo "  │                                                                  │"
    echo "  │  ${YELLOW}${api_key}${RESET}  │"
    echo "  │                                                                  │"
    echo "  │  Use this key in the Authorization header:                       │"
    echo "  │  ${CYAN}Authorization: Bearer ${api_key}${RESET}  │"
    echo "  └──────────────────────────────────────────────────────────────────┘"
    echo ""

    # Ensure the launcher is executable
    chmod +x "${COQUI_INSTALL_DIR}/bin/coqui-launcher" 2>/dev/null || true

    # Install the appropriate service
    case "$INIT_SYSTEM" in
        systemd)
            install_systemd_service
            ;;
        launchd)
            install_launchd_service
            ;;
    esac

    SERVICE_INSTALLED=true
}

# Print service management instructions
print_service_info() {
    detect_init_system

    echo ""
    echo "  ${BOLD}Service Management:${RESET}"
    echo ""

    case "$INIT_SYSTEM" in
        systemd)
            echo "    Status:   systemctl --user status coqui"
            echo "    Logs:     journalctl --user -u coqui -f"
            echo "    Stop:     systemctl --user stop coqui"
            echo "    Start:    systemctl --user start coqui"
            echo "    Restart:  systemctl --user restart coqui"
            echo "    Disable:  systemctl --user disable coqui"
            echo "    Remove:   bash install.sh --install-service uninstall"
            ;;
        launchd)
            echo "    Status:   launchctl list bot.coqui.agent"
            echo "    Logs:     tail -f /tmp/coqui-stderr.log"
            echo "    Stop:     launchctl unload ~/Library/LaunchAgents/bot.coqui.agent.plist"
            echo "    Start:    launchctl load ~/Library/LaunchAgents/bot.coqui.agent.plist"
            echo "    Remove:   bash install.sh --install-service uninstall"
            ;;
    esac

    echo ""
    echo "  ${BOLD}API Endpoint:${RESET}  http://localhost:${SERVICE_PORT}"
    echo "  ${BOLD}API Key:${RESET}       stored in ${COQUI_INSTALL_DIR}/.workspace/.env"
    echo ""
}

# ─── Banner ──────────────────────────────────────────────────────────────────

show_banner() {
    echo ""
    echo "  ${BOLD}${GREEN}▄█████  ▄▄▄   ▄▄▄  ▄▄ ▄▄ ▄▄   █████▄  ▄▄▄ ▄▄▄▄▄▄${RESET}"
    echo "  ${BOLD}${GREEN}██     ██▀██ ██▀██ ██ ██ ██   ██▄▄██ ██▀██  ██  ${RESET}"
    echo "  ${BOLD}${GREEN}▀█████ ▀███▀ ▀███▀ ▀███▀ ██   ██▄▄█▀ ▀███▀  ██  ${RESET}"
    echo "  ${BOLD}${GREEN}                ▀▀                              ${RESET}"
    echo ""
    echo "  ${BOLD}Coqui Installer${RESET}"
    echo ""
}

# ─── Success message ─────────────────────────────────────────────────────────

print_success() {
    local install_type="$1"

    echo ""
    echo "  ──────────────────────────────────────────"
    echo "  ${BOLD}${GREEN}${install_type} complete!${RESET}"
    echo "  ──────────────────────────────────────────"
    echo ""
    echo "  ${BOLD}Get started:${RESET}"
    echo ""
    echo "    coqui"
    echo ""
    echo "  ${BOLD}Configuration:${RESET}"
    echo ""
    echo "    ${COQUI_INSTALL_DIR}/openclaw.json"
    echo ""
    echo "  ${BOLD}Add cloud providers${RESET} (optional):"
    echo ""
    echo "    export OPENAI_API_KEY=\"sk-...\""
    echo "    export ANTHROPIC_API_KEY=\"sk-ant-...\""
    echo ""
    echo "  ${BOLD}Prerequisites:${RESET}"
    echo ""
    echo "    Make sure Ollama is running:  ollama serve"
    echo "    Pull a model:                 ollama pull glm-4.7-flash"

    # Show service info if a service was installed or is present
    if [ "$SERVICE_INSTALLED" = true ] || is_service_installed; then
        print_service_info
    fi

    echo ""
    echo "  ${BOLD}Docs:${RESET}  https://github.com/AgentCoqui/coqui"
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    show_banner

    detect_os
    setup_sudo
    detect_init_system

    # ── Selective mode: run only the requested components ──
    if [ "$SELECTIVE_MODE" = true ]; then
        if [ "$INSTALL_PHP" = true ]; then
            check_php
            check_extensions
        fi

        if [ "$INSTALL_COMPOSER" = true ]; then
            # Composer needs PHP — verify it exists even if --install-php wasn't passed
            if ! available php; then
                fatal "PHP is required to install Composer. Re-run with --install-php or install PHP manually."
            fi
            check_composer
        fi

        if [ "$INSTALL_COQUI" = true ]; then
            if ! available php; then
                fatal "PHP is required to install Coqui. Re-run with --install-php or install PHP manually."
            fi
            if ! available composer; then
                fatal "Composer is required to install Coqui. Re-run with --install-composer or install Composer manually."
            fi
            check_git

            if is_installed; then
                update_coqui
            else
                install_coqui
            fi
            setup_config
            create_symlink

            # Auto-restart service if running after update
            if is_service_running; then
                status "Restarting service after update..."
                restart_service
                sleep 1
                if is_service_running; then
                    success "Service restarted"
                else
                    warn "Service may not have restarted. Check service logs."
                fi
            fi
        fi

        if [ "$INSTALL_SERVICE" = true ]; then
            if ! is_installed; then
                fatal "Coqui is not installed. Re-run with --install-coqui or run a full install first."
            fi
            install_service
            if [ "$SERVICE_INSTALLED" = true ]; then
                print_service_info
            fi
        fi

        echo ""
        success "Done"
        echo ""
        return
    fi

    # ── Full install (no flags — backward compatible) ──
    if is_installed; then
        echo "  ${ARROW} Existing installation found at ${COQUI_INSTALL_DIR}"
        echo ""

        check_php
        check_extensions
        check_composer

        update_coqui
        setup_config
        create_symlink

        # Auto-restart service if running after update
        if is_service_running; then
            status "Restarting service after update..."
            restart_service
            sleep 1
            if is_service_running; then
                success "Service restarted"
            else
                warn "Service may not have restarted. Check service logs."
            fi
        fi

        print_success "Update"
    else
        check_php
        check_extensions
        check_git
        check_composer

        install_coqui
        setup_config
        create_symlink

        # Offer service installation on fresh install
        if [ -n "$INIT_SYSTEM" ]; then
            echo ""
            if confirm "Would you like to install Coqui as a background API service?"; then
                install_service
            fi
        fi

        print_success "Installation"
    fi
}

# Wrap in main() so partial curl downloads don't execute incomplete script
main "$@"
