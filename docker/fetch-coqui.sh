#!/usr/bin/env sh
# Fetch, verify (fail-closed), and extract a coqui server release.
# Usage: fetch-coqui.sh <version> <dest_dir>
#   <version>  release version without leading v, e.g. 0.0.1
#   <dest_dir> directory to place the extracted server (gets bin/, vendor/, ...)
set -eu

VERSION="${1:?version required}"
DEST="${2:?dest dir required}"

OWNER="carmelosantana"
REPO="coqui"
BASE="https://github.com/${OWNER}/${REPO}/releases/download"
ARCHIVE="coqui-v${VERSION}.tar.gz"
URL="${BASE}/v${VERSION}/${ARCHIVE}"
CHECKSUM_URL="${URL}.sha256"

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

# Fail closed: an integrity tool (sha256sum or shasum) must be available.
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "fetch-coqui: no sha256 tool (sha256sum or shasum) found — refusing to install unverified release" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "fetch-coqui: downloading ${URL}"
curl -fsSL "$URL" -o "${TMP}/${ARCHIVE}" \
    || { echo "fetch-coqui: download failed: ${URL}" >&2; exit 1; }

echo "fetch-coqui: verifying checksum"
EXPECTED="$(curl -fsSL "$CHECKSUM_URL" 2>/dev/null | awk '{print $1}')" \
    || { echo "fetch-coqui: could not fetch checksum ${CHECKSUM_URL} — refusing unverified install" >&2; exit 1; }
[ -n "$EXPECTED" ] || { echo "fetch-coqui: empty checksum — refusing unverified install" >&2; exit 1; }
ACTUAL="$(_sha256 "${TMP}/${ARCHIVE}")"
if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "fetch-coqui: Checksum mismatch. Expected ${EXPECTED}, got ${ACTUAL}" >&2
    exit 1
fi

echo "fetch-coqui: extracting to ${DEST}"
tar -xzf "${TMP}/${ARCHIVE}" -C "$TMP"
[ -d "${TMP}/coqui" ] || { echo "fetch-coqui: archive missing top-level coqui/ dir" >&2; exit 1; }
mkdir -p "$DEST"
cp -a "${TMP}/coqui/." "$DEST/"
echo "$VERSION" > "${DEST}/.coqui-version"
chmod +x "${DEST}/bin/coqui" "${DEST}/bin/coqui-console" 2>/dev/null || true
echo "fetch-coqui: done"
