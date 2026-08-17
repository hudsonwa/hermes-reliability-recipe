#!/usr/bin/env bash
# Doctor: single PASS/FAIL for reliability stack health.
# Usage: doctor.sh --profile NAME [--require-gateway] [--require-patch]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
RECIPE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE=""
REQUIRE_GW=0
REQUIRE_PATCH=1
ALLOW_NO_TRUTH=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --require-gateway) REQUIRE_GW=1; shift ;;
    --require-patch) REQUIRE_PATCH=1; shift ;;
    --skip-patch) REQUIRE_PATCH=0; shift ;;
    --allow-no-truth) ALLOW_NO_TRUTH=1; shift ;;
    -h|--help)
      echo "usage: $0 --profile NAME [--require-gateway] [--skip-patch] [--allow-no-truth]"
      echo ""
      echo "  --allow-no-truth   Do not fail if truth binary is missing/unrunnable"
      echo "                     (claim-gate-only installs on older GLIBC)"
      exit 0
      ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$PROFILE" ]]; then
  echo "required: --profile NAME" >&2
  exit 2
fi

HOME_P="$(profile_home "$PROFILE")"
PY="$(resolve_python)"
FAIL=0
ISSUES=()

note() { echo "  - $*"; }
fail() { ISSUES+=("$1"); FAIL=1; note "FAIL: $1"; }
ok() { note "ok: $1"; }

echo "== doctor profile=$PROFILE home=$HOME_P =="

# 0 prereq
if command -v hermes >/dev/null 2>&1; then ok "hermes on PATH"; else fail "hermes_missing"; fi
if "$PY" -c 'import yaml' 2>/dev/null; then ok "PyYAML ($PY)"; else fail "pyyaml_missing"; fi

# gate + tests in recipe
GATE="$RECIPE_ROOT/recipe/bin/pre_verify_claim_gate.py"
[[ -f "$GATE" ]] && ok "recipe gate" || fail "recipe_gate_missing"
if [[ -f "$RECIPE_ROOT/recipe/bin/test_claim_gate.py" ]]; then
  if "$PY" "$RECIPE_ROOT/recipe/bin/test_claim_gate.py" >/tmp/hrr-gate-test.out 2>&1; then
    ok "gate unit tests"
  else
    fail "gate_unit_tests"
    tail -5 /tmp/hrr-gate-test.out || true
  fi
fi

# truth — must exist AND run (catches GLIBC mismatches on older Linux)
TRUTH_CANDIDATE=""
for t in "$HOME_P/bin/truth" "$RECIPE_ROOT/recipe/bin/truth"; do
  if [[ -x "$t" ]]; then TRUTH_CANDIDATE="$t"; break; fi
done
if [[ -n "$TRUTH_CANDIDATE" ]]; then
  if "$TRUTH_CANDIDATE" --version >/dev/null 2>&1 || "$TRUTH_CANDIDATE" --help >/dev/null 2>&1; then
    ok "truth binary runs ($TRUTH_CANDIDATE)"
  else
    if [[ "$ALLOW_NO_TRUTH" == "1" ]]; then
      note "WARN: truth_not_runnable (allowed via --allow-no-truth)"
    else
      fail "truth_not_runnable (GLIBC too old? need 2.32+/Ubuntu 22.04+/Debian 12+)"
    fi
  fi
else
  if [[ "$ALLOW_NO_TRUTH" == "1" ]]; then
    note "WARN: truth_missing (allowed via --allow-no-truth — claim gate only)"
  else
    fail "truth_missing"
  fi
fi
TRUTH_MCP_CANDIDATE=""
for t in "$HOME_P/bin/truth-mcp" "$RECIPE_ROOT/recipe/bin/truth-mcp"; do
  if [[ -x "$t" ]]; then TRUTH_MCP_CANDIDATE="$t"; break; fi
done
if [[ -n "$TRUTH_MCP_CANDIDATE" ]]; then
  ok "truth-mcp binary present"
else
  if [[ "$ALLOW_NO_TRUTH" == "1" ]]; then
    note "WARN: truth_mcp_missing (allowed via --allow-no-truth)"
  else
    fail "truth_mcp_missing"
  fi
fi

# profile config stack
if [[ ! -f "$HOME_P/config.yaml" ]]; then
  fail "missing_config"
else
  DIAG=$(HOME_P="$HOME_P" ALLOW_NO_TRUTH="$ALLOW_NO_TRUTH" "$PY" - <<'PY'
import json, os
from pathlib import Path
import yaml
home = Path(os.environ["HOME_P"])
allow_no_truth = os.environ.get("ALLOW_NO_TRUTH") == "1"
cfg = yaml.safe_load((home / "config.yaml").read_text()) or {}
agent = cfg.get("agent") or {}
hooks = cfg.get("hooks") or {}
ms = cfg.get("mcp_servers") or {}
issues = []
if not (isinstance(hooks, dict) and hooks.get("pre_verify")):
    issues.append("pre_verify_missing")
if not agent.get("verify_on_stop"):
    issues.append("verify_on_stop_off")
if "truth" not in (ms or {}) and not allow_no_truth:
    issues.append("truth_mcp_missing")
if not agent.get("coding_instructions"):
    issues.append("coding_instructions_missing")
# Soft guidance — warn-level only via empty string tag if off (still stack-ok if missing for old installs)
tue = agent.get("tool_use_enforcement")
if tue is False or (isinstance(tue, str) and tue.strip().lower() in {"false", "off", "never", "no"}):
    issues.append("tool_use_enforcement_off")
state = home / "state" / "reliability-stack.json"
if state.exists():
    try:
        import json as _j
        if _j.loads(state.read_text()).get("enabled") is False:
            issues.append("state_disabled")
    except Exception:
        issues.append("state_unreadable")
else:
    issues.append("state_missing")
if not (home / "bin" / "pre_verify_claim_gate.py").exists():
    issues.append("profile_gate_missing")
if not (home / "working-style-instruction.md").exists():
    issues.append("working_style_missing")
else:
    ws = (home / "working-style-instruction.md").read_text(errors="replace")
    marker = "# Reliability stack (hermes-reliability-recipe)"
    if marker not in ws or "LIE/HALLUCINATION" not in ws or "truth_run_wrap" not in ws.lower():
        issues.append("working_style_soft_missing")
print(json.dumps(issues))
PY
)
  if [[ "$DIAG" == "[]" ]]; then
    ok "profile stack config"
  else
    fail "profile_stack:$DIAG"
  fi
fi

# hermes patch
LOOP="${HERMES_AGENT_ROOT:-$HOME/.hermes/hermes-agent}/agent/conversation_loop.py"
if [[ -f "$LOOP" ]]; then
  if grep -qE 'if _edited and has_hook\(["'\'']pre_verify["'\'']\)' "$LOOP"; then
    fail "pre_verify_still_edit_gated"
  elif grep -qE 'if has_hook\(["'\'']pre_verify["'\'']\)' "$LOOP"; then
    ok "always-on pre_verify"
  else
    fail "pre_verify_condition_not_found"
  fi
else
  if [[ "$REQUIRE_PATCH" == "1" ]]; then
    fail "conversation_loop_missing"
  else
    note "skip: no conversation_loop at $LOOP"
  fi
fi

# optional gateway
if [[ "$REQUIRE_GW" == "1" ]]; then
  PORT="${API_SERVER_PORT:-}"
  if [[ -z "$PORT" && -f "$HOME_P/.env" ]]; then
    PORT=$(grep -E '^API_SERVER_PORT=' "$HOME_P/.env" | head -1 | cut -d= -f2- || true)
  fi
  PORT="${PORT:-8642}"
  if curl -fsS -m 3 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    ok "gateway health :$PORT"
  else
    fail "gateway_down:$PORT"
  fi
fi

# working-style hazards — recipe template (recipe health)
WS="$RECIPE_ROOT/recipe/templates/working-style-instruction.md"
if grep -qi 'do not finish' "$WS" && grep -qi 'OUT path\|absolute OUT\|output files' "$WS"; then
  ok "recipe working-style hazard lines"
else
  fail "working_style_hazards"
fi

# working-style soft block — profile (live soft layer; catches toggle off→on drop)
if profile_has_ws_soft_block "$HOME_P"; then
  ok "profile working-style soft block (LIE + truth_run)"
else
  fail "profile_working_style_soft_missing"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "DOCTOR FAIL profile=$PROFILE issues=${ISSUES[*]}"
  write_stamp "$RECIPE_ROOT" "05-doctor" "FAIL" "${ISSUES[*]}"
  exit 1
fi
echo "DOCTOR PASS profile=$PROFILE"
write_stamp "$RECIPE_ROOT" "05-doctor" "PASS" "profile=$PROFILE"
exit 0
