#!/usr/bin/env bats

setup() { ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"; CADDYFILE="$ROOT/docker/Caddyfile"; }

@test "Caddyfile exists" {
    [ -f "$CADDYFILE" ]
}

@test "still proxies /api/* to the loopback-bound API" {
    grep -q 'handle /api/\*' "$CADDYFILE"
    grep -q 'reverse_proxy 127.0.0.1:3300' "$CADDYFILE"
}

@test "serves the bundled runtime config at /config.json" {
    grep -q 'handle /config.json' "$CADDYFILE"
    grep -q '"bundled":true' "$CADDYFILE"
    grep -q '"apiBaseUrl":"/api/v1"' "$CADDYFILE"
    grep -q 'Content-Type application/json' "$CADDYFILE"
}

@test "the /config.json route is declared before the SPA catch-all" {
    cfg_line="$(grep -n 'handle /config.json' "$CADDYFILE" | head -1 | cut -d: -f1)"
    spa_line="$(grep -n 'try_files' "$CADDYFILE" | head -1 | cut -d: -f1)"
    [ -n "$cfg_line" ]
    [ -n "$spa_line" ]
    [ "$cfg_line" -lt "$spa_line" ]
}

@test "caddy validates the Caddyfile (if caddy is available)" {
    if ! command -v caddy >/dev/null 2>&1; then skip "caddy not installed"; fi
    run caddy validate --adapter caddyfile --config "$CADDYFILE"
    [ "$status" -eq 0 ]
}
