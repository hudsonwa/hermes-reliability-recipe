#!/usr/bin/env bash
# Fail if secrets / private-export leftovers appear in text sources.
#
# This file MUST NOT contain real host names, personal names, chat IDs, or tokens.
# Maintainer extra needles live in scripts/scrub-needles.local (gitignored).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FAIL=0

TEXT_LIST=$(mktemp)
NEEDLE_FILE="${SCRUB_NEEDLES_FILE:-$ROOT/scripts/scrub-needles.local}"
trap 'rm -f "$TEXT_LIST"' EXIT

find . \
  \( -path './.git' -o -path './.hermes' -o -path './vendor' -o -path './.truth' \
     -o -path './.truth-stamps' -o -path './sync' -o -path './recipe/bin/truth' \
     -o -path './recipe/bin/truth-mcp' \) -prune -o \
  -type f \
  \( -name '*.md' -o -name '*.py' -o -name '*.sh' -o -name '*.yml' -o -name '*.yaml' \
     -o -name '*.json' -o -name '*.toml' -o -name '*.txt' -o -name '*.example' \
     -o -name 'Makefile' -o -name 'LICENSE' -o -name '*.sha256' \) \
  ! -name '.*' \
  ! -name '._*' \
  ! -name 'LAST_SYNC.json' \
  ! -name 'scrub-needles.local' \
  -print >"$TEXT_LIST"

echo "== scrub check =="

# --- class 1: high-signal secret material ---
SECRET_RE='BEGIN (OPENSSH |RSA |EC |DSA )?PRIVATE KEY|github_pat_[0-9A-Za-z_]{20,}|ghp_[0-9A-Za-z]{20,}|gho_[0-9A-Za-z]{20,}|sk-ant-[0-9A-Za-z_-]{20,}|sk-proj-[0-9A-Za-z_-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,}'
# Telegram bot tokens look like 123456789:AA.... (35+ char secret). Placeholders like 123456:ABC... must not match.
TELEGRAM_BOT_RE='[0-9]{8,12}:[A-Za-z0-9_-]{30,}'

while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  if grep -nE "$SECRET_RE" -- "$f" >/dev/null 2>&1; then
    echo "FAIL secret-class match in $f"
    grep -nE "$SECRET_RE" -- "$f" | head -5
    FAIL=1
  fi
  if grep -nE "$TELEGRAM_BOT_RE" -- "$f" >/dev/null 2>&1; then
    echo "FAIL telegram-bot-token-shaped string in $f"
    grep -nE "$TELEGRAM_BOT_RE" -- "$f" | head -5
    FAIL=1
  fi
done <"$TEXT_LIST"

# --- class 2: non-empty secret assignments in templates/docs ---
tok_hits=$(grep -nE 'TELEGRAM_BOT_TOKEN=.' recipe/templates docs 2>/dev/null | grep -v 'TELEGRAM_BOT_TOKEN=$' | grep -v 'TELEGRAM_BOT_TOKEN=\.\.\.' || true)
if [[ -n "$tok_hits" ]]; then
  echo "FAIL non-empty TELEGRAM_BOT_TOKEN assignment"
  echo "$tok_hits"
  FAIL=1
else
  echo "  ok: no non-empty TELEGRAM_BOT_TOKEN values in templates/docs"
fi

# --- class 3: optional maintainer needles (never committed) ---
if [[ -f "$NEEDLE_FILE" ]]; then
  echo "  using extra needles: $NEEDLE_FILE"
  while IFS= read -r pat || [[ -n "${pat:-}" ]]; do
    [[ -z "$pat" || "$pat" == \#* ]] && continue
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      if grep -nF -e "$pat" -- "$f" >/dev/null 2>&1; then
        echo "FAIL extra needle in $f"
        grep -nF -e "$pat" -- "$f" | head -5
        FAIL=1
      fi
    done <"$TEXT_LIST"
  done <"$NEEDLE_FILE"
  if [[ "$FAIL" -eq 0 ]]; then
    echo "  ok: extra maintainer needles absent from published tree"
  fi
else
  echo "  ok: no extra needles file (CI / public clone path)"
fi

# --- class 4: truth binaries must not be tracked ---
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked_truth=$(git ls-files 'recipe/bin/truth' 'recipe/bin/truth-mcp' 2>/dev/null || true)
  if [[ -n "$tracked_truth" ]]; then
    echo "FAIL: truth binaries must not be tracked in git (fetch at install)"
    FAIL=1
  else
    echo "  ok: truth bins not tracked"
  fi
  if git ls-files --error-unmatch scripts/scrub-needles.local >/dev/null 2>&1; then
    echo "FAIL: scripts/scrub-needles.local must not be tracked"
    FAIL=1
  fi
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "SCRUB FAILED"
  exit 1
fi
echo "PASS scrub"
