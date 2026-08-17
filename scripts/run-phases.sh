#!/usr/bin/env bash
# Drive install phases 0-5 for a profile. Stops before human secrets/restart.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
PROFILE=""
APPLY_PATCH=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --apply-patch) APPLY_PATCH=1; shift ;;
    -h|--help)
      echo "usage: $0 --profile NAME [--apply-patch]"
      exit 0
      ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$PROFILE" ]]; then
  echo "required: --profile NAME" >&2
  exit 2
fi

echo "==== Phase 0 prereq ===="
command -v hermes >/dev/null
hermes --version | head -3
PY="$(resolve_python)"
"$PY" -c 'import yaml; print("yaml ok")'
test -f recipe/bin/pre_verify_claim_gate.py
write_stamp "$ROOT" "00-prereq" "PASS" "ok"
echo "PASS phase 0"

echo "==== Phase 1 truth ===="
./scripts/fetch-truth.sh
test -x recipe/bin/truth
write_stamp "$ROOT" "01-truth" "PASS" "fetched"
echo "PASS phase 1"

echo "==== Phase 2 install ===="
if [[ ! -f "$HOME/.hermes/profiles/$PROFILE/config.yaml" ]]; then
  echo "Profile $PROFILE missing config — create with: hermes profile create $PROFILE" >&2
  write_stamp "$ROOT" "02-files" "FAIL" "no_profile"
  exit 1
fi
./scripts/install.sh --profile "$PROFILE" --skip-truth
# truth already fetched into recipe/bin; ensure profile has it
cp -f recipe/bin/truth "$HOME/.hermes/profiles/$PROFILE/bin/truth" 2>/dev/null || true
cp -f recipe/bin/truth-mcp "$HOME/.hermes/profiles/$PROFILE/bin/truth-mcp" 2>/dev/null || true
chmod +x "$HOME/.hermes/profiles/$PROFILE/bin/"* 2>/dev/null || true
write_stamp "$ROOT" "02-files" "PASS" "profile=$PROFILE"
echo "PASS phase 2"

echo "==== Phase 3 patch check ===="
if ./scripts/apply-hermes-preverify-patch.sh --check; then
  :
elif [[ "$APPLY_PATCH" == "1" ]]; then
  ./scripts/apply-hermes-preverify-patch.sh --apply
  ./scripts/apply-hermes-preverify-patch.sh --check
else
  echo "pre_verify check failed; re-run with --apply-patch after human review" >&2
  exit 1
fi
echo "PASS phase 3"

echo "==== Phase 4 stack ===="
./scripts/reliability-toggle.sh on --profile "$PROFILE" --no-restart
./scripts/reliability-toggle.sh status --profile "$PROFILE" | tee /tmp/hrr-status.txt
grep -q 'pre_verify_hook: yes' /tmp/hrr-status.txt
write_stamp "$ROOT" "04-stack" "PASS" "profile=$PROFILE"
echo "PASS phase 4"

echo "==== Phase 5 doctor ===="
./scripts/doctor.sh --profile "$PROFILE"
echo "PASS phase 5"

echo
echo "All automated phases PASS for profile=$PROFILE"
echo "HUMAN next: secrets in .env, model URL, gateway restart with explicit GO"
ls -la .truth-stamps/*.PASS 2>/dev/null || true
