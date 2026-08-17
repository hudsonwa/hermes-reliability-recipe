#!/usr/bin/env bash
# Record a command receipt via blasrodri/truth, then run it.
# Usage: truth_run_wrap.sh [--] <cmd> [args...]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRUTH_BIN="${TRUTH_BIN:-$SCRIPT_DIR/truth}"
if [[ ! -x "$TRUTH_BIN" ]]; then
  if command -v truth >/dev/null 2>&1; then
    TRUTH_BIN="$(command -v truth)"
  else
    echo "truth binary missing: set TRUTH_BIN or install via scripts/fetch-truth.sh" >&2
    exec "$@"
  fi
fi
if [[ "${1:-}" == "--" ]]; then shift; fi
if [[ $# -lt 1 ]]; then
  echo "usage: $0 [--] <cmd> [args...]" >&2
  exit 2
fi
if [[ ! -f truth.toml && ! -f .truth/truth.toml ]]; then
  "$TRUTH_BIN" init >/dev/null 2>&1 || true
fi
exec "$TRUTH_BIN" run -- "$@"
