#!/usr/bin/env bash
# Dead-man's switch: verify self-heal heartbeats are fresh (generic form).
# Profile wrappers stamp state/reliability-heartbeat.txt on every run; this
# check fails loudly if a heartbeat exceeds DEADMAN_STALE_HOURS (default 25).
# Silent when green (cron no_agent). Install one per host:
#   DEADMAN_PROFILES="alpha beta" bash scripts/deadman-check.sh
set -u
PROFILES="${DEADMAN_PROFILES:-}"
if [ -z "$PROFILES" ]; then
  # default: every profile that has a self-heal log must have a fresh heartbeat
  PROFILES=$(for f in "$HOME"/.hermes/profiles/*/logs/reliability_selfheal.jsonl; do
    [ -f "$f" ] && basename "$(dirname "$(dirname "$f")")"
  done)
fi
STALE_HOURS="${DEADMAN_STALE_HOURS:-25}"
fail=0
for p in $PROFILES; do
  HB="$HOME/.hermes/profiles/$p/state/reliability-heartbeat.txt"
  if [ ! -f "$HB" ]; then
    echo "DEADMAN FAIL: $p has NO heartbeat file"
    fail=1; continue
  fi
  mtime=$(stat -f %m "$HB" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  AGE_H=$(( (NOW - mtime) / 3600 ))
  if [ "$AGE_H" -ge "$STALE_HOURS" ]; then
    echo "DEADMAN FAIL: $p heartbeat ${AGE_H}h old (limit ${STALE_HOURS}h) — watchdog dead or starving"
    fail=1
  else
    [ -n "${DEADMAN_VERBOSE:-}" ] && echo "ok: $p heartbeat ${AGE_H}h old"
  fi
done
exit $fail
