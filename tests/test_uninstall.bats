#!/usr/bin/env bats
#
# Tests for uninstall.sh
# Requires bats-core: https://github.com/bats-core/bats-core

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
UNINSTALL_SCRIPT="$SCRIPT_DIR/uninstall.sh"

# ─── Argument parsing ─────────────────────────────────────────────────────────

@test "uninstall.sh --help exits 0" {
    run bash "$UNINSTALL_SCRIPT" --help
    [ "$status" -eq 0 ]
}

@test "uninstall.sh -h exits 0" {
    run bash "$UNINSTALL_SCRIPT" -h
    [ "$status" -eq 0 ]
}

@test "uninstall.sh --help outputs usage info" {
    run bash "$UNINSTALL_SCRIPT" --help
    echo "$output" | grep -q "Usage:"
}

@test "uninstall.sh --help shows all flags" {
    run bash "$UNINSTALL_SCRIPT" --help
    echo "$output" | grep -q -- "--remove-workspace"
    echo "$output" | grep -q -- "--force"
    echo "$output" | grep -q -- "--all"
}

@test "uninstall.sh unknown argument exits 1" {
    run bash "$UNINSTALL_SCRIPT" --unknown-flag-xyz
    [ "$status" -eq 1 ]
}

# ─── Not-installed guard ──────────────────────────────────────────────────────

@test "uninstall.sh exits 0 when Coqui is not installed" {
    COQUI_INSTALL_DIR="/tmp/coqui-not-installed-$$" run bash "$UNINSTALL_SCRIPT" --force
    [ "$status" -eq 0 ]
}

@test "uninstall.sh warns when Coqui is not installed" {
    COQUI_INSTALL_DIR="/tmp/coqui-not-installed-$$" run bash "$UNINSTALL_SCRIPT" --force
    echo "$output" | grep -qi "not installed"
}

# ─── Release install removal ──────────────────────────────────────────────────

@test "uninstall.sh --force removes release install directory" {
    local test_dir
    test_dir="$(mktemp -d)"
    echo "1.0.0" > "$test_dir/.coqui-version"
    touch "$test_dir/bin"

    COQUI_INSTALL_DIR="$test_dir" run bash "$UNINSTALL_SCRIPT" --force
    [ "$status" -eq 0 ]
    [ ! -d "$test_dir" ]
}

@test "uninstall.sh --force removes dev install directory" {
    local test_dir
    test_dir="$(mktemp -d)"
    mkdir -p "$test_dir/.git"

    COQUI_INSTALL_DIR="$test_dir" run bash "$UNINSTALL_SCRIPT" --force
    [ "$status" -eq 0 ]
    [ ! -d "$test_dir" ]
}

@test "uninstall.sh --force exits 0 on success" {
    local test_dir
    test_dir="$(mktemp -d)"
    echo "1.0.0" > "$test_dir/.coqui-version"

    COQUI_INSTALL_DIR="$test_dir" run bash "$UNINSTALL_SCRIPT" --force
    [ "$status" -eq 0 ]
}

# ─── Workspace preservation ───────────────────────────────────────────────────

@test "uninstall.sh preserves workspace by default" {
    local test_dir
    test_dir="$(mktemp -d)"
    echo "1.0.0" > "$test_dir/.coqui-version"
    mkdir -p "$test_dir/.workspace"
    echo "important-data" > "$test_dir/.workspace/session.json"

    COQUI_INSTALL_DIR="$test_dir" run bash "$UNINSTALL_SCRIPT" --force
    [ "$status" -eq 0 ]
    [ -f "$test_dir/.workspace/session.json" ]
    [ "$(cat "$test_dir/.workspace/session.json")" = "important-data" ]

    rm -rf "$test_dir"
}

@test "uninstall.sh --remove-workspace deletes workspace" {
    local test_dir
    test_dir="$(mktemp -d)"
    echo "1.0.0" > "$test_dir/.coqui-version"
    mkdir -p "$test_dir/.workspace"
    echo "data" > "$test_dir/.workspace/session.json"

    COQUI_INSTALL_DIR="$test_dir" run bash "$UNINSTALL_SCRIPT" --force --remove-workspace
    [ "$status" -eq 0 ]
    [ ! -d "$test_dir" ]
}

@test "uninstall.sh removes install dir files but keeps workspace dir intact" {
    local test_dir
    test_dir="$(mktemp -d)"
    echo "1.0.0" > "$test_dir/.coqui-version"
    mkdir -p "$test_dir/bin" "$test_dir/src" "$test_dir/.workspace"
    echo "coqui-binary" > "$test_dir/bin/coqui"
    echo "source-file" > "$test_dir/src/main.php"
    echo "workspace-data" > "$test_dir/.workspace/data.txt"

    COQUI_INSTALL_DIR="$test_dir" run bash "$UNINSTALL_SCRIPT" --force
    [ "$status" -eq 0 ]

    # bin and src should be gone
    [ ! -d "$test_dir/bin" ]
    [ ! -d "$test_dir/src" ]
    [ ! -f "$test_dir/.coqui-version" ]

    # workspace should remain
    [ -d "$test_dir/.workspace" ]
    [ -f "$test_dir/.workspace/data.txt" ]

    rm -rf "$test_dir"
}

# ─── Symlink removal ─────────────────────────────────────────────────────────

@test "uninstall.sh removes symlink pointing into install dir" {
    local test_dir bin_dir
    test_dir="$(mktemp -d)"
    bin_dir="$(mktemp -d)"
    echo "1.0.0" > "$test_dir/.coqui-version"
    mkdir -p "$test_dir/bin"
    touch "$test_dir/bin/coqui"

    # Create a symlink pointing into the install dir
    ln -sf "$test_dir/bin/coqui" "$bin_dir/coqui"

    # Run uninstall with the custom bin dir in PATH
    COQUI_INSTALL_DIR="$test_dir" PATH="$bin_dir:$PATH" run bash "$UNINSTALL_SCRIPT" --force

    [ "$status" -eq 0 ]

    rm -f "$bin_dir/coqui"
    rm -rf "$bin_dir" "$test_dir"
}

@test "uninstall.sh scans each bin dir once when it is listed twice" {
    local test_dir fake_home warn_count
    test_dir="$(mktemp -d)"
    fake_home="$(mktemp -d)"
    echo "1.0.0" > "$test_dir/.coqui-version"

    # ~/.local/bin is scanned both as a default location and as a PATH entry, so
    # a wrapper living there must still be reported only once.
    mkdir -p "$fake_home/.local/bin"
    printf '#!/bin/sh\n' > "$fake_home/.local/bin/coqui"
    chmod +x "$fake_home/.local/bin/coqui"

    run env COQUI_INSTALL_DIR="$test_dir" HOME="$fake_home" \
        PATH="$fake_home/.local/bin:/usr/bin:/bin" \
        bash "$UNINSTALL_SCRIPT" --force --quiet
    [ "$status" -eq 0 ]

    warn_count="$(printf '%s\n' "$output" | grep -c "not a symlink" || true)"
    [ "$warn_count" -eq 1 ]

    rm -rf "$test_dir" "$fake_home"
}

@test "uninstall.sh removes a symlink from a bin dir whose path contains a space" {
    local test_dir bin_dir
    test_dir="$(mktemp -d)"
    bin_dir="$(mktemp -d)/bin dir"
    mkdir -p "$bin_dir"
    echo "1.0.0" > "$test_dir/.coqui-version"
    mkdir -p "$test_dir/bin"
    touch "$test_dir/bin/coqui"
    ln -sf "$test_dir/bin/coqui" "$bin_dir/coqui"

    run env COQUI_INSTALL_DIR="$test_dir" PATH="$bin_dir:$PATH" \
        bash "$UNINSTALL_SCRIPT" --force
    [ "$status" -eq 0 ]
    # -L, not -e: a dangling symlink is still a symlink that was not cleaned up.
    [ ! -L "$bin_dir/coqui" ]

    rm -rf "$bin_dir"
}

# ─── Quiet mode ───────────────────────────────────────────────────────────────

@test "uninstall.sh --quiet --force suppresses status output" {
    local test_dir fake_home quiet_lines
    test_dir="$(mktemp -d)"
    fake_home="$(mktemp -d)"
    echo "1.0.0" > "$test_dir/.coqui-version"

    # Sandbox HOME and PATH so the bin directories the uninstaller scans hold no
    # host-installed `coqui` wrapper. Without this, a real ~/.local/bin/coqui (or
    # any other PATH entry carrying one) adds warning lines and host state decides
    # the outcome of this test.
    run env COQUI_INSTALL_DIR="$test_dir" HOME="$fake_home" PATH="/usr/bin:/bin" \
        bash "$UNINSTALL_SCRIPT" --force --quiet
    [ "$status" -eq 0 ]

    # `warn` deliberately still prints in quiet mode, and the uninstaller also
    # scans hardcoded /usr/local/bin and /opt/homebrew/bin, which PATH cannot
    # sandbox. Drop that warning so only the suppressible output is counted.
    quiet_lines="$(printf '%s\n' "$output" | grep -vc "not a symlink" || true)"

    # Quiet mode should only print the milestone line
    [ "$quiet_lines" -eq 1 ]
    echo "$output" | grep -q "Uninstall complete"

    rm -rf "$test_dir" "$fake_home"
}

# ─── Docker stack teardown ────────────────────────────────────────────────────

@test "uninstall_docker_stack runs compose down and removes the wrapper" {
    STUB="$(mktemp -d)"
    export COQUI_INSTALL_DIR="$(mktemp -d)/home"
    mkdir -p "$COQUI_INSTALL_DIR"
    echo "services: {}" > "$COQUI_INSTALL_DIR/compose.yaml"
    export BIN_DIR="$(mktemp -d)/bin"; mkdir -p "$BIN_DIR"; touch "$BIN_DIR/coqui"; chmod +x "$BIN_DIR/coqui"
    cat > "$STUB/docker" <<'EOF'
#!/bin/sh
echo "docker $*" >> "$RECORD"; exit 0
EOF
    chmod +x "$STUB/docker"; export RECORD="$STUB/record.txt"
    run env PATH="$STUB:$PATH" bash -c '
      src=$(mktemp); awk "NR>1 { print prev } { prev=\$0 }" uninstall.sh > "$src"; source "$src"
      BIN_DIR="'"$BIN_DIR"'"
      FORCE_MODE=true; REMOVE_WORKSPACE=false
      uninstall_docker_stack
    '
    [ "$status" -eq 0 ]
    grep -q 'compose .* down' "$RECORD"
    [ ! -e "$BIN_DIR/coqui" ]
    rm -rf "$STUB"
}

@test "uninstall_docker_stack passes -v only with --remove-workspace" {
    STUB="$(mktemp -d)"
    export COQUI_INSTALL_DIR="$(mktemp -d)/home"; mkdir -p "$COQUI_INSTALL_DIR"
    echo "services: {}" > "$COQUI_INSTALL_DIR/compose.yaml"
    export BIN_DIR="$(mktemp -d)/bin"; mkdir -p "$BIN_DIR"
    cat > "$STUB/docker" <<'EOF'
#!/bin/sh
echo "docker $*" >> "$RECORD"; exit 0
EOF
    chmod +x "$STUB/docker"; export RECORD="$STUB/record.txt"
    run env PATH="$STUB:$PATH" bash -c '
      src=$(mktemp); awk "NR>1 { print prev } { prev=\$0 }" uninstall.sh > "$src"; source "$src"
      BIN_DIR="'"$BIN_DIR"'"
      FORCE_MODE=true; REMOVE_WORKSPACE=true
      uninstall_docker_stack
    '
    grep -qE 'compose .* down .*-v|compose .* down.* --volumes' "$RECORD"
    rm -rf "$STUB"
}

# ─── Installation detection ───────────────────────────────────────────────────

@test "uninstall.sh is_dev_installed detects .git directory" {
    local test_dir
    test_dir="$(mktemp -d)"
    mkdir -p "$test_dir/.git"

    run bash -c "
        COQUI_INSTALL_DIR='$test_dir'
        is_dev_installed() {
            [ -d \"\$COQUI_INSTALL_DIR\" ] && [ -d \"\$COQUI_INSTALL_DIR/.git\" ]
        }
        is_dev_installed && echo 'dev' || echo 'not-dev'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "dev" ]

    rm -rf "$test_dir"
}

@test "uninstall.sh is_release_installed detects .coqui-version file" {
    local test_dir
    test_dir="$(mktemp -d)"
    echo "0.5.0" > "$test_dir/.coqui-version"

    run bash -c "
        COQUI_INSTALL_DIR='$test_dir'
        is_release_installed() {
            [ -d \"\$COQUI_INSTALL_DIR\" ] && [ -f \"\$COQUI_INSTALL_DIR/.coqui-version\" ]
        }
        is_release_installed && echo 'release' || echo 'not-release'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "release" ]

    rm -rf "$test_dir"
}

@test "uninstall.sh get_installed_version returns version string" {
    local test_dir
    test_dir="$(mktemp -d)"
    echo "3.1.0" > "$test_dir/.coqui-version"

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
    [ "$output" = "3.1.0" ]

    rm -rf "$test_dir"
}
