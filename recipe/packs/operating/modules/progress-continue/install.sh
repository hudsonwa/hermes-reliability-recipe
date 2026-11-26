#!/usr/bin/env bash
# progress-continue module installer (called by install-pack.sh --module progress-continue).
# Copies the plugin into the profile and enables it in config.yaml. Does NOT reload a gateway:
# it takes effect on that profile's next gateway restart (or `hermes -p NAME plugins enable progress-continue`).
set -euo pipefail
MOD="$(cd "$(dirname "$0")" && pwd)"; P="$1"
mkdir -p "$P/plugins"
rm -rf "${P:?}/plugins/progress-continue"
cp -R "$MOD/plugin" "$P/plugins/progress-continue"
CFG="$P/config.yaml" python3 - <<'PY'
import os, yaml
p = os.environ["CFG"]
d = (yaml.safe_load(open(p)) if os.path.exists(p) else None) or {}
pl = d.setdefault("plugins", {})
en = pl.setdefault("enabled", [])
if "progress-continue" not in en: en.append("progress-continue")
ent = pl.setdefault("entries", {}).setdefault("progress-continue", {})
ent["allow_gateway_injection"] = True
yaml.safe_dump(d, open(p, "w"), sort_keys=False)
PY
echo "progress-continue: plugin installed and enabled in config (takes effect after a gateway restart)"
