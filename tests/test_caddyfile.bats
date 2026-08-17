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
    grep -q '^[[:space:]]*handle /config\.json' "$CADDYFILE"
    # Byte-identical body — a stray space anywhere in the JSON must fail here.
    grep -qF 'respond `{"bundled":true,"apiBaseUrl":"/api/v1"}` 200' "$CADDYFILE"
    grep -q 'Content-Type application/json' "$CADDYFILE"
}

@test "the /config.json route reads before the SPA catch-all (readability, not correctness)" {
    # File order is NOT what makes this route win. Caddy sorts `handle` blocks
    # within a site by path-matcher specificity, and a matcher-less `handle`
    # sorts last regardless of where it appears — so the exact-path
    # `handle /config.json` would beat the SPA catch-all even if written below it.
    # This test guards readability/intent only: the file should read in the order
    # it is evaluated. The container smoke step in
    # .github/workflows/docker-image.yml is the actual correctness guard.
    cfg_line="$(grep -n '^[[:space:]]*handle /config\.json' "$CADDYFILE" | head -1 | cut -d: -f1)"
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
