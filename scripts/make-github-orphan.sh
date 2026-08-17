#!/usr/bin/env bash
# Build a history-free sibling git repo for first GitHub publish.
# Does NOT rewrite this repo. Does NOT push.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$SRC/../hermes-reliability-recipe-github}"
OUT="$(mkdir -p "$OUT" && cd "$OUT" && pwd)"

if [[ -d "$OUT/.git" ]]; then
  echo "FAIL: $OUT already has a .git — pick a fresh directory" >&2
  exit 2
fi

echo "Exporting scrubbed tree → $OUT"
rsync -a --delete \
  --exclude '.git/' \
  --exclude '.hermes/' \
  --exclude '.truth/' \
  --exclude '.truth-stamps/' \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude '.DS_Store' \
  --exclude '._*' \
  --exclude '.env' \
  --exclude 'recipe/bin/truth' \
  --exclude 'recipe/bin/truth-mcp' \
  --exclude 'scripts/scrub-needles.local' \
  --exclude 'sync/LAST_SYNC.json' \
  "$SRC/" "$OUT/"

# Refuse to export if the destination still has maintainer needles file
if [[ -f "$OUT/scripts/scrub-needles.local" ]]; then
  echo "FAIL: needles file leaked into export" >&2
  exit 1
fi

(
  cd "$OUT"
  bash scripts/check-scrub.sh
  git init -b main
  NAME="${GIT_AUTHOR_NAME:-hermes-reliability-recipe contributors}"
  EMAIL="${GIT_AUTHOR_EMAIL:-noreply@users.noreply.github.com}"
  git -c user.name="$NAME" -c user.email="$EMAIL" add -A
  if git ls-files --error-unmatch scripts/scrub-needles.local >/dev/null 2>&1; then
    echo "FAIL: needles file staged" >&2
    exit 1
  fi
  git -c user.name="$NAME" -c user.email="$EMAIL" \
      commit -m "$(cat <<'EOF'
feat: public hermes-reliability-recipe kernel

Unofficial fail-closed reliability stack for Hermes Agent.
EOF
)"
)

echo "PASS orphan export at $OUT"
echo "Next: review git log in that directory, then push with human GO."
