#!/usr/bin/env bash
# Check or apply always-on pre_verify patch for Hermes conversation_loop.py
# Upstream historically gated pre_verify on file edits; pure lies skipped the gate.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECIPE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
ACTION="check"
HERMES_ROOT="${HERMES_AGENT_ROOT:-$HOME/.hermes/hermes-agent}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) ACTION=check; shift ;;
    --apply) ACTION=apply; shift ;;
    --unapply) ACTION=unapply; shift ;;
    --hermes-root) HERMES_ROOT="$2"; shift 2 ;;
    -h|--help)
      echo "usage: $0 [--check|--apply|--unapply] [--hermes-root DIR]"
      echo ""
      echo "  --check    Verify the patch is in place (no changes made)"
      echo "  --apply    Apply the patch (backs up the original first)"
      echo "  --unapply  Restore conversation_loop.py from the most recent backup"
      echo "             This is GLOBAL — affects all profiles on this machine."
      echo "  --hermes-root DIR  Override Hermes install location"
      exit 0
      ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done

LOOP="$HERMES_ROOT/agent/conversation_loop.py"
if [[ ! -f "$LOOP" ]]; then
  echo "FAIL: conversation_loop not found at $LOOP"
  write_stamp "$RECIPE_ROOT" "03-patch" "FAIL" "missing_loop"
  exit 1
fi

edit_gated() {
  grep -qE 'if _edited and has_hook\(["'\'']pre_verify["'\'']\)' "$LOOP"
}
always_on() {
  grep -qE 'if has_hook\(["'\'']pre_verify["'\'']\)' "$LOOP" \
    && ! edit_gated
}

if [[ "$ACTION" == "check" ]]; then
  if always_on; then
    echo "PASS always-on pre_verify in $LOOP"
    write_stamp "$RECIPE_ROOT" "03-patch" "PASS" "$LOOP"
    exit 0
  elif edit_gated; then
    echo "FAIL: pre_verify still edit-gated in $LOOP"
    echo "Run: $0 --apply --hermes-root $HERMES_ROOT"
    write_stamp "$RECIPE_ROOT" "03-patch" "FAIL" "edit_gated"
    exit 1
  else
    echo "FAIL: could not find pre_verify condition in $LOOP"
    write_stamp "$RECIPE_ROOT" "03-patch" "FAIL" "not_found"
    exit 1
  fi
fi

# unapply — restore from most recent .bak
if [[ "$ACTION" == "unapply" ]]; then
  if [[ ! -f "$LOOP" ]]; then
    echo "FAIL: conversation_loop not found at $LOOP"
    write_stamp "$RECIPE_ROOT" "03-patch" "FAIL" "missing_loop_unapply"
    exit 1
  fi
  # Find the most recent backup
  LATEST_BAK=$(ls -t "$LOOP".bak.* 2>/dev/null | head -1)
  if [[ -z "$LATEST_BAK" ]]; then
    echo "FAIL: no backup file found at $LOOP.bak.*"
    echo "Cannot restore — no backup exists. You may need to reinstall Hermes"
    echo "or re-apply the edit-gated condition manually."
    write_stamp "$RECIPE_ROOT" "03-patch" "FAIL" "no_backup"
    exit 1
  fi
  echo "Restoring conversation_loop.py from: $LATEST_BAK"
  echo "NOTE: This is GLOBAL — affects all profiles on this machine."
  cp -a "$LATEST_BAK" "$LOOP"
  # Verify the restore (should now be edit-gated again)
  if edit_gated; then
    echo "PASS restored (pre_verify is now edit-gated again)"
    echo "NOTE: restart gateways using this Hermes install for the change to take effect."
    write_stamp "$RECIPE_ROOT" "03-patch" "FAIL" "unapplied"
    exit 0
  elif always_on; then
    echo "WARN: restored but pre_verify still always-on — backup may have been pre-patched"
    write_stamp "$RECIPE_ROOT" "03-patch" "PASS" "restore_inconclusive"
    exit 0
  else
    echo "PASS restored (pre_verify condition no longer found — original state)"
    write_stamp "$RECIPE_ROOT" "03-patch" "FAIL" "unapplied_no_condition"
    exit 0
  fi
fi

# apply
if always_on; then
  echo "already always-on; nothing to do"
  write_stamp "$RECIPE_ROOT" "03-patch" "PASS" "already"
  exit 0
fi

cp -a "$LOOP" "$LOOP.bak.$(date +%Y%m%d-%H%M%S)"
# Python rewrite of the condition line
PY_BIN="$(resolve_python)"
LOOP="$LOOP" "$PY_BIN" - <<'PY'
import os, re
from pathlib import Path
p = Path(os.environ["LOOP"])
text = p.read_text()
# common form
pat = re.compile(
    r'if\s+_edited\s+and\s+has_hook\(\s*["\']pre_verify["\']\s*\)\s+and\s+_attempt\s*<\s*max_verify_nudges\(\)\s*:'
)
rep = 'if has_hook("pre_verify") and _attempt < max_verify_nudges():'
new, n = pat.subn(rep, text, count=1)
if n == 0:
    pat2 = re.compile(
        r'if\s+_edited\s+and\s+has_hook\(\s*["\']pre_verify["\']\s*\)\s*:'
    )
    rep2 = 'if has_hook("pre_verify"):'
    new, n = pat2.subn(rep2, text, count=1)
if n == 0:
    raise SystemExit("could not locate edit-gated pre_verify condition to patch")
p.write_text(new)
print(f"patched {n} occurrence(s)")
PY

if always_on; then
  echo "PASS applied always-on pre_verify → $LOOP"
  echo "NOTE: restart gateways using this Hermes install for the change to take effect."
  write_stamp "$RECIPE_ROOT" "03-patch" "PASS" "applied"
  exit 0
fi
echo "FAIL: patch ran but check still fails"
write_stamp "$RECIPE_ROOT" "03-patch" "FAIL" "post_apply"
exit 1
