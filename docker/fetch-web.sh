#!/usr/bin/env sh
# Fetch the coqui-app web bundle into <dest_dir>.
# Usage: fetch-web.sh <app_version> <dest_dir>
# Modes (in priority order):
#   COQUI_WEB_STUB=1     -> write a minimal placeholder index.html (CI plumbing tests)
#   WEB_TARBALL_URL=...  -> fetch that exact URL
#   else                 -> fetch the release asset for <app_version>
set -eu

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

if [ -n "${WEB_TARBALL_URL:-}" ]; then
    URL="$WEB_TARBALL_URL"
else
    [ -n "$APP_VERSION" ] || { echo "fetch-web: app version required when no WEB_TARBALL_URL/stub" >&2; exit 1; }
    URL="https://github.com/carmelosantana/coqui-app/releases/download/v${APP_VERSION}/Coqui-${APP_VERSION}-web.tar.gz"
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "fetch-web: downloading ${URL}"
curl -fsSL "$URL" -o "${TMP}/web.tar.gz" || { echo "fetch-web: download failed: ${URL}" >&2; exit 1; }
tar -xzf "${TMP}/web.tar.gz" -C "$DEST"
[ -f "${DEST}/index.html" ] || { echo "fetch-web: bundle missing index.html" >&2; exit 1; }
echo "fetch-web: done"
