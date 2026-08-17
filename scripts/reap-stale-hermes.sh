#!/usr/bin/env bash
# Reap stale Hermes *worker/chat* processes — never gateways/desktop/serve.
# Simple + ground-truthable. Default is dry-run (print only).
#
# Usage:
#   reap-stale-hermes.sh                  # dry-run report
#   reap-stale-hermes.sh --apply          # kill stale targets
#   reap-stale-hermes.sh --apply --max-age-min 90
#   reap-stale-hermes.sh --apply --registry-only
#
# Targets (must match ALL relevant rules):
#   1) Registry entries (worker_pids.jsonl) older than max age whose PID still lives
#   2) Orphan hermes chat/-q (PPID=1) older than max age
# Never:
#   gateway run | hermes serve | dashboard | open-webui | Hermes.app | truth-mcp with live parent
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

APPLY=0
MAX_AGE_MIN="${REAP_MAX_AGE_MIN:-120}"
REGISTRY_ONLY=0
PROFILE="${HERMES_PROFILE:-}"
NOW=$(date +%s)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --max-age-min) MAX_AGE_MIN="$2"; shift 2 ;;
    --registry-only) REGISTRY_ONLY=1; shift ;;
    --profile) PROFILE="$2"; shift 2 ;;
    -h|--help) sed -n '1,20p' "$0"; exit 0 ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  echo "required: --profile NAME" >&2
  exit 2
fi
validate_profile_name "$PROFILE" || exit 2
HOME_P="$(profile_home "$PROFILE")"
REG="${WORKER_REGISTRY:-$HOME_P/state/worker_pids.jsonl}"
LOG="${REAP_LOG:-$HOME_P/logs/process_reaper.jsonl}"

mkdir -p "$(dirname "$LOG")" "$(dirname "$REG")"
MAX_AGE_SEC=$((MAX_AGE_MIN * 60))
KILLED=()
SKIPPED=()
REPORT=()

log_line() {
  # $1=action $2=pid $3=age $4=optional out
  REAP_ACTION="$1" REAP_PID="$2" REAP_AGE="$3" REAP_OUT="${4:-}" REAP_TS="$NOW" \
    python3 -c 'import json,os,sys
print(json.dumps({"ts":int(os.environ["REAP_TS"]),"action":os.environ["REAP_ACTION"],"pid":int(os.environ["REAP_PID"]),"age_s":int(os.environ["REAP_AGE"]),"out":os.environ.get("REAP_OUT","")}))' >> "$LOG"
}

is_never_kill() {
  local cmd="$1"
  case "$cmd" in
    *gateway\ run*|*gateway\ restart*|*hermes_cli.main\ serve*|*dashboard*|*open-webui*|*Hermes\ Agent.app*|*Hermes.app*|*mcp_stdio_watchdog*|*truth-mcp*|*language-server*)
      return 0 ;;
  esac
  return 1
}

pid_alive() { kill -0 "$1" 2>/dev/null; }

etime_to_sec() {
  # etime formats: SS | MM:SS | HH:MM:SS | DD-HH:MM:SS
  local e="$1"
  local d=0 h=0 m=0 s=0
  if [[ "$e" == *-* ]]; then
    d=${e%%-*}; e=${e#*-}
  fi
  IFS=: read -r a b c <<<"$e"
  if [[ -n "${c:-}" ]]; then h=$a; m=$b; s=$c
  elif [[ -n "${b:-}" ]]; then m=$a; s=$b
  else s=$a
  fi
  echo $((10#$d*86400 + 10#$h*3600 + 10#$m*60 + 10#$s))
}

# --- registry-based ---
if [[ -f "$REG" ]]; then
  TMPR=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    pid=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("pid",""))' "$line" 2>/dev/null || true)
    started=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("started",0))' "$line" 2>/dev/null || echo 0)
    out=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("out",""))' "$line" 2>/dev/null || true)
    [[ -z "$pid" ]] && continue
    if ! pid_alive "$pid"; then
      # drop dead entry
      continue
    fi
    age=$((NOW - started))
    cmd=$(ps -p "$pid" -o command= 2>/dev/null || echo "")
    if is_never_kill "$cmd"; then
      echo "$line" >> "$TMPR"
      SKIPPED+=("registry_never_kill:$pid")
      continue
    fi
    if (( age >= MAX_AGE_SEC )); then
      REPORT+=("REGISTRY_STALE pid=$pid age_s=$age out=$out cmd=${cmd:0:80}")
      if [[ "$APPLY" == "1" ]]; then
        kill "$pid" 2>/dev/null || true
        sleep 0.2
        kill -9 "$pid" 2>/dev/null || true
        KILLED+=("$pid")
        log_line "kill_registry" "$pid" "$age" "$out"
      fi
      # do not keep entry
    else
      echo "$line" >> "$TMPR"
    fi
  done < "$REG"
  if [[ "$APPLY" == "1" ]]; then
    mv "$TMPR" "$REG"
  else
    rm -f "$TMPR"
  fi
fi

# --- orphan hermes chat -q (PPID 1), age based ---
if [[ "$REGISTRY_ONLY" != "1" ]]; then
  while read -r pid ppid etime cmd; do
    [[ -z "${pid:-}" ]] && continue
    if is_never_kill "$cmd"; then
      continue
    fi
    # must look like a one-shot chat worker
    if ! [[ "$cmd" == *hermes* && ( "$cmd" == *" chat"* || "$cmd" == *\ chat\ * ) ]]; then
      continue
    fi
    # prefer -q / worker-ecore / gt- markers
    if ! [[ "$cmd" == *\ -q* || "$cmd" == *worker-ecore* || "$cmd" == *gt-worker* || "$cmd" == *source\ worker* ]]; then
      # still allow PPID1 hermes chat that's been around forever
      if [[ "$ppid" != "1" ]]; then
        continue
      fi
    fi
    age=$(etime_to_sec "$etime")
    if [[ "$ppid" == "1" ]] && (( age >= MAX_AGE_SEC )); then
      REPORT+=("ORPHAN_CHAT pid=$pid ppid=$ppid age_s=$age cmd=${cmd:0:100}")
      if [[ "$APPLY" == "1" ]]; then
        kill "$pid" 2>/dev/null || true
        sleep 0.2
        kill -9 "$pid" 2>/dev/null || true
        KILLED+=("$pid")
        log_line "kill_orphan_chat" "$pid" "$age"
      fi
    fi
  done < <(ps -axo pid=,ppid=,etime=,command= | grep -i hermes | grep -v grep || true)
fi

echo "reap profile=$PROFILE max_age_min=$MAX_AGE_MIN apply=$APPLY"
if [[ ${#REPORT[@]} -eq 0 ]]; then
  echo "targets: none"
else
  echo "targets:"
  printf '  %s\n' "${REPORT[@]}"
fi
echo "killed: ${KILLED[*]:-none}"
# Quiet success for cron when nothing to say and apply cleaned or dry empty
if [[ "$APPLY" == "1" && ${#KILLED[@]} -gt 0 ]]; then
  echo "REAPED ${#KILLED[@]} process(es)"
fi
exit 0
