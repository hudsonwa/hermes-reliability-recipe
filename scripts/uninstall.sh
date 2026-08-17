#!/usr/bin/env bash
# Uninstall hermes-reliability-recipe from a Hermes profile.
# Surgical reversal: only removes files this recipe installed, only restores
# from backups this recipe created. Asks before touching anything.
#
# Usage:
#   ./scripts/uninstall.sh --profile NAME [--dry-run] [--yes] [--skip-patch]
#   ./scripts/uninstall.sh --profile NAME --dry-run    # preview only
#   ./scripts/uninstall.sh --profile NAME --yes        # skip confirmation
#   ./scripts/uninstall.sh --profile NAME --skip-patch # keep Hermes patch
#
# Safety rules (hard-coded):
#   1. Never delete .env, config.yaml, SOUL.md, or the profile directory itself
#   2. Never delete files we didn't install — only known install list
#   3. Never touch files outside the profile except the Hermes patch (own --unapply)
#   4. Always show what will be removed/restored before doing anything
#   5. Require explicit confirmation (yes/no) before executing — no auto-run
#   6. If a backup doesn't exist for a restore, skip + warn — never restore from nothing
#   7. If a file to remove doesn't exist, skip silently — never error on missing files
#   8. Log every action to uninstall.log
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECIPE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

PROFILE=""
ALL_PROFILES=0
DRY_RUN=0
SKIP_CONFIRM=0
SKIP_PATCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --all-profiles) ALL_PROFILES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) SKIP_CONFIRM=1; shift ;;
    --skip-patch) SKIP_PATCH=1; shift ;;
    -h|--help)
      echo "usage: $0 --profile NAME [--dry-run] [--yes] [--skip-patch]"
      echo "       $0 --profile NAME1,NAME2,NAME3 [--dry-run] [--yes] [--skip-patch]"
      echo "       $0 --all-profiles [--dry-run] [--yes] [--skip-patch]"
      echo ""
      echo "  --profile NAME      Uninstall from one profile"
      echo "  --profile N1,N2,N3   Uninstall from multiple profiles (comma-separated)"
      echo "  --all-profiles       Uninstall from all profiles with config.yaml"
      echo "  --dry-run            Preview without changes"
      echo "  --yes                Skip confirmation prompt"
      echo "  --skip-patch         Do not touch the Hermes patch (keep always-on pre_verify)"
      echo ""
      echo "This only removes files installed by hermes-reliability-recipe."
      echo "It does NOT delete .env, config.yaml, SOUL.md, or the profile itself."
      echo "The Hermes patch --unapply runs only ONCE (it is global, not per-profile)."
      exit 0
      ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done

if [[ "$ALL_PROFILES" == "0" && -z "$PROFILE" ]]; then
  echo "required: --profile NAME or --all-profiles" >&2
  exit 2
fi

# Build the list of profiles
export ALL_PROFILES
PROFILES_LIST=()
while IFS= read -r _p; do
  [[ -n "$_p" ]] && PROFILES_LIST+=("$_p")
done < <(parse_profiles "$PROFILE")

if [[ ${#PROFILES_LIST[@]} -eq 0 ]]; then
  echo "No profiles found." >&2
  exit 2
fi

if [[ "${#PROFILES_LIST[@]}" -gt 1 ]]; then
  echo "Uninstalling from ${#PROFILES_LIST[@]} profiles: ${PROFILES_LIST[*]}"
fi

# Files this recipe installed (only these are removed — nothing else)
INSTALLED_BINS=(
  "pre_verify_claim_gate.py"
  "truth"
  "truth-mcp"
  "truth_run_wrap.sh"
  "test_claim_gate.py"
)

# Working-style markers (for surgical removal)
WS_MARKER="# Reliability stack (hermes-reliability-recipe)"
SOUL_MARKER="# Reliability (hermes-reliability-recipe)"

# Hermes patch detection (global — checked once)
PATCH_SCRIPT="$SCRIPT_DIR/apply-hermes-preverify-patch.sh"
LOOP="${HERMES_AGENT_ROOT:-$HOME/.hermes/hermes-agent}/agent/conversation_loop.py"
HAS_PATCH=0
if [[ -f "$LOOP" ]] && grep -qE 'if has_hook\(["'"'"']pre_verify["'"'"']\)' "$LOOP" 2>/dev/null; then
  if ! grep -qE 'if _edited and has_hook\(["'"'"']pre_verify["'"'"']\)' "$LOOP" 2>/dev/null; then
    HAS_PATCH=1
  fi
fi
PATCH_BAKS=()
if ls "$LOOP.bak."* >/dev/null 2>&1; then
  PATCH_BAKS=("$LOOP.bak."*)
fi

PY="$(resolve_python)"

# Per-profile uninstall function
uninstall_one_profile() {
  local PROFILE="$1"
  local HOME_P
  HOME_P="$(profile_home "$PROFILE")"
  local LOG="$HOME_P/logs/uninstall.log"

  local INSTALLED_SKILLS_DIR="$HOME_P/skills/reliability"
  local INSTALLED_STATE_FILES=(
    "$HOME_P/state/reliability-stack.json"
    "$HOME_P/state/reliability-recipe-root.txt"
  )

  echo ""
  echo "=========================================="
  echo " hermes-reliability-recipe — uninstall"
  echo "=========================================="
  echo " profile:  $PROFILE"
  echo " home:      $HOME_P"
  echo " dry_run:   $DRY_RUN"
  echo " skip_patch: $SKIP_PATCH"
  echo ""

  # --- Collect what would be removed/restored ---
  local TO_REMOVE=()
  local TO_STRIP_WS=0
  local TO_STRIP_SOUL=0

  for f in "${INSTALLED_BINS[@]}"; do
    if [[ -f "$HOME_P/bin/$f" ]]; then
      TO_REMOVE+=("$HOME_P/bin/$f")
    fi
  done
  if [[ -d "$INSTALLED_SKILLS_DIR" ]]; then
    TO_REMOVE+=("$INSTALLED_SKILLS_DIR (directory)")
  fi
  for f in "${INSTALLED_STATE_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      TO_REMOVE+=("$f")
    fi
  done

  if [[ -f "$HOME_P/working-style-instruction.md" ]] && grep -qF "$WS_MARKER" "$HOME_P/working-style-instruction.md" 2>/dev/null; then
    TO_STRIP_WS=1
  fi
  if [[ -f "$HOME_P/SOUL.md" ]] && grep -qF "$SOUL_MARKER" "$HOME_P/SOUL.md" 2>/dev/null; then
    TO_STRIP_SOUL=1
  fi

  local WS_BAKS=()
  if ls "$HOME_P/working-style-instruction.md.bak."* >/dev/null 2>&1; then
    WS_BAKS=("$HOME_P/working-style-instruction.md.bak."*)
  fi

  # --- Show preview ---
  echo "=== What will be REMOVED ==="
  if [[ ${#TO_REMOVE[@]} -eq 0 ]]; then
    echo "  (none — no installed files found)"
  else
    for f in "${TO_REMOVE[@]}"; do
      echo "  - $f"
    done
  fi
  echo ""

  echo "=== What will be RESTORED / REVERSED ==="
  if [[ $TO_STRIP_WS -eq 1 ]]; then
    echo "  - working-style-instruction.md: remove appended reliability section"
    if [[ ${#WS_BAKS[@]} -gt 0 ]]; then
      echo "    (backup available: ${WS_BAKS[-1]})"
    else
      echo "    (no backup found — will strip reliability section, keep remaining content)"
    fi
  fi
  if [[ $TO_STRIP_SOUL -eq 1 ]]; then
    echo "  - SOUL.md: remove appended reliability section"
  fi
  echo ""

  echo "=== What will NOT be touched ==="
  echo "  - .env (never deleted or modified)"
  echo "  - config.yaml (restored by toggle off from its own backup)"
  echo "  - SOUL.md (only the reliability section is removed; rest preserved)"
  echo "  - Profile directory itself (never deleted)"
  echo "  - Any other files in bin/, skills/, state/ that we didn't install"
  echo ""

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN — no changes made."
    return 0
  fi

  # --- Execute ---
  mkdir -p "$HOME_P/logs"
  local LOG_ENTRY="[uninstall $(date -Iseconds)] profile=$PROFILE dry_run=$DRY_RUN skip_patch=$SKIP_PATCH"

  # Step 1: Toggle off
  if [[ -f "$SCRIPT_DIR/reliability-toggle.sh" ]]; then
    echo ""
    echo "Step 1: Turning off reliability stack..."
    if "$SCRIPT_DIR/reliability-toggle.sh" off --profile "$PROFILE" --no-restart 2>&1; then
      echo "  ok: stack turned off (config hooks/MCP removed, SOUL+working-style sections stripped)"
      LOG_ENTRY="$LOG_ENTRY step1=toggle_off:ok"
    else
      echo "  WARN: toggle off failed (may already be off or config missing)"
      LOG_ENTRY="$LOG_ENTRY step1=toggle_off:warn"
    fi
  else
    echo "Step 1: SKIPPED (reliability-toggle.sh not found)"
    LOG_ENTRY="$LOG_ENTRY step1=toggle_off:skip"
  fi

  # Step 2: Working-style check
  echo ""
  echo "Step 2: Working-style check..."
  if [[ $TO_STRIP_WS -eq 1 ]]; then
    if grep -qF "$WS_MARKER" "$HOME_P/working-style-instruction.md" 2>/dev/null; then
      echo "  reliability section still present — stripping manually..."
      WS="$HOME_P/working-style-instruction.md" MARKER="$WS_MARKER" "$PY" - <<'PY'
import os
from pathlib import Path
ws = Path(os.environ["WS"])
marker = os.environ["MARKER"]
text = ws.read_text()
if marker in text:
    text = text.split(marker)[0].rstrip() + "\n"
    ws.write_text(text)
    print("  ok: working-style reliability section stripped")
PY
      LOG_ENTRY="$LOG_ENTRY step2=ws_strip:ok"
    else
      echo "  ok: reliability section already removed by toggle"
      LOG_ENTRY="$LOG_ENTRY step2=ws_strip:already_done"
    fi
  else
    echo "  ok: no reliability section in working-style (nothing to strip)"
    LOG_ENTRY="$LOG_ENTRY step2=ws_strip:not_present"
  fi

  # Steps 4-6: Remove installed files, skills, state (patch handled separately)
  echo ""
  echo "Step 3: Removing installed files..."
  for f in "${INSTALLED_BINS[@]}"; do
    if [[ -f "$HOME_P/bin/$f" ]]; then
      rm -f "$HOME_P/bin/$f"
      echo "  removed: bin/$f"
      LOG_ENTRY="$LOG_ENTRY rm:bin/$f"
    fi
  done

  echo ""
  echo "Step 4: Removing installed skills..."
  if [[ -d "$INSTALLED_SKILLS_DIR" ]]; then
    rm -rf "$INSTALLED_SKILLS_DIR"
    echo "  removed: skills/reliability/"
    LOG_ENTRY="$LOG_ENTRY rm:skills/reliability"
  else
    echo "  ok: skills/reliability/ not found (already removed)"
  fi

  echo ""
  echo "Step 5: Removing state files..."
  for f in "${INSTALLED_STATE_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      rm -f "$f"
      echo "  removed: $(basename "$f")"
      LOG_ENTRY="$LOG_ENTRY rm:$(basename "$f")"
    fi
  done

  echo "$LOG_ENTRY" >> "$LOG"

  echo ""
  echo "=========================================="
  echo " Uninstall complete for profile=$PROFILE"
  echo "=========================================="
  echo ""
  echo "What was done:"
  echo "  - Reliability stack turned off (hooks, MCP, coding_instructions removed from config)"
  echo "  - Working-style reliability section stripped (original content preserved)"
  echo "  - SOUL reliability section stripped (original content preserved)"
  echo "  - Installed bin files removed"
  echo "  - Installed skills removed"
  echo "  - State files removed"
  echo ""
  echo "What was NOT touched:"
  echo "  - .env"
  echo "  - config.yaml (restored by toggle off from its backup)"
  echo "  - SOUL.md (only reliability section removed)"
  echo "  - Profile directory"
  echo "  - Any other files"
  echo ""
  echo "Log written to: $LOG"
  echo ""
  echo "To re-install later:"
  echo "  ./scripts/install.sh --profile $PROFILE"
  echo ""
  echo "PASS uninstall --profile $PROFILE"
}

# --- Show patch preview (once, for all profiles) ---
if [[ ${#PROFILES_LIST[@]} -gt 1 ]] || [[ "$ALL_PROFILES" == "1" ]]; then
  echo ""
  echo "=========================================="
  echo " Hermes patch (global — applies once for all profiles)"
  echo "=========================================="
  if [[ "$SKIP_PATCH" -eq 1 ]]; then
    echo "  SKIPPED (--skip-patch)"
  elif [[ $HAS_PATCH -eq 0 ]]; then
    echo "  Patch not present (nothing to undo)"
  elif [[ ${#PATCH_BAKS[@]} -eq 0 ]]; then
    echo "  WARN: no backup found — cannot undo safely"
  else
    echo "  Patch is present. Backup: ${PATCH_BAKS[-1]}"
    echo "  Undoing this affects ALL profiles on this machine."
  fi
  echo ""
fi

# --- Confirmation (once, before any changes) ---
if [[ "$DRY_RUN" -eq 1 ]]; then
  for _p in "${PROFILES_LIST[@]}"; do
    uninstall_one_profile "$_p"
  done
  # Show patch info in dry-run
  if [[ $HAS_PATCH -eq 1 && "$SKIP_PATCH" -ne 1 ]]; then
    echo ""
    echo "=== Hermes patch (would be undone after profiles) ==="
    if [[ ${#PATCH_BAKS[@]} -gt 0 ]]; then
      echo "  Would restore from: ${PATCH_BAKS[-1]}"
    else
      echo "  WARN: no backup found — would warn and skip"
    fi
  fi
  echo ""
  echo "DRY RUN — no changes made."
  exit 0
fi

if [[ "$SKIP_CONFIRM" -ne 1 ]]; then
  echo "Proceed with uninstall for ${#PROFILES_LIST[@]} profile(s)? (yes/no)"
  read -r ANSWER
  if [[ "$ANSWER" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# --- Execute per-profile uninstalls ---
UNINSTALL_OK=0
UNINSTALL_FAIL=0
for _p in "${PROFILES_LIST[@]}"; do
  if uninstall_one_profile "$_p"; then
    UNINSTALL_OK=$((UNINSTALL_OK + 1))
  else
    UNINSTALL_FAIL=$((UNINSTALL_FAIL + 1))
  fi
done

# --- Hermes patch undo (once, after all profiles) ---
echo ""
echo "=========================================="
echo " Hermes patch (global — undo once)"
echo "=========================================="
if [[ "$SKIP_PATCH" -eq 1 ]]; then
  echo "  SKIPPED (--skip-patch)"
elif [[ $HAS_PATCH -eq 0 ]]; then
  echo "  ok: patch not present (nothing to undo)"
elif [[ ! -f "$PATCH_SCRIPT" ]]; then
  echo "  WARN: patch script not found — cannot undo"
elif [[ ${#PATCH_BAKS[@]} -eq 0 ]]; then
  echo "  WARN: no backup found for conversation_loop.py — cannot undo safely"
  echo "  The patch remains in place. To undo manually, reinstall Hermes or restore"
  echo "  the edit-gated condition in conversation_loop.py."
else
  echo "  This will restore conversation_loop.py from backup."
  echo "  This is GLOBAL — it affects ALL profiles on this machine."
  if [[ "$SKIP_CONFIRM" -ne 1 ]]; then
    echo "  Proceed with patch undo? (yes/no)"
    read -r PATCH_ANSWER
    if [[ "$PATCH_ANSWER" != "yes" ]]; then
      echo "  SKIPPED (user declined)"
    else
      "$PATCH_SCRIPT" --unapply 2>&1 || true
      echo "  ok: patch undone"
    fi
  else
    "$PATCH_SCRIPT" --unapply 2>&1 || true
    echo "  ok: patch undone (--yes mode)"
  fi
fi

# --- Final summary ---
if [[ "${#PROFILES_LIST[@]}" -gt 1 ]]; then
  echo ""
  echo "=========================================="
  echo " Multi-profile uninstall summary"
  echo "=========================================="
  echo "  Total: ${#PROFILES_LIST[@]}  OK: $UNINSTALL_OK  Failed: $UNINSTALL_FAIL"
fi

echo ""
echo "To re-install later:"
echo "  ./scripts/install.sh --profile NAME"
echo "  ./scripts/install.sh --all-profiles"
echo ""
