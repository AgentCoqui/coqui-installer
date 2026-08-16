#!/usr/bin/env bats

setup() { ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"; COMPOSE="$ROOT/compose.yaml"; }

# PyYAML ships with python3 on the Linux CI runner but not on the macOS runner;
# the YAML-parse checks skip cleanly where it is unavailable (the grep-based
# structural checks below still run everywhere, and Linux CI validates the YAML).
_have_pyyaml() { python3 -c "import yaml" >/dev/null 2>&1; }

@test "compose.yaml exists and is valid YAML" {
    [ -f "$COMPOSE" ]
    _have_pyyaml || skip "PyYAML not available"
    python3 -c "import yaml; yaml.safe_load(open('$COMPOSE'))"
}

@test "declares exactly one coqui service on the ghcr image" {
    grep -q 'ghcr.io/carmelosantana/coqui-stack' "$COMPOSE"
    _have_pyyaml || skip "PyYAML not available"
    run python3 -c "import yaml; d=yaml.safe_load(open('$COMPOSE')); s=list(d['services']); assert len(s)==1 and s==['coqui'], s"
    [ "$status" -eq 0 ]
}

@test "publishes port 8080 and persists config + data" {
    grep -qE '8080:8080|:8080"' "$COMPOSE"
    grep -q '/config' "$COMPOSE"
    grep -q '/data' "$COMPOSE"
    grep -q 'restart: unless-stopped' "$COMPOSE"
}

@test "binds to loopback (127.0.0.1) by default via COQUI_BIND" {
    grep -qE '"\$\{COQUI_BIND:-127\.0\.0\.1\}:\$\{COQUI_PORT:-8080\}:8080"' "$COMPOSE"
}

@test "documents host.docker.internal for Linux" {
    grep -q 'host-gateway' "$COMPOSE"
}

@test "docker compose config parses (if docker is available)" {
    if ! command -v docker >/dev/null 2>&1; then skip "docker not installed"; fi
    run docker compose -f "$COMPOSE" config
    [ "$status" -eq 0 ]
}
