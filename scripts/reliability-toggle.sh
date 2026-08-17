#!/usr/bin/env bash
# Toggle reliability stack: claim gate + truth MCP + soft layer.
# Usage:
#   ./scripts/reliability-toggle.sh status --profile NAME
#   ./scripts/reliability-toggle.sh on|off --profile NAME [--no-restart|--restart]
# Env:
#   LAB_YOLO=1 CONFIRM_LAB_YOLO=I_UNDERSTAND — also set approvals.mode=off (lab only)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

PROFILE="${PROFILE:-}"
RESTART=0
ACTION="${1:-status}"
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --no-restart) RESTART=0; shift ;;
    --restart) RESTART=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$PROFILE" ]]; then
  echo "Usage: $0 {status|on|off} --profile NAME [--restart|--no-restart]" >&2
  exit 2
fi
validate_profile_name "$PROFILE" || exit 2
require_lab_yolo_confirm || exit 2

HERMES_BIN="${HERMES_BIN:-hermes}"
HOME_P="$(profile_home "$PROFILE")"
CFG="$HOME_P/config.yaml"
STATE_DIR="$HOME_P/state"
STATE_FILE="$STATE_DIR/reliability-stack.json"
BACKUP_DIR="$HOME_P/state/reliability-backups"
RECIPE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECIPE_BIN="$RECIPE_ROOT/recipe/bin"
PY="$(resolve_python)"

if [[ -z "${GATE_PY:-}" ]]; then
  if [[ -f "$RECIPE_BIN/pre_verify_claim_gate.py" ]]; then
    GATE_PY="$RECIPE_BIN/pre_verify_claim_gate.py"
  elif [[ -f "$HOME_P/bin/pre_verify_claim_gate.py" ]]; then
    GATE_PY="$HOME_P/bin/pre_verify_claim_gate.py"
  else
    echo "No claim gate script found" >&2
    exit 1
  fi
fi

if [[ ! -f "$CFG" ]]; then
  echo "No config at $CFG — create profile first: hermes profile create $PROFILE" >&2
  exit 1
fi
mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$HOME_P/bin" "$HOME_P/logs"

ts() { date "+%Y-%m-%dT%H:%M:%S%z"; }

ensure_bins() {
  if [[ -f "$RECIPE_BIN/pre_verify_claim_gate.py" ]]; then
    cp -f "$RECIPE_BIN/pre_verify_claim_gate.py" "$HOME_P/bin/pre_verify_claim_gate.py"
    chmod +x "$HOME_P/bin/pre_verify_claim_gate.py" 2>/dev/null || true
    GATE_PY="$HOME_P/bin/pre_verify_claim_gate.py"
  fi
  for name in truth truth-mcp truth_run_wrap.sh test_claim_gate.py; do
    if [[ -e "$RECIPE_BIN/$name" ]]; then
      cp -f "$RECIPE_BIN/$name" "$HOME_P/bin/$name"
      chmod +x "$HOME_P/bin/$name" 2>/dev/null || true
    fi
  done
}

snapshot_cfg() {
  cp -a "$CFG" "$BACKUP_DIR/config.yaml.${1}.$(date +%Y%m%d-%H%M%S)"
}

allowlist_gate() {
  local al="$HOME_P/shell-hooks-allowlist.json"
  local cmd="$PY $GATE_PY"
  GATE_PY="$GATE_PY" AL="$al" CMD="$cmd" "$PY" - <<'PY'
import json, os
from datetime import datetime, timezone
from pathlib import Path
al = Path(os.environ["AL"])
cmd = os.environ["CMD"]
gate = Path(os.environ["GATE_PY"])
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
mtime = (
    datetime.utcfromtimestamp(gate.stat().st_mtime).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    if gate.exists()
    else now
)
data = {"approvals": []}
if al.exists():
    try:
        data = json.loads(al.read_text()) or {"approvals": []}
    except Exception:
        data = {"approvals": []}
approvals = [
    a
    for a in (data.get("approvals") or [])
    if not (
        a.get("event") == "pre_verify"
        and "pre_verify_claim_gate" in str(a.get("command", ""))
    )
]
approvals.append(
    {
        "approved_at": now,
        "command": cmd,
        "event": "pre_verify",
        "script_mtime_at_approval": mtime,
    }
)
data["approvals"] = approvals
al.write_text(json.dumps(data, indent=2) + "\n")
print("allowlist ok")
PY
}

apply_on() {
  ensure_bins
  snapshot_cfg on
  allowlist_gate
  local wrap="$HOME_P/bin/truth_run_wrap.sh"
  local mcp="$HOME_P/bin/truth-mcp"
  CFG="$CFG" PY_BIN="$PY" GATE_PY="$GATE_PY" WRAP="$wrap" MCP="$mcp" LAB_YOLO="${LAB_YOLO:-0}" "$PY" - <<'PY'
import os
from pathlib import Path
import yaml

cfg = Path(os.environ["CFG"])
d = yaml.safe_load(cfg.read_text()) or {}
agent = d.setdefault("agent", {})
agent["verify_on_stop"] = True
agent["max_verify_nudges"] = 3
# Soft Hermes guidance: call tools instead of describing them (helps weak/local models).
agent["tool_use_enforcement"] = True
wrap = os.environ["WRAP"]
agent["coding_instructions"] = f"""Proof-before-claim rules for coding and file work:
- Do not state success until you re-read or stat written files and/or re-run relevant tests.
- Never invent line counts, byte sizes, corpus stats, or test results.
- If verification is impossible, say so explicitly and do not claim DONE or ship.
- Prefer honest PARTIAL/FAILED over a polished false success.
- Quote real tool output (paths that exist, pytest lines, exit codes). Do not use empty EVIDENCE theater.
- For tests in a project: `{wrap} -- python3 -m pytest -q` (or truth run). Before claiming tests pass, call MCP verify_turn (mcp__truth__verify_turn) when available.
- Wrong-directory greens do not count.
- Host/live machine facts need tools this turn (or say BLOCKED). No tool cosplay in prose.
- If the user forbids tools, or the claim is about another project/tree: do not start long exploratory pytest. Answer FAILED/PARTIAL.
"""
d["hooks"] = {
    "pre_verify": [
        {
            "command": f"{os.environ['PY_BIN']} {os.environ['GATE_PY']}",
            "timeout": 15,
        }
    ]
}
d["hooks_auto_accept"] = True
mcp = Path(os.environ["MCP"])
if mcp.exists():
    servers = d.get("mcp_servers") if isinstance(d.get("mcp_servers"), dict) else {}
    servers = dict(servers or {})
    servers["truth"] = {
        "command": str(mcp),
        "args": [],
        "timeout": 60,
        "connect_timeout": 30,
    }
    d["mcp_servers"] = servers
if os.environ.get("LAB_YOLO") == "1":
    ap = d.setdefault("approvals", {})
    if isinstance(ap, dict):
        ap["mode"] = "off"
        ap["cron_mode"] = "approve"
cfg.write_text(yaml.safe_dump(d, sort_keys=False, allow_unicode=True))
print("config ON written")
PY
  local soul="$HOME_P/SOUL.md"
  local marker="# Reliability (hermes-reliability-recipe)"
  if [[ -f "$soul" ]] && ! grep -qF "$marker" "$soul"; then
    cat >> "$soul" <<'SOUL'

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
  elif [[ ! -f "$soul" && -f "$RECIPE_ROOT/recipe/templates/SOUL.reliability.md" ]]; then
    cp -f "$RECIPE_ROOT/recipe/templates/SOUL.reliability.md" "$soul"
  fi
  # Soft working-style must come back on toggle ON (toggle OFF strips it).
  # This is the load-bearing fix for off→on silently dropping LIE/truth_run bullets.
  local ws_status
  if ! ws_status="$(ensure_working_style_soft_block "$HOME_P" "$RECIPE_ROOT")"; then
    echo "FAIL: working-style soft block not present after toggle on ($ws_status)" >&2
    return 1
  fi
  echo "working-style soft block: $ws_status"
  printf '%s\n' "{\"enabled\":true,\"updated\":\"$(ts)\",\"profile\":\"$PROFILE\",\"recipe\":\"hermes-reliability-recipe\"}" > "$STATE_FILE"
  echo "reliability stack ON for $PROFILE"
}

apply_off() {
  snapshot_cfg off
  CFG="$CFG" "$PY" - <<'PY'
import os
from pathlib import Path
import yaml

cfg = Path(os.environ["CFG"])
d = yaml.safe_load(cfg.read_text()) or {}
agent = d.setdefault("agent", {})
agent["verify_on_stop"] = False
agent.pop("coding_instructions", None)
# Leave tool_use_enforcement as-is on off (harmless soft guidance); do not force-remove.
hooks = d.get("hooks") or {}
if isinstance(hooks, dict):
    hooks.pop("pre_verify", None)
    d["hooks"] = hooks if hooks else {}
ms = d.get("mcp_servers") or {}
if isinstance(ms, dict) and "truth" in ms:
    ms = dict(ms)
    ms.pop("truth", None)
    if ms:
        d["mcp_servers"] = ms
    else:
        d.pop("mcp_servers", None)
cfg.write_text(yaml.safe_dump(d, sort_keys=False, allow_unicode=True))
print("config OFF written")
PY
  local soul="$HOME_P/SOUL.md"
  if [[ -f "$soul" ]] && grep -q "hermes-reliability-recipe" "$soul"; then
    SOUL="$soul" "$PY" - <<'PY'
import os
from pathlib import Path
soul = Path(os.environ["SOUL"])
text = soul.read_text()
marker = "# Reliability (hermes-reliability-recipe)"
if marker in text:
    text = text.split(marker)[0].rstrip() + "\n"
    soul.write_text(text)
print("soul stripped")
PY
  fi
  # Strip appended reliability soft section (surgical reversal). toggle ON restores it.
  local ws="$HOME_P/working-style-instruction.md"
  local ws_marker
  ws_marker="$(ws_soft_marker)"
  if [[ -f "$ws" ]] && grep -qF "$ws_marker" "$ws" 2>/dev/null; then
    WS="$ws" MARKER="$ws_marker" "$PY" - <<'PY'
import os
from pathlib import Path
ws = Path(os.environ["WS"])
marker = os.environ["MARKER"]
text = ws.read_text()
if marker in text:
    text = text.split(marker)[0].rstrip() + "\n"
    ws.write_text(text)
print("working-style reliability section stripped")
PY
  fi
  printf '%s\n' "{\"enabled\":false,\"updated\":\"$(ts)\",\"profile\":\"$PROFILE\"}" > "$STATE_FILE"
  echo "reliability stack OFF for $PROFILE"
}

show_status() {
  echo "profile: $PROFILE"
  echo "config:  $CFG"
  echo "recipe:  $RECIPE_ROOT"
  if [[ -f "$STATE_FILE" ]]; then
    echo -n "state:   "; cat "$STATE_FILE"; echo
  else
    echo "state:   (none)"
  fi
  CFG="$CFG" "$PY" - <<'PY'
import os
from pathlib import Path
import yaml
d = yaml.safe_load(Path(os.environ["CFG"]).read_text()) or {}
agent = d.get("agent") or {}
hooks = d.get("hooks") or {}
ms = d.get("mcp_servers") or {}
ap = d.get("approvals") or {}
print("verify_on_stop:", agent.get("verify_on_stop"))
print("coding_instructions:", "yes" if agent.get("coding_instructions") else "no")
print("tool_use_enforcement:", agent.get("tool_use_enforcement"))
print("pre_verify_hook:", "yes" if (hooks.get("pre_verify") if isinstance(hooks, dict) else None) else "no")
print("mcp_truth:", "yes" if isinstance(ms, dict) and "truth" in ms else "no")
print("approvals.mode:", ap.get("mode") if isinstance(ap, dict) else ap)
print("model:", (d.get("model") or {}).get("default"))
PY
  [[ -x "$HOME_P/bin/truth" ]] && echo "truth_bin: ok" || echo "truth_bin: missing"
  [[ -x "$HOME_P/bin/truth-mcp" ]] && echo "truth_mcp: ok" || echo "truth_mcp: missing"
  [[ -f "$GATE_PY" ]] && echo "gate_py: ok ($GATE_PY)" || echo "gate_py: missing"
  if profile_has_ws_soft_block "$HOME_P"; then
    echo "working_style_soft: ok"
  else
    echo "working_style_soft: MISSING (run toggle on or install)"
  fi
}

maybe_restart() {
  if [[ "$RESTART" != "1" ]]; then
    echo "(gateway restart skipped — pass --restart after human approval)"
    return 0
  fi
  echo "Restarting gateway for profile $PROFILE (HERMES_HOME=$HOME_P)..."
  export HERMES_PROFILE="$PROFILE"
  export HERMES_HOME="$HOME_P"
  $HERMES_BIN gateway stop 2>/dev/null || true
  sleep 1
  local launcher="$HOME_P/logs/start-gateway-once.sh"
  cat > "$launcher" <<EOF
#!/usr/bin/env bash
export HERMES_PROFILE=$PROFILE
export HERMES_HOME=$HOME_P
exec hermes gateway run --replace
EOF
  chmod +x "$launcher"
  "$PY" - <<PY
import subprocess, os
log = open(os.path.expanduser("$HOME_P/logs/gateway-toggle.log"), "a")
subprocess.Popen(
    ["bash", os.path.expanduser("$launcher")],
    stdout=log,
    stderr=log,
    start_new_session=True,
)
print("gateway start launched")
PY
  sleep 5
  HERMES_PROFILE="$PROFILE" HERMES_HOME="$HOME_P" hermes gateway status 2>&1 | tail -10 || true
}

case "$ACTION" in
  status) show_status ;;
  on) apply_on; maybe_restart; show_status ;;
  off) apply_off; maybe_restart; show_status ;;
  *)
    echo "Usage: $0 {status|on|off} --profile NAME [--restart|--no-restart]"
    exit 2
    ;;
esac
