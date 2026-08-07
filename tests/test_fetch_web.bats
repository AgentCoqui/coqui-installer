#!/usr/bin/env bats

setup() {
    SCRIPT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/docker/fetch-web.sh"
    DEST_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export PATH="$STUB_DIR:$PATH"
}
teardown() { rm -rf "$DEST_DIR" "$STUB_DIR"; }

@test "stub mode writes a placeholder index.html" {
    run env COQUI_WEB_STUB=1 bash "$SCRIPT" 0.0.0 "$DEST_DIR"
    [ "$status" -eq 0 ]
    [ -f "$DEST_DIR/index.html" ]
    grep -qi "coqui" "$DEST_DIR/index.html"
}

@test "WEB_TARBALL_URL override is fetched and extracted" {
    # Build a fake web tarball and a curl stub that serves it.
    WEB_FIX="$(mktemp -d)"
    echo "<html>real</html>" > "$WEB_FIX/index.html"
    ( cd "$WEB_FIX" && tar -czf "$STUB_DIR/web.tar.gz" . )
    cat > "$STUB_DIR/curl" <<EOF
#!/bin/sh
out=""; while [ \$# -gt 0 ]; do [ "\$1" = "-o" ] && out="\$2"; shift; done
[ -n "\$out" ] && cp "$STUB_DIR/web.tar.gz" "\$out"
EOF
    chmod +x "$STUB_DIR/curl"
    run env WEB_TARBALL_URL="http://example/web.tar.gz" bash "$SCRIPT" 0.0.0 "$DEST_DIR"
    [ "$status" -eq 0 ]
    grep -q "real" "$DEST_DIR/index.html"
    rm -rf "$WEB_FIX"
}
