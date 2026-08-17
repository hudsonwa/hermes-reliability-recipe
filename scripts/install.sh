#!/usr/bin/env bash
# Install reliability stack into a Hermes profile.
# Usage:
#   install.sh --profile NAME [--lab-yolo] [--fetch-truth] [--skip-truth]
#   install.sh --profile NAME1,NAME2,NAME3 [--lab-yolo]
#   install.sh --all-profiles [--lab-yolo]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
RECIPE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE=""
ALL_PROFILES=0
LAB_YOLO="${LAB_YOLO:-0}"
FETCH_TRUTH=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --all-profiles) ALL_PROFILES=1; shift ;;
    --lab-yolo) LAB_YOLO=1; shift ;;
    --fetch-truth) FETCH_TRUTH=1; shift ;;
    --skip-truth) FETCH_TRUTH=0; shift ;;
    -h|--help)
      echo "usage: $0 --profile NAME [--lab-yolo] [--skip-truth]"
      echo "       $0 --profile NAME1,NAME2,NAME3 [--lab-yolo]"
      echo "       $0 --all-profiles [--lab-yolo]"
      echo ""
      echo "  --profile NAME         Install into one profile"
      echo "  --profile N1,N2,N3     Install into multiple profiles (comma-separated)"
      echo "  --all-profiles         Discover and install into all profiles with config.yaml"
      echo "  --lab-yolo             Also set approvals.mode=off (lab machines only)"
      echo "  --skip-truth           Skip truth binary download (already fetched)"
      exit 0
      ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done
if [[ "$ALL_PROFILES" == "0" && -z "$PROFILE" ]]; then
  echo "required: --profile NAME or --all-profiles" >&2
  exit 2
fi

# Build the list of profiles to install into
export ALL_PROFILES
PROFILES_LIST=()
while IFS= read -r _p; do
  [[ -n "$_p" ]] && PROFILES_LIST+=("$_p")
done < <(parse_profiles "$PROFILE")

if [[ ${#PROFILES_LIST[@]} -eq 0 ]]; then
  echo "No profiles found. Create one with: hermes profile create NAME" >&2
  exit 2
fi

require_lab_yolo_confirm || exit 2

if [[ "${#PROFILES_LIST[@]}" -gt 1 ]]; then
  echo "Installing into ${#PROFILES_LIST[@]} profiles: ${PROFILES_LIST[*]}"
fi

# Fetch truth once (shared across all profiles)
if [[ "$FETCH_TRUTH" == "1" ]]; then
  "$SCRIPT_DIR/fetch-truth.sh" --dest "$RECIPE_ROOT/recipe/bin"
fi

# Per-profile install function
install_one_profile() {
  local PROFILE="$1"
  local HOME_P
  HOME_P="$(profile_home "$PROFILE")"
  echo ""
  echo "==== Installing into profile=$PROFILE ===="
  echo "Installing hermes-reliability-recipe into $HOME_P"
  mkdir -p "$HOME_P"/{bin,skills/reliability,memories,logs,state,scripts}

  if [[ ! -d "$HOME_P" ]] || [[ ! -f "$HOME_P/config.yaml" ]]; then
    if command -v hermes >/dev/null 2>&1; then
      echo "Profile config missing — try: hermes profile create $PROFILE"
    fi
    echo "WARN: $HOME_P/config.yaml not found; files will still be copied"
  fi

  # bins
  cp -f "$RECIPE_ROOT/recipe/bin/"*.py "$HOME_P/bin/" 2>/dev/null || true
  cp -f "$RECIPE_ROOT/recipe/bin/truth_run_wrap.sh" "$HOME_P/bin/" 2>/dev/null || true
  [[ -x "$RECIPE_ROOT/recipe/bin/truth" ]] && cp -f "$RECIPE_ROOT/recipe/bin/truth" "$HOME_P/bin/truth"
  [[ -x "$RECIPE_ROOT/recipe/bin/truth-mcp" ]] && cp -f "$RECIPE_ROOT/recipe/bin/truth-mcp" "$HOME_P/bin/truth-mcp"
  chmod +x "$HOME_P/bin/"* 2>/dev/null || true

  # ops scripts
  for s in reliability-toggle.sh reliability-selfheal.sh doctor.sh reap-stale-hermes.sh fetch-truth.sh lib.sh; do
    if [[ -f "$SCRIPT_DIR/$s" ]]; then
      cp -f "$SCRIPT_DIR/$s" "$HOME_P/scripts/$s"
      chmod +x "$HOME_P/scripts/$s"
    fi
  done

  # working style — SURGICAL via shared helper (never overwrite existing prose)
  local WS_STATUS=""
  if ! WS_STATUS="$(ensure_working_style_soft_block "$HOME_P" "$RECIPE_ROOT")"; then
    echo "FAIL: working-style soft block missing after ensure ($WS_STATUS)" >&2
    return 1
  fi
  case "$WS_STATUS" in
    installed) echo "working-style-instruction.md installed from template (no prior file existed)" ;;
    appended)  echo "working-style: reliability soft block appended (existing content preserved)" ;;
    skipped)   echo "working-style: reliability soft block already present (skipped)" ;;
    *)         echo "working-style: $WS_STATUS" ;;
  esac
  # Post-condition: stack soft layer must be on disk (no silent skip/fail)
  if ! profile_has_ws_soft_block "$HOME_P"; then
    echo "FAIL: postcondition — profile working-style lacks LIE/truth_run soft block" >&2
    return 1
  fi

  # SOUL — SURGICAL: back up existing, then append reliability section (never overwrite)
  local SOUL_TARGET="$HOME_P/SOUL.md"
  local SOUL_TEMPLATE="$RECIPE_ROOT/recipe/templates/SOUL.reliability.md"
  local SOUL_MARKER="# Reliability (hermes-reliability-recipe)"

  if [[ -f "$SOUL_TARGET" ]]; then
    local SOUL_BAK="$SOUL_TARGET.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$SOUL_TARGET" "$SOUL_BAK"
    echo "Backed up existing SOUL.md → $SOUL_BAK"

    if grep -qF "$SOUL_MARKER" "$SOUL_TARGET" 2>/dev/null; then
      echo "SOUL: reliability section already present (skipped)"
    else
      cat >> "$SOUL_TARGET" <<'SOUL'

# Reliability (hermes-reliability-recipe)
- Never invent file paths, byte/line counts, test results, or corpus stats.
- Do not claim DONE/green/ship without tool proof from THIS workspace.
- Prefer honest PARTIAL or FAILED over a polished false success.
- Wrong-directory test greens do not count.
- Host / live facts (disk, git, processes, fleet status, "what's on this machine"): use tools this turn, or say BLOCKED. Do not answer from memory alone.
- MEMORY.md and notes are an index, not live state. Re-read files or run commands for current facts.
- Never describe tool use in prose without actually calling tools.
- If the user says check / verify / thoroughly: call at least one real tool before the final answer.
SOUL
      echo "SOUL: reliability section appended (existing content preserved)"
    fi
  else
    cp -f "$SOUL_TEMPLATE" "$SOUL_TARGET"
    echo "SOUL.md installed from template (no prior file existed)"
  fi

  # Upgrade older reliability SOUL blocks missing host-facts bullets
  if [[ -f "$SOUL_TARGET" ]] && grep -qF "$SOUL_MARKER" "$SOUL_TARGET" 2>/dev/null \
    && ! grep -qF 'Host / live facts' "$SOUL_TARGET" 2>/dev/null; then
    cat >> "$SOUL_TARGET" <<'SOULUP'

- Host / live facts (disk, git, processes, fleet status, "what's on this machine"): use tools this turn, or say BLOCKED. Do not answer from memory alone.
- MEMORY.md and notes are an index, not live state. Re-read files or run commands for current facts.
- Never describe tool use in prose without actually calling tools.
- If the user says check / verify / thoroughly: call at least one real tool before the final answer.
SOULUP
    echo "SOUL: host-facts bullets upgraded"
  fi

  # skills
  mkdir -p "$HOME_P/skills/reliability"
  cp -rf "$RECIPE_ROOT/recipe/skills/reliability/." "$HOME_P/skills/reliability/" 2>/dev/null || true

  # env example only if missing
  if [[ ! -f "$HOME_P/.env" && -f "$RECIPE_ROOT/recipe/templates/env.example" ]]; then
    cp -f "$RECIPE_ROOT/recipe/templates/env.example" "$HOME_P/.env"
    echo "Created $HOME_P/.env from example — HUMAN must fill secrets"
  fi

  # marker so selfheal finds recipe
  echo "$RECIPE_ROOT" > "$HOME_P/state/reliability-recipe-root.txt"

  export LAB_YOLO
  if [[ -f "$HOME_P/config.yaml" ]]; then
    GATE_PY="$HOME_P/bin/pre_verify_claim_gate.py" \
      LAB_YOLO="$LAB_YOLO" \
      "$SCRIPT_DIR/reliability-toggle.sh" on --profile "$PROFILE" --no-restart
  else
    echo "skip toggle (no config.yaml)"
  fi

  write_stamp "$RECIPE_ROOT" "02-files" "PASS" "profile=$PROFILE"
  echo ""
  echo "=========================================="
  echo " Install complete for profile=$PROFILE"
  echo "=========================================="
  echo ""
  echo "What was added:"
  echo "  - Claim gate: $HOME_P/bin/pre_verify_claim_gate.py"
  echo "  - Truth tools: $HOME_P/bin/truth, truth-mcp, truth_run_wrap.sh"
  echo "  - Skills: $HOME_P/skills/reliability/"
  echo "  - Working-style soft block: $WS_STATUS (marker + LIE banner + truth_run_wrap verified)"
  if grep -qF "# Reliability (hermes-reliability-recipe)" "$HOME_P/SOUL.md" 2>/dev/null; then
    echo "  - SOUL: reliability section present"
  else
    echo "  - SOUL: reliability section MISSING (unexpected)"
  fi
  echo "  - Config: hooks + MCP + coding_instructions + verify_on_stop added"
  echo ""
  echo "What was NOT changed:"
  echo "  - .env (only created if it didn't exist)"
  echo "  - Your profile directory"
  echo ""
  echo "Still need to do (human):"
  echo "  1) Fill secrets in $HOME_P/.env if needed"
  echo "  2) Set model base_url in $HOME_P/config.yaml if using a local model"
  echo "  3) $RECIPE_ROOT/scripts/apply-hermes-preverify-patch.sh --check  (see docs/HERMES-PATCH.md)"
  echo "  4) $RECIPE_ROOT/scripts/doctor.sh --profile $PROFILE"
  echo "  5) Gateway restart only with explicit GO (optional, not required)"
  echo ""
  echo "To undo everything later:"
  echo "  $RECIPE_ROOT/scripts/uninstall.sh --profile $PROFILE --dry-run"
  echo ""
  echo "PASS install --profile $PROFILE"
}

# Run install for each profile
INSTALL_OK=0
INSTALL_FAIL=0
for _p in "${PROFILES_LIST[@]}"; do
  if install_one_profile "$_p"; then
    INSTALL_OK=$((INSTALL_OK + 1))
  else
    INSTALL_FAIL=$((INSTALL_FAIL + 1))
    echo "FAIL install --profile $_p" >&2
  fi
done

if [[ "${#PROFILES_LIST[@]}" -gt 1 ]]; then
  echo ""
  echo "=========================================="
  echo " Multi-profile install summary"
  echo "=========================================="
  echo "  Total: ${#PROFILES_LIST[@]}  OK: $INSTALL_OK  Failed: $INSTALL_FAIL"
  echo ""
  echo "Next steps (human):"
  echo "  1) Fill secrets in each profile's .env if needed"
  echo "  2) $RECIPE_ROOT/scripts/apply-hermes-preverify-patch.sh --check  (once — patch is global)"
  echo "  3) $RECIPE_ROOT/scripts/doctor.sh --profile NAME  (run per profile)"
  echo "  4) Gateway restart only with explicit GO (optional, not required)"
  echo ""
  echo "To undo all later:"
  echo "  $RECIPE_ROOT/scripts/uninstall.sh --all-profiles --dry-run"
fi

if [[ "$INSTALL_FAIL" -gt 0 ]]; then
  exit 1
fi
