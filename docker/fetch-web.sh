#!/usr/bin/env sh
# Fetch the coqui-app web bundle into <dest_dir>.
# Usage: fetch-web.sh <app_version> <dest_dir>
# Modes (in priority order):
#   COQUI_WEB_STUB=1     -> write a minimal placeholder index.html (CI plumbing tests)
#   WEB_TARBALL_URL=...  -> fetch that exact URL
#   else                 -> fetch the release asset for <app_version>
set -eu

# Portable sha256 of a file (macOS ships `shasum`, not `sha256sum`). Prints the
# hash only. Returns non-zero if no sha256 tool is available.
_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        return 127
    fi
}

APP_VERSION="${1:-}"
DEST="${2:?dest dir required}"
mkdir -p "$DEST"

if [ "${COQUI_WEB_STUB:-0}" = "1" ]; then
    cat > "${DEST}/index.html" <<'HTML'
<!doctype html>
<html><head><meta charset="utf-8"><title>Coqui (stub)</title></head>
<body><h1>Coqui web placeholder</h1><p>CI plumbing stub — not the real UI.</p></body></html>
HTML
    echo "fetch-web: wrote stub placeholder"
    exit 0
fi

# VERIFY=1 only on the real-release (version-constructed) path. The
# WEB_TARBALL_URL override intentionally BYPASSES integrity verification (you
# are pointing at an arbitrary URL you control); the COQUI_WEB_STUB path exits
# earlier and never reaches here.
VERIFY=0
if [ -n "${WEB_TARBALL_URL:-}" ]; then
    URL="$WEB_TARBALL_URL"
else
    [ -n "$APP_VERSION" ] || { echo "fetch-web: app version required when no WEB_TARBALL_URL/stub" >&2; exit 1; }
    TARBALL_NAME="Coqui-${APP_VERSION}-web.tar.gz"
    URL="https://github.com/carmelosantana/coqui-app/releases/download/v${APP_VERSION}/${TARBALL_NAME}"
    SUMS_URL="https://github.com/carmelosantana/coqui-app/releases/download/v${APP_VERSION}/SHA256SUMS.txt"
    VERIFY=1
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "fetch-web: downloading ${URL}"
curl -fsSL "$URL" -o "${TMP}/web.tar.gz" || { echo "fetch-web: download failed: ${URL}" >&2; exit 1; }

if [ "$VERIFY" = "1" ]; then
    # Fail closed: require a sha256 tool and a matching entry in SHA256SUMS.txt.
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        echo "fetch-web: no sha256 tool (sha256sum or shasum) found — cannot verify web bundle" >&2; exit 1
    fi
    echo "fetch-web: verifying ${TARBALL_NAME} against ${SUMS_URL}"
    curl -fsSL "$SUMS_URL" -o "${TMP}/SHA256SUMS.txt" || { echo "fetch-web: could not download checksums: ${SUMS_URL}" >&2; exit 1; }
    EXPECTED="$(grep -E "[[:space:]]${TARBALL_NAME}\$" "${TMP}/SHA256SUMS.txt" | awk '{print $1}' | head -1)"
    [ -n "$EXPECTED" ] || { echo "fetch-web: no checksum for ${TARBALL_NAME} in SHA256SUMS.txt" >&2; exit 1; }
    ACTUAL="$(_sha256 "${TMP}/web.tar.gz")"
    [ "$EXPECTED" = "$ACTUAL" ] || { echo "fetch-web: checksum mismatch for ${TARBALL_NAME} (expected ${EXPECTED}, got ${ACTUAL})" >&2; exit 1; }
    echo "fetch-web: checksum verified"
fi

tar -xzf "${TMP}/web.tar.gz" -C "$DEST"
[ -f "${DEST}/index.html" ] || { echo "fetch-web: bundle missing index.html" >&2; exit 1; }
echo "fetch-web: done"
