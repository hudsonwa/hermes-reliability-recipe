#!/usr/bin/env bash
# Reliability self-heal: check → heal → recheck.
# Profile path ALWAYS from --profile / arg (ignore ambient HERMES_HOME).
# Usage:
#   reliability-selfheal.sh --profile NAME
#   reliability-selfheal.sh --profile NAME --check-only
#   reliability-selfheal.sh --profile NAME --force-heal
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
RECIPE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE=""
CHECK_ONLY=0
FORCE=0
# allow legacy: first positional profile
if [[ "${1:-}" != "" && "${1:-}" != --* ]]; then
  PROFILE="$1"; shift || true
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --check-only) CHECK_ONLY=1; shift ;;
    --force-heal) FORCE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$PROFILE" ]]; then
  echo "required: --profile NAME" >&2
  exit 2
fi

# NEVER trust ambient HERMES_HOME for target selection
export HOME_P="$(profile_home "$PROFILE")"
PY="$(resolve_python)"
LOG="$HOME_P/logs/reliability_selfheal.jsonl"
TOGGLE="$RECIPE_ROOT/scripts/reliability-toggle.sh"
GATE_CANONICAL="$RECIPE_ROOT/recipe/bin/pre_verify_claim_gate.py"
# optional recipe root override from prior install
if [[ -f "$HOME_P/state/reliability-recipe-root.txt" ]]; then
  MARKER=$(cat "$HOME_P/state/reliability-recipe-root.txt" 2>/dev/null || true)
  if [[ -n "$MARKER" && -f "$MARKER/scripts/reliability-toggle.sh" ]]; then
    RECIPE_ROOT="$MARKER"
    TOGGLE="$RECIPE_ROOT/scripts/reliability-toggle.sh"
    GATE_CANONICAL="$RECIPE_ROOT/recipe/bin/pre_verify_claim_gate.py"
  fi
fi
mkdir -p "$HOME_P/logs" "$HOME_P/scripts" "$HOME_P/bin" "$HOME_P/state"

diagnose() {
  HOME_P="$HOME_P" RECIPE="$RECIPE_ROOT" "$PY" - <<'PY'
import json, os, sys
from pathlib import Path
home = Path(os.environ["HOME_P"])
recipe = Path(os.environ.get("RECIPE", "")).expanduser()
cfg_path = home / "config.yaml"
state_path = home / "state" / "reliability-stack.json"
issues = []
if not cfg_path.exists():
    print(json.dumps({"ok": False, "issues": ["missing_config"], "home": str(home)}))
    sys.exit(0)
try:
    import yaml
    cfg = yaml.safe_load(cfg_path.read_text()) or {}
except Exception as e:
    print(json.dumps({"ok": False, "issues": [f"config_parse:{e}"], "home": str(home)}))
    sys.exit(0)

agent = cfg.get("agent") or {}
hooks = cfg.get("hooks") or {}
ms = cfg.get("mcp_servers") or {}
if not (isinstance(hooks, dict) and hooks.get("pre_verify")):
    issues.append("pre_verify_missing")
if not agent.get("verify_on_stop"):
    issues.append("verify_on_stop_off")
if "truth" not in (ms or {}):
    issues.append("truth_mcp_missing")
if not agent.get("coding_instructions"):
    issues.append("coding_instructions_missing")
if state_path.exists():
    try:
        if json.loads(state_path.read_text()).get("enabled") is False:
            issues.append("state_disabled")
    except Exception:
        issues.append("state_unreadable")
else:
    issues.append("state_missing")

gate_ok = False
for g in (
    home / "bin" / "pre_verify_claim_gate.py",
    recipe / "recipe" / "bin" / "pre_verify_claim_gate.py",
):
    if g.exists():
        gate_ok = True
        break
if not gate_ok:
    issues.append("gate_script_missing")
if not (home / "bin" / "truth-mcp").exists():
    issues.append("truth_bin_missing")
if not (home / "working-style-instruction.md").exists():
    issues.append("working_style_missing")
else:
    ws = (home / "working-style-instruction.md").read_text(errors="replace")
    marker = "# Reliability stack (hermes-reliability-recipe)"
    if marker not in ws or "LIE/HALLUCINATION" not in ws or "truth_run_wrap" not in ws.lower():
        issues.append("working_style_soft_missing")

print(json.dumps({"ok": len(issues) == 0, "issues": issues, "home": str(home)}))
PY
}

BEFORE=$(diagnose)
OK=$(echo "$BEFORE" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("ok"))')
ISSUES=$(echo "$BEFORE" | "$PY" -c 'import sys,json; print(",".join(json.load(sys.stdin).get("issues") or []))')
HOME_DIAG=$(echo "$BEFORE" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("home") or "")')

if [[ "$OK" == "True" && "$FORCE" != "1" ]]; then
  echo "{\"ts\":\"$(date -Iseconds 2>/dev/null || date)\",\"profile\":\"$PROFILE\",\"phase\":\"check\",\"ok\":true,\"home\":\"$HOME_DIAG\"}" >> "$LOG"
  if [[ -n "${SELFHEAL_VERBOSE:-}" ]]; then
    echo "OK $PROFILE home=$HOME_DIAG (no heal needed)"
  fi
  exit 0
fi

if [[ "$CHECK_ONLY" == "1" ]]; then
  echo "RELIABILITY CHECK FAIL profile=$PROFILE"
  echo "home: $HOME_DIAG"
  echo "issues: $ISSUES"
  exit 0
fi

HEAL_ACTIONS=()
if [[ -f "$GATE_CANONICAL" ]]; then
  cp -f "$GATE_CANONICAL" "$HOME_P/bin/pre_verify_claim_gate.py"
  chmod +x "$HOME_P/bin/pre_verify_claim_gate.py" 2>/dev/null || true
  HEAL_ACTIONS+=("synced_gate_script")
fi
# Restore soft working-style block when missing (enabled stack must keep LIE/truth_run bullets)
if [[ -f "$RECIPE_ROOT/recipe/templates/working-style-instruction.md" ]]; then
  if ! profile_has_ws_soft_block "$HOME_P"; then
    if ws_h="$(ensure_working_style_soft_block "$HOME_P" "$RECIPE_ROOT")"; then
      HEAL_ACTIONS+=("restored_working_style_soft:$ws_h")
    else
      HEAL_ACTIONS+=("restored_working_style_soft_failed:$ws_h")
    fi
  fi
fi
for s in reliability-selfheal.sh doctor.sh reap-stale-hermes.sh lib.sh reliability-toggle.sh; do
  if [[ -f "$RECIPE_ROOT/scripts/$s" ]]; then
    cp -f "$RECIPE_ROOT/scripts/$s" "$HOME_P/scripts/$s"
    chmod +x "$HOME_P/scripts/$s"
  fi
done
if [[ -x "$TOGGLE" ]]; then
  if GATE_PY="$HOME_P/bin/pre_verify_claim_gate.py" \
      "$TOGGLE" on --profile "$PROFILE" --no-restart >/tmp/hrr-selfheal-toggle.out 2>&1; then
    HEAL_ACTIONS+=("toggle_on")
  else
    HEAL_ACTIONS+=("toggle_on_failed")
  fi
else
  HEAL_ACTIONS+=("toggle_missing")
fi

AFTER=$(diagnose)
OK2=$(echo "$AFTER" | "$PY" -c 'import sys,json; print("1" if json.load(sys.stdin).get("ok") else "0")')
ISSUES2=$(echo "$AFTER" | "$PY" -c 'import sys,json; print(",".join(json.load(sys.stdin).get("issues") or []))')
echo "{\"ts\":\"$(date -Iseconds 2>/dev/null || date)\",\"profile\":\"$PROFILE\",\"phase\":\"heal\",\"home\":\"$HOME_DIAG\",\"before\":\"$ISSUES\",\"actions\":\"${HEAL_ACTIONS[*]:-}\",\"after_ok\":$OK2,\"after\":\"$ISSUES2\"}" >> "$LOG"

if [[ "$OK2" == "1" ]]; then
  if [[ -n "${SELFHEAL_VERBOSE:-}" ]]; then
    echo "HEALED $PROFILE actions=${HEAL_ACTIONS[*]:-none}"
  fi
  exit 0
fi

echo "RELIABILITY SELF-HEAL FAILED"
echo "profile=$PROFILE"
echo "home: $HOME_DIAG"
echo "before: $ISSUES"
echo "actions: ${HEAL_ACTIONS[*]:-none}"
echo "after: $ISSUES2"
echo "log: $LOG"
exit 0
