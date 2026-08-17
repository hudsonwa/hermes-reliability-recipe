#!/usr/bin/env bash
# Download blasrodri/truth for this OS/arch with SHA256 verify against
# checksums pinned in this repo (not only the checksum file from the same release).
# Usage: fetch-truth.sh [--dest DIR] [--version v0.3.15]
set -euo pipefail
VERSION="${TRUTH_VERSION:-v0.3.15}"
DEST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    -h|--help) echo "usage: $0 [--dest DIR] [--version vX.Y.Z]"; exit 0 ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="${DEST:-$REPO/recipe/bin}"
mkdir -p "$DEST"

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Darwin) OS_TAG="apple-darwin" ;;
  Linux) OS_TAG="unknown-linux-gnu" ;;
  *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac
case "$ARCH" in
  arm64|aarch64) ARCH_TAG="aarch64" ;;
  x86_64|amd64) ARCH_TAG="x86_64" ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

ASSET="truth-${VERSION}-${ARCH_TAG}-${OS_TAG}.tar.gz"
PREFIX="truth-${VERSION}-${ARCH_TAG}-${OS_TAG}"
BASE="https://github.com/blasrodri/truth/releases/download/${VERSION}"
URL="${BASE}/${ASSET}"
PIN_FILE="$REPO/recipe/checksums/truth-${VERSION}.sha256"
if [[ ! -f "$PIN_FILE" ]]; then
  echo "FAIL: no pinned checksum file at $PIN_FILE" >&2
  echo "  Refusing to trust a checksum downloaded from the same GitHub release." >&2
  echo "  Add recipe/checksums/truth-${VERSION}.sha256 (reviewed) and retry." >&2
  exit 1
fi
PINNED=$(awk -v a="$ASSET" '$2==a {print $1; found=1} END{if(!found) exit 1}' "$PIN_FILE") || {
  echo "FAIL: $ASSET not listed in $PIN_FILE" >&2
  exit 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Fetching $URL"
curl -fsSL -o "$TMP/$ASSET" "$URL"

if command -v shasum >/dev/null 2>&1; then
  GOT=$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  GOT=$(sha256sum "$TMP/$ASSET" | awk '{print $1}')
else
  echo "No shasum/sha256sum" >&2; exit 1
fi
if [[ "$GOT" != "$PINNED" ]]; then
  echo "SHA256 mismatch for $ASSET (pinned checksum)" >&2
  echo " expected $PINNED" >&2
  echo " got      $GOT" >&2
  exit 1
fi
echo "checksum OK (pinned $PIN_FILE)"

# Extract only the expected member names (no archive walk / zip-slip find).
if ! tar -tzf "$TMP/$ASSET" | grep -qx "${PREFIX}/truth"; then
  echo "FAIL: archive missing ${PREFIX}/truth" >&2
  tar -tzf "$TMP/$ASSET" >&2
  exit 1
fi
tar -xzf "$TMP/$ASSET" -C "$TMP" "${PREFIX}/truth"
if tar -tzf "$TMP/$ASSET" | grep -qx "${PREFIX}/truth-mcp"; then
  tar -xzf "$TMP/$ASSET" -C "$TMP" "${PREFIX}/truth-mcp"
fi

TRUTH_SRC="$TMP/${PREFIX}/truth"
MCP_SRC="$TMP/${PREFIX}/truth-mcp"
if [[ ! -f "$TRUTH_SRC" ]]; then
  echo "truth binary not found after extract" >&2
  exit 1
fi
cp -f "$TRUTH_SRC" "$DEST/truth"
chmod +x "$DEST/truth"
if [[ -f "$MCP_SRC" ]]; then
  cp -f "$MCP_SRC" "$DEST/truth-mcp"
  chmod +x "$DEST/truth-mcp"
else
  echo "WARN: truth-mcp not in archive" >&2
fi

# Verify the binary actually runs on this system (catches GLIBC mismatches)
if ! "$DEST/truth" --version >/tmp/hrr-truth-ver.out 2>/tmp/hrr-truth-ver.err \
   && ! "$DEST/truth" --help >/tmp/hrr-truth-ver.out 2>/tmp/hrr-truth-ver.err; then
  echo "FAIL: truth binary downloaded but does not run on this system." >&2
  echo "  This usually means the OS GLIBC is too old for the prebuilt binary." >&2
  echo "  truth $VERSION typically needs GLIBC 2.32+ (Ubuntu 22.04+, Debian 12+)." >&2
  echo "  Your libc:" >&2
  ldd --version 2>&1 | head -1 >&2 || true
  echo "  Error output:" >&2
  cat /tmp/hrr-truth-ver.err 2>/dev/null | head -5 >&2 || true
  echo "  Workarounds:" >&2
  echo "    - Use Ubuntu 22.04+ or Debian 12+ (recommended for WSL2)" >&2
  echo "    - Or install without truth layer: continue install; claim gate still works" >&2
  echo "    - Or build truth from source: https://github.com/blasrodri/truth" >&2
  rm -f "$DEST/truth" "$DEST/truth-mcp"
  exit 1
fi
cat /tmp/hrr-truth-ver.out 2>/dev/null | head -3 || true
echo "Installed truth → $DEST"
echo "PASS fetch-truth $VERSION $ARCH_TAG-$OS_TAG"
