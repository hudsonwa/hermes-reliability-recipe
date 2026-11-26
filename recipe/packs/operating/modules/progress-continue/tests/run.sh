#!/usr/bin/env bash
# progress-continue module tests (picked up by the pack's tests/test_pack.sh)
set -euo pipefail
cd "$(dirname "$0")"
PY="${PYTHON:-python3}"
"$PY" -c 'import pytest' 2>/dev/null || { echo "SKIP progress-continue tests (no pytest)"; exit 0; }
"$PY" -m pytest -q -p no:cacheprovider test_core.py
