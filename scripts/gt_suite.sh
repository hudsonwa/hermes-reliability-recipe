#!/usr/bin/env bash
# Ground-truth suite — deterministic only. No LLM-as-judge.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
PY="$(resolve_python)"
GATE="$ROOT/recipe/bin/pre_verify_claim_gate.py"
TEST_GATE="$ROOT/recipe/bin/test_claim_gate.py"
TEST_LEDGER="$ROOT/recipe/bin/test_seam_ledger.py"
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# GT2/GT5 invoke the gate directly; without this the gate's hits logger
# defaults to $HERMES_HOME/logs/claim_gate_hits.jsonl and pollutes the LIVE
# profile's organic-catch log with test rows (null session_id noise).
export CLAIM_GATE_LOG="$TMP/gt-claim-gate-hits.jsonl"

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

echo "== GT1b seam ledger unit tests =="
if [[ -f "$TEST_LEDGER" ]]; then
  if ! "$PY" "$TEST_LEDGER"; then
    echo "FAIL GT1b"; FAIL=1
  else
    echo "PASS GT1b"
  fi
else
  echo "FAIL GT1b missing $TEST_LEDGER"; FAIL=1
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

echo "== GT10 selfheal detects Hermes pre_verify patch drift =="
# Hermetic: fake Hermes root whose conversation_loop.py is edit-gated must
# produce pre_verify_patch_drift; always-on must stay clean.
if [[ -n "$PROFILE_FOR_GT" && -f "$HOME/.hermes/profiles/$PROFILE_FOR_GT/config.yaml" ]]; then
  GT10_ROOT="$TMP/gt10-hermes-root"
  mkdir -p "$GT10_ROOT/agent"
  cat >"$GT10_ROOT/agent/conversation_loop.py" <<'LOOP'
def x():
    if _edited and has_hook("pre_verify") and _attempt < max_verify_nudges():
        pass
LOOP
  GT10_OUT=$(HERMES_AGENT_ROOT="$GT10_ROOT" HRR_TEST_PROFILE="${PROFILE_FOR_GT:-}" \
    bash "$ROOT/scripts/reliability-selfheal.sh" --profile "$PROFILE_FOR_GT" --check-only 2>&1 || true)
  if echo "$GT10_OUT" | grep -q "pre_verify_patch_drift"; then
    echo "PASS GT10a drift flagged on edit-gated root"
  else
    echo "FAIL GT10a drift not flagged"; echo "$GT10_OUT"; FAIL=1
  fi
  cat >"$GT10_ROOT/agent/conversation_loop.py" <<'LOOP2'
def x():
    if has_hook("pre_verify") and _attempt < max_verify_nudges():
        pass
LOOP2
  GT10_OUT2=$(HERMES_AGENT_ROOT="$GT10_ROOT" HRR_TEST_PROFILE="${PROFILE_FOR_GT:-}" \
    bash "$ROOT/scripts/reliability-selfheal.sh" --profile "$PROFILE_FOR_GT" --check-only 2>&1 || true)
  if echo "$GT10_OUT2" | grep -q "pre_verify_patch_drift"; then
    echo "FAIL GT10b false positive on always-on root"; echo "$GT10_OUT2"; FAIL=1
  else
    echo "PASS GT10b no false positive on always-on root"
  fi
else
  echo "SKIP GT10 (set HRR_TEST_PROFILE to a real profile for live check)"
fi

echo "== GT11 doctor WS three-state + hermes venv fallback =="
# Locks issue #1/#2: a PATH-only hermes miss must not fail doctor, and the
# working-style check must name WHICH piece is missing (file / marker / content).
GT11_FAIL=0
GT11_WS="$TMP/gt11-ws.md"

# 1) no file -> missing
rm -f "$GT11_WS"
if [[ "$(ws_soft_block_state "$GT11_WS")" != "missing" ]]; then
  echo "FAIL GT11 state=missing (no file)"; GT11_FAIL=1
fi
# 2) plain style file -> marker_missing
printf '# My style\nplain text\n' >"$GT11_WS"
if [[ "$(ws_soft_block_state "$GT11_WS")" != "marker_missing" ]]; then
  echo "FAIL GT11 state=marker_missing (plain file)"; GT11_FAIL=1
fi
# 3) clone-from-randolph: LIE/truth_run lines present but NO marker -> still
#    marker_missing, so the marker miss is not hidden by existing content.
printf '# My style\n>>> LIE/HALLUCINATION CAUGHT... <<<\nUse truth_run_wrap for pytest.\n' >>"$GT11_WS"
if [[ "$(ws_soft_block_state "$GT11_WS")" != "marker_missing" ]]; then
  echo "FAIL GT11 state=marker_missing (LIE present, no marker)"; GT11_FAIL=1
fi
# 4) marker present, content missing -> lie_truth_run_missing
printf '# Reliability stack (hermes-reliability-recipe)\n---\n' >"$GT11_WS"
if [[ "$(ws_soft_block_state "$GT11_WS")" != "lie_truth_run_missing" ]]; then
  echo "FAIL GT11 state=lie_truth_run_missing (marker only)"; GT11_FAIL=1
fi
# 5) real soft block (marker + --- + template) -> ok
{
  echo "# Reliability stack (hermes-reliability-recipe)"
  echo "---"
  cat "$ROOT/recipe/templates/working-style-instruction.md"
} >"$GT11_WS"
if [[ "$(ws_soft_block_state "$GT11_WS")" != "ok" ]]; then
  echo "FAIL GT11 state=ok (full soft block)"
  echo "  got: $(ws_soft_block_state "$GT11_WS")"; GT11_FAIL=1
fi

# hermes venv fallback: PATH-only miss must resolve via HERMES_AGENT_ROOT.
GT11_AGENT="$TMP/gt11-agent"
mkdir -p "$GT11_AGENT/venv/bin"
printf '#!/bin/sh\necho fake-hermes\n' >"$GT11_AGENT/venv/bin/hermes"
chmod +x "$GT11_AGENT/venv/bin/hermes"
GT11_HERMES=$(PATH=/usr/bin:/bin HERMES_AGENT_ROOT="$GT11_AGENT" find_hermes_bin gt11 2>/dev/null || true)
if [[ "$GT11_HERMES" != "$GT11_AGENT/venv/bin/hermes" ]]; then
  echo "FAIL GT11 hermes fallback (got: ${GT11_HERMES:-none})"; GT11_FAIL=1
fi
# Absent-hermes case: must return EMPTY (and not trip callers using set -e).
# HOME is pointed at an empty fake home so ~/.local/bin/hermes cannot match.
mkdir -p "$TMP/gt11-empty" "$TMP/gt11-empty-home"
GT11_NONE=$(PATH=/usr/bin:/bin HOME="$TMP/gt11-empty-home" HERMES_AGENT_ROOT="$TMP/gt11-empty" find_hermes_bin gt11 2>/dev/null || true)
if [[ -n "$GT11_NONE" ]]; then
  echo "FAIL GT11 hermes should be absent (got: $GT11_NONE)"; GT11_FAIL=1
fi

# doctor output must NAME the failing state (acceptance), not conflate.
GT11_PF="$TMP/gt11-profiles/gt11w"
mkdir -p "$GT11_PF"
echo "agent: {}" >"$GT11_PF/config.yaml"
printf '# My style\n>>> LIE/HALLUCINATION CAUGHT... <<<\nUse truth_run_wrap for pytest.\n' >"$GT11_PF/working-style-instruction.md"
GT11_OUT=$(HERMES_PROFILES_ROOT="$TMP/gt11-profiles" \
  bash "$ROOT/scripts/doctor.sh" --profile gt11w --skip-patch 2>&1 || true)
if ! echo "$GT11_OUT" | grep -q "working_style_marker_missing"; then
  echo "FAIL GT11b doctor does not name working_style_marker_missing"
  echo "$GT11_OUT" | grep -i "working" | head -3; GT11_FAIL=1
fi
if echo "$GT11_OUT" | grep -q "working_style_lie_truth_run_missing"; then
  echo "FAIL GT11b doctor wrongly reports lie/truth_run missing (content exists)"
  GT11_FAIL=1
fi

if [[ "$GT11_FAIL" -eq 0 ]]; then
  echo "PASS GT11"
else
  FAIL=1
fi

echo "== GT12 doctor fails when profile gate hash lags recipe (#3) =="
# Isolated fake profile: older/different gate in profile bin vs recipe/bin.
# Doctor must fail-closed profile_gate_stale. Matching hashes must not use that code.
# Optional skip: HRR_DOCTOR_ALLOW_STALE_BINS=1 (intentionally diverged profiles).
GT12_FAIL=0
GT12_ROOT="$TMP/gt12-profiles"
GT12_NAME="gt12g"
mkdir -p "$GT12_ROOT/$GT12_NAME/bin"
echo "agent: {}" >"$GT12_ROOT/$GT12_NAME/config.yaml"
printf '# deliberately stale profile gate copy\nprint("old-gate")\n' >"$GT12_ROOT/$GT12_NAME/bin/pre_verify_claim_gate.py"
GT12_OUT=$(HERMES_PROFILES_ROOT="$GT12_ROOT" \
  bash "$ROOT/scripts/doctor.sh" --profile "$GT12_NAME" --skip-patch --allow-no-truth 2>&1 || true)
if ! echo "$GT12_OUT" | grep -q "profile_gate_stale"; then
  echo "FAIL GT12a stale gate not flagged profile_gate_stale"
  echo "$GT12_OUT" | tail -20
  GT12_FAIL=1
fi
cp -f "$ROOT/recipe/bin/pre_verify_claim_gate.py" "$GT12_ROOT/$GT12_NAME/bin/pre_verify_claim_gate.py"
GT12_OUT2=$(HERMES_PROFILES_ROOT="$GT12_ROOT" \
  bash "$ROOT/scripts/doctor.sh" --profile "$GT12_NAME" --skip-patch --allow-no-truth 2>&1 || true)
if echo "$GT12_OUT2" | grep -q "profile_gate_stale"; then
  echo "FAIL GT12b false profile_gate_stale when hashes match"
  echo "$GT12_OUT2" | tail -20
  GT12_FAIL=1
fi
printf '# stale again for skip-env\nprint("old-gate")\n' >"$GT12_ROOT/$GT12_NAME/bin/pre_verify_claim_gate.py"
GT12_OUT3=$(HRR_DOCTOR_ALLOW_STALE_BINS=1 HERMES_PROFILES_ROOT="$GT12_ROOT" \
  bash "$ROOT/scripts/doctor.sh" --profile "$GT12_NAME" --skip-patch --allow-no-truth 2>&1 || true)
if echo "$GT12_OUT3" | grep -q "profile_gate_stale"; then
  echo "FAIL GT12c HRR_DOCTOR_ALLOW_STALE_BINS=1 still flagged profile_gate_stale"
  echo "$GT12_OUT3" | tail -20
  GT12_FAIL=1
fi
if [[ "$GT12_FAIL" -eq 0 ]]; then
  echo "PASS GT12"
else
  FAIL=1
fi

echo "== GT13 doctor fails when profile test_claim_gate.py lags or is absent (#4) =="
# Sibling of #3: distinct fail code profile_gate_tests_stale.
# Same skip env HRR_DOCTOR_ALLOW_STALE_BINS=1 (do not add a second dialect).
GT13_FAIL=0
GT13_ROOT="$TMP/gt13-profiles"
GT13_NAME="gt13t"
mkdir -p "$GT13_ROOT/$GT13_NAME/bin"
echo "agent: {}" >"$GT13_ROOT/$GT13_NAME/config.yaml"
cp -f "$ROOT/recipe/bin/pre_verify_claim_gate.py" "$GT13_ROOT/$GT13_NAME/bin/pre_verify_claim_gate.py"
# a) absent unit file
rm -f "$GT13_ROOT/$GT13_NAME/bin/test_claim_gate.py"
GT13_OUT=$(HERMES_PROFILES_ROOT="$GT13_ROOT" \
  bash "$ROOT/scripts/doctor.sh" --profile "$GT13_NAME" --skip-patch --allow-no-truth 2>&1 || true)
if ! echo "$GT13_OUT" | grep -q "profile_gate_tests_stale"; then
  echo "FAIL GT13a absent test_claim_gate.py not flagged"
  echo "$GT13_OUT"
  GT13_FAIL=1
fi
# b) mismatch
printf '# stale unit file\nprint("old-tests")\n' >"$GT13_ROOT/$GT13_NAME/bin/test_claim_gate.py"
GT13_OUT2=$(HERMES_PROFILES_ROOT="$GT13_ROOT" \
  bash "$ROOT/scripts/doctor.sh" --profile "$GT13_NAME" --skip-patch --allow-no-truth 2>&1 || true)
if ! echo "$GT13_OUT2" | grep -q "profile_gate_tests_stale"; then
  echo "FAIL GT13b stale test_claim_gate.py not flagged"
  echo "$GT13_OUT2"
  GT13_FAIL=1
fi
# c) matching hash
cp -f "$ROOT/recipe/bin/test_claim_gate.py" "$GT13_ROOT/$GT13_NAME/bin/test_claim_gate.py"
GT13_OUT3=$(HERMES_PROFILES_ROOT="$GT13_ROOT" \
  bash "$ROOT/scripts/doctor.sh" --profile "$GT13_NAME" --skip-patch --allow-no-truth 2>&1 || true)
if echo "$GT13_OUT3" | grep -q "profile_gate_tests_stale"; then
  echo "FAIL GT13c false profile_gate_tests_stale when hashes match"
  echo "$GT13_OUT3"
  GT13_FAIL=1
fi
# d) skip env on absent file
rm -f "$GT13_ROOT/$GT13_NAME/bin/test_claim_gate.py"
GT13_OUT4=$(HRR_DOCTOR_ALLOW_STALE_BINS=1 HERMES_PROFILES_ROOT="$GT13_ROOT" \
  bash "$ROOT/scripts/doctor.sh" --profile "$GT13_NAME" --skip-patch --allow-no-truth 2>&1 || true)
if echo "$GT13_OUT4" | grep -q "profile_gate_tests_stale"; then
  echo "FAIL GT13d skip env still flagged profile_gate_tests_stale"
  echo "$GT13_OUT4"
  GT13_FAIL=1
fi
if [[ "$GT13_FAIL" -eq 0 ]]; then
  echo "PASS GT13"
else
  FAIL=1
fi

echo "== GT14 truth_run_wrap fail-closed when truth missing (#5) =="
# Missing truth must exit non-zero and MUST NOT run the wrapped command.
# No passthrough env. Actionable stderr names fetch-truth.sh or TRUTH_BIN=.
GT14_FAIL=0
GT14_SENTINEL="$TMP/gt14-wrapped-ran"
rm -f "$GT14_SENTINEL"
GT14_RC=0
PATH=/usr/bin:/bin TRUTH_BIN=/no/such/truth-bin \
  bash "$ROOT/recipe/bin/truth_run_wrap.sh" -- \
  sh -c "echo RAN > \"$GT14_SENTINEL\"" \
  >"$TMP/gt14.out" 2>"$TMP/gt14.err" || GT14_RC=$?
if [[ -f "$GT14_SENTINEL" ]]; then
  echo "FAIL GT14 wrapped command ran despite missing truth"
  GT14_FAIL=1
fi
if [[ "$GT14_RC" -eq 0 ]]; then
  echo "FAIL GT14 exit 0 on missing truth (want non-zero, 127 is fine)"
  GT14_FAIL=1
fi
if ! grep -qE 'fetch-truth\.sh|TRUTH_BIN' "$TMP/gt14.err"; then
  echo "FAIL GT14 stderr missing fetch-truth.sh or TRUTH_BIN= hint"
  cat "$TMP/gt14.err"
  GT14_FAIL=1
fi
if [[ "$GT14_FAIL" -eq 0 ]]; then
  echo "PASS GT14 (rc=$GT14_RC)"
else
  FAIL=1
fi

echo "== GT15 venv python for pytest; recipe suite is not pytest (#6) =="
GT15_FAIL=0
# skills / template / toggle: wrap a python that can import pytest; name the gate suite
for f in \
  "$ROOT/recipe/skills/reliability/SKILL.md" \
  "$ROOT/recipe/skills/reliability/truth-pytest-receipts/SKILL.md"
do
  if ! grep -q 'HERMES_VENV\|import pytest' "$f"; then
    echo "FAIL GT15 $f missing HERMES_VENV or import pytest"
    GT15_FAIL=1
  fi
  if ! grep -q 'recipe/bin/test_claim_gate.py' "$f"; then
    echo "FAIL GT15 $f missing canonical gate suite path"
    GT15_FAIL=1
  fi
  if grep -q 'truth_run_wrap.sh -- python3 -m pytest' "$f" \
     || grep -q 'truth run -- python3 -m pytest' "$f"; then
    echo "FAIL GT15 $f still wraps system python3 -m pytest"
    GT15_FAIL=1
  fi
done
if ! grep -q 'test_claim_gate.py' "$ROOT/recipe/templates/working-style-instruction.md"; then
  echo "FAIL GT15 working-style missing gate suite path"
  GT15_FAIL=1
fi
if grep -q 'python3 -m pytest' "$ROOT/scripts/reliability-toggle.sh"; then
  echo "FAIL GT15 toggle still embeds python3 -m pytest in coding_instructions"
  GT15_FAIL=1
fi
if ! grep -q 'HERMES_VENV' "$ROOT/scripts/reliability-toggle.sh"; then
  echo "FAIL GT15 toggle coding_instructions missing HERMES_VENV"
  GT15_FAIL=1
fi

# doctor: python3 -m pytest in coding_instructions + python3 cannot import pytest → FAIL
GT15_ROOT="$TMP/gt15-profiles"
GT15_NAME="gt15p"
GT15_BIN="$TMP/gt15-bin"
mkdir -p "$GT15_ROOT/$GT15_NAME/bin" "$GT15_BIN"
cp -f "$ROOT/recipe/bin/pre_verify_claim_gate.py" "$GT15_ROOT/$GT15_NAME/bin/"
cp -f "$ROOT/recipe/bin/test_claim_gate.py" "$GT15_ROOT/$GT15_NAME/bin/"
printf '%s\n' '#!/bin/sh
if [ "$1" = "-c" ] && echo "$2" | grep -q pytest; then exit 1; fi
exit 0
' >"$GT15_BIN/python3"
chmod +x "$GT15_BIN/python3"
cat >"$GT15_ROOT/$GT15_NAME/config.yaml" <<'YAML'
agent:
  coding_instructions: |
    For tests in a project: wrap -- python3 -m pytest -q
YAML
GT15_OUT=$(PATH="$GT15_BIN:/usr/bin:/bin" HERMES_PROFILES_ROOT="$GT15_ROOT" \
  bash "$ROOT/scripts/doctor.sh" --profile "$GT15_NAME" --skip-patch --allow-no-truth 2>&1 || true)
if ! echo "$GT15_OUT" | grep -q "pytest_python_cannot_import"; then
  echo "FAIL GT15a doctor did not fail pytest_python_cannot_import"
  echo "$GT15_OUT"
  GT15_FAIL=1
fi
# no pytest instruction → WARN only, not that fail code
cat >"$GT15_ROOT/$GT15_NAME/config.yaml" <<'YAML'
agent:
  coding_instructions: |
    Proof-before-claim. Quote tool output.
YAML
GT15_OUT2=$(PATH="$GT15_BIN:/usr/bin:/bin" HERMES_PROFILES_ROOT="$GT15_ROOT" \
  bash "$ROOT/scripts/doctor.sh" --profile "$GT15_NAME" --skip-patch --allow-no-truth 2>&1 || true)
if echo "$GT15_OUT2" | grep -q "pytest_python_cannot_import"; then
  echo "FAIL GT15b no-pytest instruction still failed pytest_python_cannot_import"
  echo "$GT15_OUT2"
  GT15_FAIL=1
fi
if ! echo "$GT15_OUT2" | grep -qi "WARN.*pytest"; then
  echo "FAIL GT15b expected WARN when coding_instructions have no pytest"
  echo "$GT15_OUT2"
  GT15_FAIL=1
fi
# venv/import-ok instructions → skip even if python3 cannot import pytest
cat >"$GT15_ROOT/$GT15_NAME/config.yaml" <<'YAML'
agent:
  coding_instructions: |
    For pytest: wrap -- "$HERMES_VENV/python" -m pytest -q
    (a python where import pytest succeeds).
YAML
GT15_OUT3=$(PATH="$GT15_BIN:/usr/bin:/bin" HERMES_PROFILES_ROOT="$GT15_ROOT" \
  bash "$ROOT/scripts/doctor.sh" --profile "$GT15_NAME" --skip-patch --allow-no-truth 2>&1 || true)
if echo "$GT15_OUT3" | grep -q "pytest_python_cannot_import"; then
  echo "FAIL GT15c venv/import-ok instructions still failed pytest_python_cannot_import"
  echo "$GT15_OUT3"
  GT15_FAIL=1
fi
if [[ "$GT15_FAIL" -eq 0 ]]; then
  echo "PASS GT15"
else
  FAIL=1
fi

echo "== GT16 unittest discovery must not 0-test OK (#7) =="
# Keep the __main__ runner. python -m unittest must not print Ran 0 tests / OK.
GT16_FAIL=0
GT16_RC=0
GT16_OUT=$("$PY" -m unittest recipe.bin.test_claim_gate 2>&1) || GT16_RC=$?
if echo "$GT16_OUT" | grep -qE 'Ran 0 tests' && echo "$GT16_OUT" | grep -qE '(^|\s)OK(\s|$)'; then
  echo "FAIL GT16a vacuous 0-test OK from python -m unittest recipe.bin.test_claim_gate"
  echo "$GT16_OUT"
  GT16_FAIL=1
fi
if [[ "$GT16_RC" -eq 0 ]]; then
  echo "FAIL GT16a unittest discovery exited 0"
  echo "$GT16_OUT"
  GT16_FAIL=1
fi
if ! echo "$GT16_OUT" | grep -q 'recipe/bin/test_claim_gate.py'; then
  echo "FAIL GT16a stderr/stdout missing canonical runner path"
  echo "$GT16_OUT"
  GT16_FAIL=1
fi
GT16_RC2=0
GT16_OUT2=$(cd "$ROOT/recipe/bin" && "$PY" -m unittest test_claim_gate 2>&1) || GT16_RC2=$?
if echo "$GT16_OUT2" | grep -qE 'Ran 0 tests' && echo "$GT16_OUT2" | grep -qE '(^|\s)OK(\s|$)'; then
  echo "FAIL GT16b vacuous 0-test OK from recipe/bin unittest test_claim_gate"
  echo "$GT16_OUT2"
  GT16_FAIL=1
fi
if [[ "$GT16_RC2" -eq 0 ]]; then
  echo "FAIL GT16b recipe/bin unittest discovery exited 0"
  echo "$GT16_OUT2"
  GT16_FAIL=1
fi
if ! "$PY" "$ROOT/recipe/bin/test_claim_gate.py" >/tmp/hrr-gt16-main.out 2>&1; then
  echo "FAIL GT16c __main__ runner broken"
  cat /tmp/hrr-gt16-main.out
  GT16_FAIL=1
fi
if [[ "$GT16_FAIL" -eq 0 ]]; then
  echo "PASS GT16"
else
  FAIL=1
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "GT SUITE FAILED"
  exit 1
fi
echo "GT SUITE PASSED"
exit 0
