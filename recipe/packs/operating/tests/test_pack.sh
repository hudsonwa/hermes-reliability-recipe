#!/usr/bin/env bash
# Hermetic tests for the operating pack (fake profile in a temp HERMES_HOME_ROOT).
set -euo pipefail
PACK="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAIL=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; FAIL=1; }
mk(){ local p="$T/profiles/$1"; mkdir -p "$p/bin"
  printf 'You are a bot.\n<!-- botport:begin x -->\nbp\n<!-- botport:end x -->\n<!-- twin:begin y -->\ntw\n<!-- twin:end y -->\n' >"$p/SOUL.md"
  printf 'mcp_servers:\n  truth:\n    command: %s/bin/truth-mcp\n' "$p" >"$p/config.yaml"; }
export HERMES_HOME_ROOT="$T"
mk a; bash "$PACK/install-pack.sh" --profile a --owner "Ann Owner" --workdir /work/a >/dev/null
S="$T/profiles/a/SOUL.md"
grep -q "hrr:begin operating-pack" "$S" && ok P1-block || bad P1-block
! grep -q "{{" "$S" "$T"/profiles/a/skills/operating/*/SKILL.md && ok P2-rendered || bad P2-rendered
grep -q "hand that step to Ann Owner" "$S" && grep -q "never tick" "$T/profiles/a/skills/operating/browser-etiquette/SKILL.md" && ok P3-default-handoff || bad P3-default-handoff
[[ $(grep -n 'twin:end' "$S" | cut -d: -f1) -lt $(grep -n 'hrr:begin operating-pack' "$S" | cut -d: -f1) ]] && ok P4-order || bad P4-order
grep -q "truth-mcp-workdir" "$T/profiles/a/config.yaml" && grep -q "/work/a" "$T/profiles/a/bin/truth-mcp-workdir" && ok P5-workdir || bad P5-workdir
bash "$PACK/install-pack.sh" --profile a --owner "Ann Owner" --workdir /work/a --captcha tick >/dev/null
[[ $(grep -c "hrr:begin operating-pack" "$S") == 1 ]] && ok P6-idempotent || bad P6-idempotent
grep -q "allows you to tick" "$S" && ! grep -qi "never solve, tick" "$S" && ! grep -q "never tick" "$T/profiles/a/skills/operating/browser-etiquette/SKILL.md" && ok P7-tick-one-rule || bad P7-tick-one-rule
ls "$T/profiles/a/" | grep -q "SOUL.md.bak.pack-" && ok P8-backup || bad P8-backup
mk b; printf '\n<!-- botstack:begin operating-stack v=1.0.0 -->\nold\n<!-- botstack:end operating-stack -->\n' >>"$T/profiles/b/SOUL.md"
bash "$PACK/install-pack.sh" --profile b --owner O --workdir /w >/dev/null
! grep -q botstack "$T/profiles/b/SOUL.md" && ok P9-migrate-botstack || bad P9-migrate-botstack
bash "$PACK/install-pack.sh" --profile b --owner O --workdir /w --captcha maybe >/dev/null 2>&1 && bad P10-bad-captcha || ok P10-bad-captcha
bash "$PACK/install-pack.sh" --profile b --owner O --workdir /w --module nope >/dev/null 2>&1 && bad P11-unknown-module || ok P11-unknown-module
mk c; bash "$PACK/install-pack.sh" --profile c --owner O --workdir /w >/dev/null
[[ ! -d "$T/profiles/c/plugins/progress-continue" ]] && ! grep -q progress-continue "$T/profiles/c/config.yaml" && ok P13-module-off-by-default || bad P13-module-off-by-default
bash "$PACK/install-pack.sh" --profile c --owner O --workdir /w --module progress-continue >/dev/null
C="$T/profiles/c"; python3 -c "
import yaml,sys;d=yaml.safe_load(open('$C/config.yaml'));p=d['plugins']
assert 'progress-continue' in p['enabled'] and p['entries']['progress-continue']['allow_gateway_injection'] is True
assert d['mcp_servers']['truth']['command'].endswith('truth-mcp-workdir')" && [[ -f "$C/plugins/progress-continue/plugin.yaml" ]] && grep -q "making real progress" "$C/SOUL.md" && [[ $(grep -c "hrr:begin operating-pack" "$C/SOUL.md") == 1 ]] && ok P14-module-install || bad P14-module-install
grep -q '{{MODULES}}' "$PACK/soul/operating-pack.md" && ok P12-module-slot || bad P12-module-slot
for f in "$PACK"/modules/*/tests/*.sh; do [[ -f "$f" ]] && { bash "$f" && ok "module $f" || bad "module $f"; }; done
[[ $FAIL == 0 ]] && echo "PASS operating pack tests" || { echo "FAIL operating pack tests"; exit 1; }
