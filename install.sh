#!/usr/bin/env bash

# Coqui Installer
# https://github.com/AgentCoqui/coqui
#
# Terminal AI agent with multi-model orchestration, persistent sessions,
# and runtime extensibility via Composer.
#
# Install with:
#   curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh | bash

set -eu

# ─── Configuration (override via environment variables) ──────────────────────

COQUI_REPO="${COQUI_REPO:-https://github.com/AgentCoqui/coqui.git}"
COQUI_INSTALL_DIR="${COQUI_INSTALL_DIR:-$HOME/.coqui}"
COQUI_VERSION="${COQUI_VERSION:-}"

# Minimum PHP version required
REQUIRED_PHP_MAJOR=8
REQUIRED_PHP_MINOR=4

# PHP extensions required by Coqui and php-agents
REQUIRED_EXTENSIONS="curl mbstring pdo_sqlite xml zip"

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

    # Non-interactive — assume yes
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
            fi
            ;;
        Darwin)
            # shellcheck disable=SC2034
            DISTRO="macos"
            if available brew; then
                PKG_MANAGER="brew"
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
            echo ""
            echo "  Install PHP via Homebrew:"
            echo ""
            echo "    brew install php@${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}"
            echo ""
            fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
            ;;
        dnf|yum)
            echo ""
            echo "  Install PHP via ${PKG_MANAGER}:"
            echo ""
            echo "    sudo ${PKG_MANAGER} install php-cli php-curl php-mbstring php-xml php-zip php-intl php-pdo"
            echo ""
            fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
            ;;
        pacman)
            echo ""
            echo "  Install PHP via pacman:"
            echo ""
            echo "    sudo pacman -S php php-sqlite php-intl"
            echo ""
            fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
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
    else
        echo ""
        echo "  Please install the following PHP extensions:${missing}"
        echo ""
        fatal "Required extensions missing."
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
            fatal "git is required. Install it with: brew install git"
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

# ─── Banner ──────────────────────────────────────────────────────────────────

show_banner() {
    echo ""
    echo "  ${BOLD}${GREEN}  ___                  _  ${RESET}"
    echo "  ${BOLD}${GREEN} / __| ___   __ _ _  _(_) ${RESET}"
    echo "  ${BOLD}${GREEN}| (__ / _ \\ / _\` | || | | ${RESET}"
    echo "  ${BOLD}${GREEN} \\___|\\___/ \\__, |\\_,_|_| ${RESET}"
    echo "  ${BOLD}${GREEN}              |_|         ${RESET}"
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
    echo ""
    echo "  ${BOLD}Docs:${RESET}  https://github.com/AgentCoqui/coqui"
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    show_banner

    detect_os
    setup_sudo

    if is_installed; then
        echo "  ${ARROW} Existing installation found at ${COQUI_INSTALL_DIR}"
        echo ""

        check_php
        check_extensions
        check_composer

        update_coqui
        setup_config
        create_symlink

        print_success "Update"
    else
        check_php
        check_extensions
        check_git
        check_composer

        install_coqui
        setup_config
        create_symlink

        print_success "Installation"
    fi
}

# Wrap in main() so partial curl downloads don't execute incomplete script
main "$@"
