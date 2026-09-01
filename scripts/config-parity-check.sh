#!/usr/bin/env bash
# Config-parity check: compare reliability settings across local profiles.
# Flags drift in the settings whose silent changes broke this stack before
# (verify_on_stop clobber, enforcement flips, hook removal). Silent = parity.
# Usage: bash config-parity-check.sh   (auto-discovers managed profiles; or PARITY_PROFILES="a b")
set -u
# Auto-discover managed profiles: ones actually running this stack (their
# own self-heal log / heartbeat present). Copies of the gate binary alone
# don't count — unmanaged profiles may legitimately differ.
PROFILES="${PARITY_PROFILES:-}"
if [ -z "$PROFILES" ]; then
  PROFILES=$(for f in "$HOME"/.hermes/profiles/*/logs/reliability_selfheal.jsonl \
                  "$HOME"/.hermes/profiles/*/state/reliability-heartbeat.txt; do
    [ -f "$f" ] && basename "$(dirname "$(dirname "$f")")"
  done | sort -u)
fi
HERMES_ROOT="${HERMES_AGENT_ROOT:-$HOME/.hermes/hermes-agent}"
PY="$HERMES_ROOT/venv/bin/python"
[ -x "$PY" ] || PY=python3

"$PY" - "$PROFILES" <<'EOF'
import sys, os, json
try:
    import yaml
except ImportError:
    print("PARITY FAIL: pyyaml unavailable"); sys.exit(1)

profiles = sys.argv[1].split()
fail = 0
snap = {}
for p in profiles:
    cfg_path = os.path.expanduser(f"~/.hermes/profiles/{p}/config.yaml")
    try:
        c = yaml.safe_load(open(cfg_path)) or {}
    except Exception as e:
        print(f"PARITY FAIL: {p} config unreadable: {e}"); fail = 1; continue
    a = c.get("agent", {}) or {}
    enforce = a.get("tool_use_enforcement")
    gate = (c.get("hooks") or {}).get("pre_verify") or []
    gate_ok = bool(gate) and all(os.path.exists(g.get("command", "").split()[-1] if g.get("command") else "") or True for g in gate)
    gate_bin = gate[0].get("command", "").split()[-1] if gate else None
    snap[p] = {
        "verify_on_stop": a.get("verify_on_stop"),
        "enforcement": enforce if enforce in (True, False, "auto") else f"UNUSUAL:{enforce}",
        "pre_verify_hook": bool(gate),
        "gate_bin_exists": bool(gate_bin) and os.path.exists(gate_bin) if gate_bin else False,
        "model_default": (c.get("model") or {}).get("default"),
    }

# parity rules (the settings that must hold everywhere)
for p, s in snap.items():
    if s["verify_on_stop"] is not True:
        print(f"PARITY FAIL: {p} verify_on_stop={s['verify_on_stop']} (must be True)"); fail = 1
    if s["pre_verify_hook"] is not True:
        print(f"PARITY FAIL: {p} hooks.pre_verify missing"); fail = 1
    if not s["gate_bin_exists"]:
        print(f"PARITY FAIL: {p} gate binary missing on disk"); fail = 1
    if s["enforcement"] not in (True, "auto"):
        print(f"PARITY FAIL: {p} tool_use_enforcement={s['enforcement']} (True or auto expected)"); fail = 1

if len(snap) > 1 and not fail:
    vos = {s["verify_on_stop"] for s in snap.values()}
    gate = {s["pre_verify_hook"] for s in snap.values()}
    if len(vos) > 1 or len(gate) > 1:
        print("PARITY WARN: profiles disagree on core toggles:", json.dumps(snap))
        fail = 1

if not fail:
    import datetime
    print("PARITY OK " + datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S") + " " + json.dumps(snap))
sys.exit(fail)
EOF
