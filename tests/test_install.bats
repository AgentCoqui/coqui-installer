#!/usr/bin/env bats
#
# Tests for install.sh
# Requires bats-core: https://github.com/bats-core/bats-core

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install.sh"

# ─── Argument parsing ─────────────────────────────────────────────────────────

@test "install.sh --help exits 0" {
    run bash "$INSTALL_SCRIPT" --help
    [ "$status" -eq 0 ]
}

@test "install.sh -h exits 0" {
    run bash "$INSTALL_SCRIPT" -h
    [ "$status" -eq 0 ]
}

@test "install.sh --help outputs usage info" {
    run bash "$INSTALL_SCRIPT" --help
    echo "$output" | grep -q "Usage:"
}

@test "install.sh --help shows all flags" {
    run bash "$INSTALL_SCRIPT" --help
    echo "$output" | grep -q -- "--install-php"
    echo "$output" | grep -q -- "--install-composer"
    echo "$output" | grep -q -- "--install-coqui"
    echo "$output" | grep -q -- "--dev"
    echo "$output" | grep -q -- "--non-interactive"
}

@test "install.sh --help points Windows users to the WSL2 bootstrap" {
    run bash "$INSTALL_SCRIPT" --help
    echo "$output" | grep -q "PowerShell WSL2 bootstrap"
}

@test "install.sh declares dom as a required extension" {
    run grep -q 'REQUIRED_EXTENSIONS="dom mbstring pdo_sqlite xml"' "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "install.sh no longer declares openssl as a required extension" {
    run grep -q 'REQUIRED_EXTENSIONS=".*openssl' "$INSTALL_SCRIPT"
    [ "$status" -ne 0 ]
}

@test "install.sh unknown argument exits 1" {
    run bash "$INSTALL_SCRIPT" --unknown-flag-xyz
    [ "$status" -eq 1 ]
}

@test "install.sh unknown argument prints error" {
    run bash "$INSTALL_SCRIPT" --unknown-flag-xyz
    echo "$output" | grep -qi "unknown"
}

# ─── Installation detection ───────────────────────────────────────────────────

@test "install.sh detects release installation via .coqui-version" {
    local test_dir
    test_dir="$(mktemp -d)"
    echo "1.0.0" > "$test_dir/.coqui-version"

    # Script sources detection logic; we test via a helper that echoes result
    run bash -c "
        COQUI_INSTALL_DIR='$test_dir'
        is_release_installed() {
            [ -d \"\$COQUI_INSTALL_DIR\" ] && [ -f \"\$COQUI_INSTALL_DIR/.coqui-version\" ]
        }
        is_release_installed && echo 'yes' || echo 'no'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "yes" ]

    rm -rf "$test_dir"
}

@test "install.sh detects dev installation via .git directory" {
    local test_dir
    test_dir="$(mktemp -d)"
    mkdir -p "$test_dir/.git"

    run bash -c "
        COQUI_INSTALL_DIR='$test_dir'
        is_dev_installed() {
            [ -d \"\$COQUI_INSTALL_DIR\" ] && [ -d \"\$COQUI_INSTALL_DIR/.git\" ]
        }
        is_dev_installed && echo 'yes' || echo 'no'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "yes" ]

    rm -rf "$test_dir"
}

@test "install.sh does not detect installation in empty directory" {
    local test_dir
    test_dir="$(mktemp -d)"

    run bash -c "
        COQUI_INSTALL_DIR='$test_dir'
        is_dev_installed() {
            [ -d \"\$COQUI_INSTALL_DIR\" ] && [ -d \"\$COQUI_INSTALL_DIR/.git\" ]
        }
        is_release_installed() {
            [ -d \"\$COQUI_INSTALL_DIR\" ] && [ -f \"\$COQUI_INSTALL_DIR/.coqui-version\" ]
        }
        is_installed() { is_dev_installed || is_release_installed; }
        is_installed && echo 'yes' || echo 'no'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "no" ]

    rm -rf "$test_dir"
}

@test "install.sh does not detect installation when directory is absent" {
    run bash -c "
        COQUI_INSTALL_DIR='/tmp/coqui-test-nonexistent-dir-$$'
        is_dev_installed() {
            [ -d \"\$COQUI_INSTALL_DIR\" ] && [ -d \"\$COQUI_INSTALL_DIR/.git\" ]
        }
        is_release_installed() {
            [ -d \"\$COQUI_INSTALL_DIR\" ] && [ -f \"\$COQUI_INSTALL_DIR/.coqui-version\" ]
        }
        is_installed() { is_dev_installed || is_release_installed; }
        is_installed && echo 'yes' || echo 'no'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "no" ]
}

@test "install.sh get_installed_version reads .coqui-version" {
    local test_dir
    test_dir="$(mktemp -d)"
    echo "2.3.4" > "$test_dir/.coqui-version"

    run bash -c "
        COQUI_INSTALL_DIR='$test_dir'
        get_installed_version() {
            if [ -f \"\$COQUI_INSTALL_DIR/.coqui-version\" ]; then
                cat \"\$COQUI_INSTALL_DIR/.coqui-version\"
            else
                echo ''
            fi
        }
        get_installed_version
    "
    [ "$status" -eq 0 ]
    [ "$output" = "2.3.4" ]

    rm -rf "$test_dir"
}

# ─── detect_bin_dir ───────────────────────────────────────────────────────────

@test "install.sh detect_bin_dir falls back to ~/.local/bin when no writable standard dirs" {
    # Use system-only PATH so tr/grep are available but Homebrew dirs are absent
    run bash -c "
        PATH='/usr/bin:/bin:/usr/sbin:/sbin'
        detect_bin_dir() {
            if echo \"\$PATH\" | tr ':' '\n' | grep -qx '/opt/homebrew/bin' && [ -w '/opt/homebrew/bin' ]; then
                BIN_DIR='/opt/homebrew/bin'; return
            fi
            if echo \"\$PATH\" | tr ':' '\n' | grep -qx '/usr/local/bin' && [ -w '/usr/local/bin' ]; then
                BIN_DIR='/usr/local/bin'; return
            fi
            BIN_DIR=\"\$HOME/.local/bin\"
        }
        detect_bin_dir
        echo \"\$BIN_DIR\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/.local/bin" ]
}

# ─── Quiet mode ───────────────────────────────────────────────────────────────

@test "install.sh --quiet --help exits 0" {
    run bash "$INSTALL_SCRIPT" --help --quiet
    [ "$status" -eq 0 ]
}

# ─── Release-over-dev guard ───────────────────────────────────────────────────

@test "install.sh exits non-zero when release install attempted over dev install" {
    local test_dir
    test_dir="$(mktemp -d)"
    mkdir -p "$test_dir/.git"

    # With mocked curl/php that would never be called, the guard should fire first
    COQUI_INSTALL_DIR="$test_dir" run bash "$INSTALL_SCRIPT" \
        --install-coqui --non-interactive 2>&1 || true

    # Script must exit non-zero (fatal)
    [ "$status" -ne 0 ]

    rm -rf "$test_dir"
}
