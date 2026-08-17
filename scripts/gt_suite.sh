#!/usr/bin/env bash
# Ground-truth suite — deterministic only. No LLM-as-judge.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
PY="$(resolve_python)"
GATE="$ROOT/recipe/bin/pre_verify_claim_gate.py"
TEST_GATE="$ROOT/recipe/bin/test_claim_gate.py"
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "== GT1 claim gate unit tests =="
if [[ -f "$TEST_GATE" ]]; then
  if ! "$PY" "$TEST_GATE"; then
    echo "FAIL GT1"; FAIL=1
  else
    echo "PASS GT1"
  fi
else
  echo "FAIL GT1 missing $TEST_GATE"; FAIL=1
fi

echo "== GT2 loud banner on ungrounded ship =="
OUT=$("$PY" "$GATE" <<'JSON'
{"final_response":"All tests are green. Ship it.","attempt":0,"cwd":"/tmp/gt-suite-x"}
JSON
)
echo "$OUT" | grep -q 'LIE/HALLUCINATION CAUGHT' && echo "PASS GT2" || { echo "FAIL GT2: $OUT"; FAIL=1; }
echo "$OUT" | grep -q '"action": "continue"' && echo "PASS GT2b action=continue" || { echo "FAIL GT2b"; FAIL=1; }

echo "== GT3 recipe artifacts present =="
for f in \
  "$ROOT/recipe/templates/working-style-instruction.md" \
  "$ROOT/recipe/bin/pre_verify_claim_gate.py" \
  "$ROOT/scripts/reliability-selfheal.sh" \
  "$ROOT/scripts/reliability-toggle.sh" \
  "$ROOT/scripts/doctor.sh" \
  "$ROOT/scripts/fetch-truth.sh" \
  "$ROOT/docs/RELIABILITY.md" \
  "$ROOT/AGENTS.md" \
  "$ROOT/INSTALL_PHASES.md"
do
  if [[ -f "$f" ]]; then echo "  ok $f"; else echo "FAIL missing $f"; FAIL=1; fi
done
echo "PASS GT3"

echo "== GT4 working-style hazard lines =="
WS="$ROOT/recipe/templates/working-style-instruction.md"
grep -qi "do the work yourself\|Keep the main thread lean" "$WS" \
  && grep -qi "do not finish" "$WS" \
  && grep -qi "OUT path\|output files\|absolute OUT" "$WS" \
  && echo "PASS GT4" || { echo "FAIL GT4 workers hazard lines"; FAIL=1; }

echo "== GT5 gate honest-fail allows =="
OUT5=$("$PY" "$GATE" <<'JSON'
{"final_response":"FAILED. 1 failed in pytest. Do not ship.","attempt":0,"cwd":"/tmp/x"}
JSON
)
if [[ "$OUT5" == "{}" ]] || [[ -z "$OUT5" ]]; then
  echo "PASS GT5 empty-allow"
elif echo "$OUT5" | grep -q '"action"' && echo "$OUT5" | grep -qv 'continue'; then
  echo "PASS GT5"
else
  echo "FAIL GT5 $OUT5"; FAIL=1
fi

echo "== GT6 scrub check =="
if bash "$ROOT/scripts/check-scrub.sh"; then
  echo "PASS GT6"
else
  echo "FAIL GT6"; FAIL=1
fi

echo "== GT7 always-on pre_verify (optional if Hermes present) =="
LOOP="${HERMES_AGENT_ROOT:-$HOME/.hermes/hermes-agent}/agent/conversation_loop.py"
if [[ -f "$LOOP" ]]; then
  if grep -qE 'if _edited and has_hook\(["'\'']pre_verify["'\'']\)' "$LOOP"; then
    echo "FAIL GT7: pre_verify still edit-gated in $LOOP"; FAIL=1
  elif grep -qE 'if has_hook\(["'\'']pre_verify["'\'']\)' "$LOOP"; then
    echo "PASS GT7 always-on pre_verify"
  else
    echo "FAIL GT7: could not find pre_verify condition"; FAIL=1
  fi
else
  echo "SKIP GT7 (no conversation_loop at $LOOP)"
fi

echo "== GT8 selfheal ignores ambient HERMES_HOME (if profile exists) =="
PROFILE_FOR_GT="${HRR_TEST_PROFILE:-}"
if [[ -n "$PROFILE_FOR_GT" && -d "$HOME/.hermes/profiles/$PROFILE_FOR_GT" ]]; then
  OTHER="${HRR_TEST_OTHER_PROFILE:-default}"
  OUT8=$(HERMES_HOME="$HOME/.hermes/profiles/$OTHER" \
    bash "$ROOT/scripts/reliability-selfheal.sh" --profile "$PROFILE_FOR_GT" --check-only 2>&1 || true)
  if echo "$OUT8" | grep -q "home: .*/profiles/$PROFILE_FOR_GT" \
     || echo "$OUT8" | grep -q "OK $PROFILE_FOR_GT" \
     || ! echo "$OUT8" | grep -q "RELIABILITY CHECK FAIL"; then
    # If fail path, must show correct home
    if echo "$OUT8" | grep -q 'RELIABILITY CHECK FAIL'; then
      echo "$OUT8" | grep -q "/profiles/$PROFILE_FOR_GT" && echo "PASS GT8" || { echo "FAIL GT8"; echo "$OUT8"; FAIL=1; }
    else
      echo "PASS GT8"
    fi
  else
    echo "FAIL GT8"; echo "$OUT8"; FAIL=1
  fi
else
  echo "SKIP GT8 (set HRR_TEST_PROFILE to a real profile for live check)"
fi

echo "== GT9 toggle off→on restores working-style soft block =="
# Isolated fake profile under tmp HERMES_PROFILES_ROOT — never touches real profiles.
GT9_ROOT="$TMP/gt9-profiles"
GT9_NAME="gt9-ws"
mkdir -p "$GT9_ROOT/$GT9_NAME"/{bin,state,logs,scripts}
cat >"$GT9_ROOT/$GT9_NAME/config.yaml" <<'YAML'
agent:
  max_turns: 8
model:
  default: dummy
YAML
# Long existing style WITHOUT the reliability soft block
cat >"$GT9_ROOT/$GT9_NAME/working-style-instruction.md" <<'WS'
# My long personal style
Do useful work. Be brief.
WS
# Minimal truth bins so toggle ensure_bins can copy or skip
if [[ -x "$ROOT/recipe/bin/truth" ]]; then
  cp -f "$ROOT/recipe/bin/truth" "$GT9_ROOT/$GT9_NAME/bin/truth" 2>/dev/null || true
  cp -f "$ROOT/recipe/bin/truth-mcp" "$GT9_ROOT/$GT9_NAME/bin/truth-mcp" 2>/dev/null || true
fi
cp -f "$ROOT/recipe/bin/pre_verify_claim_gate.py" "$GT9_ROOT/$GT9_NAME/bin/" 2>/dev/null || true
cp -f "$ROOT/recipe/bin/truth_run_wrap.sh" "$GT9_ROOT/$GT9_NAME/bin/" 2>/dev/null || true
chmod +x "$GT9_ROOT/$GT9_NAME/bin/"* 2>/dev/null || true

GT9_FAIL=0
export HERMES_PROFILES_ROOT="$GT9_ROOT"
# ON should append soft block
if ! bash "$ROOT/scripts/reliability-toggle.sh" on --profile "$GT9_NAME" --no-restart >/tmp/hrr-gt9-on1.out 2>&1; then
  echo "FAIL GT9 toggle on #1"; cat /tmp/hrr-gt9-on1.out; GT9_FAIL=1
fi
source "$ROOT/scripts/lib.sh"
if ! profile_has_ws_soft_block "$GT9_ROOT/$GT9_NAME"; then
  echo "FAIL GT9 soft block missing after first on"; GT9_FAIL=1
  tail -20 "$GT9_ROOT/$GT9_NAME/working-style-instruction.md" || true
fi
# OFF strips soft block
if ! bash "$ROOT/scripts/reliability-toggle.sh" off --profile "$GT9_NAME" --no-restart >/tmp/hrr-gt9-off.out 2>&1; then
  echo "FAIL GT9 toggle off"; cat /tmp/hrr-gt9-off.out; GT9_FAIL=1
fi
if profile_has_ws_soft_block "$GT9_ROOT/$GT9_NAME"; then
  echo "FAIL GT9 soft block still present after off"; GT9_FAIL=1
fi
# Personal prose must survive
if ! grep -q 'My long personal style' "$GT9_ROOT/$GT9_NAME/working-style-instruction.md"; then
  echo "FAIL GT9 personal style wiped on off"; GT9_FAIL=1
fi
# ON again must restore soft block (the regression this GT locks)
if ! bash "$ROOT/scripts/reliability-toggle.sh" on --profile "$GT9_NAME" --no-restart >/tmp/hrr-gt9-on2.out 2>&1; then
  echo "FAIL GT9 toggle on #2"; cat /tmp/hrr-gt9-on2.out; GT9_FAIL=1
fi
if ! profile_has_ws_soft_block "$GT9_ROOT/$GT9_NAME"; then
  echo "FAIL GT9 soft block missing after second on (off→on drop regression)"; GT9_FAIL=1
  cat /tmp/hrr-gt9-on2.out || true
fi
if ! grep -q 'My long personal style' "$GT9_ROOT/$GT9_NAME/working-style-instruction.md"; then
  echo "FAIL GT9 personal style wiped on second on"; GT9_FAIL=1
fi
unset HERMES_PROFILES_ROOT
if [[ "$GT9_FAIL" -eq 0 ]]; then
  echo "PASS GT9 off→on restores soft working-style"
else
  FAIL=1
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "GT SUITE FAILED"
  exit 1
fi
echo "GT SUITE PASSED"
exit 0
