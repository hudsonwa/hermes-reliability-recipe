#!/usr/bin/env bash
# sync-from-kernel.sh — propagate shared reliability files from the private
# kernel checkout into this public export tree, deterministically.
#
#   ./scripts/sync-from-kernel.sh --kernel /path/to/hermes-reliability-recipe
#   ./scripts/sync-from-kernel.sh --kernel ... --check   (report drift, exit 1 on drift)
#
# Every propagated file must match the kernel byte-for-byte (except gate +
# tests, which may carry a publicize transform only if defined here).
# Exit codes: 0 = in sync, 1 = drift/check failed, 2 = usage error.
set -euo pipefail

KERNEL=""
CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kernel) KERNEL="$2"; shift 2 ;;
    --check) CHECK=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$KERNEL" ]] || { echo "Usage: $0 --kernel /path/to/hermes-reliability-recipe [--check]" >&2; exit 2; }
[[ -d "$KERNEL/recipe/bin" ]] || { echo "FAIL: $KERNEL does not look like the kernel repo" >&2; exit 2; }

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SELF_DIR/.." && pwd)"

# Files that must be identical in kernel and export. The public kernel is
# canonical for these; the export never carries kernel-only private tooling.
SYNC_FILES=(
  scripts/gt_suite.sh
  scripts/reliability-selfheal.sh
  scripts/reliability-toggle.sh
  scripts/check-scrub.sh
  scripts/uninstall.sh
  recipe/bin/pre_verify_claim_gate.py
  recipe/bin/test_claim_gate.py
  recipe/bin/seam_ledger.py
  recipe/bin/test_seam_ledger.py
  recipe/bin/claim_auditor.py
)

drift=0
for f in "${SYNC_FILES[@]}"; do
  if [[ ! -f "$ROOT/$f" ]]; then
    echo "MISSING in export: $f"; drift=1
    continue
  fi
  if ! cmp -s "$ROOT/$f" "$KERNEL/$f"; then
    if [[ $CHECK -eq 1 ]]; then
      echo "DRIFT: $f"
    else
      cp "$KERNEL/$f" "$ROOT/$f"
      echo "SYNCED: $f"
    fi
    drift=1
  fi
done

# Gate against private residue in anything copied from the kernel.
if ! bash "$ROOT/scripts/check-scrub.sh" >/dev/null 2>&1; then
  echo "FAIL: scrub gate — private needle detected after sync" >&2
  drift=1
fi

# Identity-needle pass: import the kernel's machine-local needle list when it
# exists (gitignored, operator-specific) and scan case-INSENSITIVELY — the
# generic scrub misses capitalized personal names.
NEEDLES_FILE="$KERNEL/scripts/scrub-needles.local"
if [[ -f "$NEEDLES_FILE" ]]; then
  while IFS= read -r needle; do
    [[ -z "$needle" || "$needle" == \#* ]] && continue
    if grep -rilF -- "$needle" "$ROOT" --exclude-dir=.git >/dev/null 2>&1; then
      echo "FAIL: identity needle '$needle' found in export after sync" >&2
      drift=1
    fi
  done < <(grep -vE '^\s*($|#)' "$NEEDLES_FILE" | head -50)
fi

if [[ $drift -eq 0 ]]; then
  echo "IN SYNC: export matches kernel on ${#SYNC_FILES[@]} files"
  exit 0
fi
[[ $CHECK -eq 1 ]] && exit 1 || exit 0
