#!/usr/bin/env bash
# Install the opt-in operating pack into one Hermes profile.
# Usage: install-pack.sh --profile NAME --owner "Name" --workdir /abs/path
#          [--captcha handoff|tick] [--module progress-continue] [--dry-run]
# Needs the core recipe in that profile first (scripts/install.sh does both with --pack operating).
# Never restarts a gateway. Backs up SOUL.md and config.yaml before writing.
set -euo pipefail
PACK="$(cd "$(dirname "$0")" && pwd)"
PROFILE="" OWNER="" WORKDIR="" CAPTCHA="handoff" DRY=0 MODULES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --captcha) CAPTCHA="$2"; shift 2 ;;
    --module) MODULES+=("$2"); shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n 2,6p "$0"; exit 0 ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$PROFILE" && -n "$OWNER" && -n "$WORKDIR" ]] || { echo "required: --profile --owner --workdir" >&2; exit 2; }
[[ "$CAPTCHA" == handoff || "$CAPTCHA" == tick ]] || { echo "--captcha must be handoff|tick" >&2; exit 2; }
[[ "$WORKDIR" == /* ]] || { echo "--workdir must be absolute" >&2; exit 2; }
HERMES_HOME_ROOT="${HERMES_HOME_ROOT:-$HOME/.hermes}"
P="$HERMES_HOME_ROOT/profiles/$PROFILE"
[[ -f "$P/SOUL.md" ]] || { echo "missing $P/SOUL.md" >&2; exit 1; }
for m in "${MODULES[@]+"${MODULES[@]}"}"; do
  [[ -f "$PACK/modules/$m/soul.md" ]] || { echo "module $m not available in this release" >&2; exit 2; }
done
echo "== operating pack: profile=$PROFILE captcha=$CAPTCHA dry=$DRY"
[[ $DRY == 1 ]] && { echo "DRY: would write SOUL block, skills/operating/*, bin/truth-mcp-workdir"; exit 0; }

TS="$(date +%Y%m%d-%H%M%S)"
for f in SOUL.md config.yaml; do [[ -f "$P/$f" ]] && cp -a "$P/$f" "$P/$f.bak.pack-$TS"; done

# skills
for s in plan-to-issues proof-and-receipts browser-etiquette; do
  mkdir -p "$P/skills/operating/$s"
done
for m in "${MODULES[@]+"${MODULES[@]}"}"; do
  [[ -d "$PACK/modules/$m/skills" ]] && cp -R "$PACK/modules/$m/skills/." "$P/skills/operating/"
done

PACK="$PACK" P="$P" OWNER="$OWNER" WORKDIR="$WORKDIR" CAPTCHA="$CAPTCHA" MODS="${MODULES[*]+"${MODULES[*]}"}" python3 - <<'PY'
import os, re, pathlib
pack, p = pathlib.Path(os.environ["PACK"]), pathlib.Path(os.environ["P"])
owner, wd, cap = os.environ["OWNER"], os.environ["WORKDIR"], os.environ["CAPTCHA"]
def render(t):
    return t.replace("{{OWNER}}", owner).replace("{{WORKDIR}}", wd)
mods = "".join(render((pack/"modules"/m/"soul.md").read_text()).rstrip("\n")+"\n" for m in os.environ["MODS"].split() if m)
block = (pack/"soul/operating-pack.md").read_text()
block = block.replace("{{CAPTCHA_POLICY}}\n", (pack/f"captcha/{cap}.soul.md").read_text()).replace("{{MODULES}}", mods)
block = render(block)
assert "{{" not in block, "unrendered placeholder in SOUL block"
soul_p = p/"SOUL.md"; soul = soul_p.read_text()
# replace earlier pack block, and migrate a legacy botstack block
for pat in (r"\n*<!-- hrr:begin operating-pack.*?<!-- hrr:end operating-pack -->\n?",
            r"\n*<!-- botstack:begin operating-stack.*?<!-- botstack:end operating-stack -->\n?"):
    soul = re.sub(pat, "\n", soul, flags=re.S)
soul = soul.rstrip("\n") + "\n\n" + block.strip("\n") + "\n"
soul_p.write_text(soul)
for s in ("plan-to-issues", "proof-and-receipts", "browser-etiquette"):
    t = (pack/"skills"/s/"SKILL.md").read_text()
    t = t.replace("{{CAPTCHA_POLICY_SKILL}}\n", (pack/f"captcha/{cap}.skill.md").read_text())
    assert "{{" not in t, s
    (p/"skills/operating"/s/"SKILL.md").write_text(t)
w = (pack/"bin/truth-mcp-workdir").read_text().replace("__WORKDIR__", wd)
bp = p/"bin/truth-mcp-workdir"; bp.parent.mkdir(exist_ok=True); bp.write_text(w); bp.chmod(0o755)
cfg = p/"config.yaml"
if cfg.exists():
    c = cfg.read_text()
    c2 = re.sub(r"(command:\s*)(\S*/bin/truth-mcp)\s*$", r"\1\2-workdir", c, flags=re.M)
    if c2 != c: cfg.write_text(c2); print("config: truth MCP now starts in workdir")
(p/"state").mkdir(exist_ok=True)
(p/"state/operating-pack.json").write_text(
  '{"pack":"operating","version":"0.3.0","captcha":"%s","modules":"%s"}\n' % (cap, os.environ["MODS"]))
print("SOUL: operating-pack block written (end of file, after any botport/twin blocks)")
PY
for m in "${MODULES[@]+"${MODULES[@]}"}"; do
  [[ -x "$PACK/modules/$m/install.sh" ]] && "$PACK/modules/$m/install.sh" "$P"
done
echo "PASS operating pack --profile $PROFILE"
