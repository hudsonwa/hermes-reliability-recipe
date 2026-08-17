#!/usr/bin/env bash
# Shared helpers for hermes-reliability-recipe scripts.
# shellcheck disable=SC2034

recipe_root_from() {
  local script_dir
  script_dir="$(cd "$(dirname "$1")" && pwd)"
  cd "$script_dir/.." && pwd
}

resolve_python() {
  if [[ -n "${HERMES_PYTHON:-}" && -x "${HERMES_PYTHON}" ]]; then
    echo "$HERMES_PYTHON"
    return
  fi
  if [[ -x "${HOME}/.hermes/hermes-agent/venv/bin/python" ]]; then
    echo "${HOME}/.hermes/hermes-agent/venv/bin/python"
    return
  fi
  # Prefer bare python3, then versioned (uv-managed installs often only expose 3.11)
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return
  fi
  if command -v python3.11 >/dev/null 2>&1; then
    command -v python3.11
    return
  fi
  if command -v python3.12 >/dev/null 2>&1; then
    command -v python3.12
    return
  fi
  if command -v python >/dev/null 2>&1; then
    command -v python
    return
  fi
  echo "python3"  # last resort; caller will fail clearly
}

# Hermes profile slugs only. Blocks path traversal (--profile ../.ssh).
validate_profile_name() {
  local profile="$1"
  if [[ -z "$profile" ]]; then
    echo "FAIL: empty profile name" >&2
    return 2
  fi
  if [[ ! "$profile" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "FAIL: invalid profile name '$profile' (use a Hermes slug: letters, numbers, . _ -)" >&2
    return 2
  fi
  return 0
}

# Lab YOLO turns off Hermes command approvals. Require an explicit confirm
# so a public clone + curious flag cannot silently disable the safety rail.
require_lab_yolo_confirm() {
  if [[ "${LAB_YOLO:-0}" != "1" ]]; then
    return 0
  fi
  if [[ "${CONFIRM_LAB_YOLO:-}" != "I_UNDERSTAND" ]]; then
    echo "REFUSING --lab-yolo / LAB_YOLO=1" >&2
    echo "This sets approvals.mode=off (the agent can run shell without asking)." >&2
    echo "If you really want that on a disposable lab machine:" >&2
    echo "  CONFIRM_LAB_YOLO=I_UNDERSTAND LAB_YOLO=1 ./scripts/install.sh --profile NAME --lab-yolo" >&2
    return 2
  fi
  echo "WARN: LAB YOLO enabled — command approvals will be turned OFF"
  return 0
}

profile_home() {
  local profile="$1"
  validate_profile_name "$profile" || return 2
  echo "${HERMES_PROFILES_ROOT:-$HOME/.hermes/profiles}/$profile"
}

# Discover all profiles that have a config.yaml (i.e. real, usable profiles).
# Prints one profile name per line. Skips directories without config.yaml.
discover_profiles() {
  local root="${HERMES_PROFILES_ROOT:-$HOME/.hermes/profiles}"
  if [[ ! -d "$root" ]]; then
    return 0
  fi
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local name
    name="$(basename "$entry")"
    if [[ -f "$entry/config.yaml" ]]; then
      if ! validate_profile_name "$name" >/dev/null 2>&1; then
        echo "WARN: skipping non-slug profile directory: $name" >&2
        continue
      fi
      echo "$name"
    fi
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
}

# Parse --profile argument which may be:
#   --profile NAME        (single)
#   --profile NAME1,NAME2 (comma-separated)
# Prints one profile per line on stdout.
# If ALL_PROFILES=1 is set, calls discover_profiles instead.
parse_profiles() {
  local arg="$1"
  if [[ "${ALL_PROFILES:-0}" == "1" ]]; then
    discover_profiles
    return
  fi
  if [[ -z "$arg" ]]; then
    return
  fi
  local IFS=','
  local p
  for p in $arg; do
    p="${p// /}"
    [[ -z "$p" ]] && continue
    validate_profile_name "$p" || return 2
    echo "$p"
  done
}

stamp_dir() {
  local root="$1"
  echo "$root/.truth-stamps"
}

write_stamp() {
  local root="$1" phase="$2" status="$3" detail="${4:-}"
  local d
  d="$(stamp_dir "$root")"
  mkdir -p "$d"
  local f="$d/${phase}.${status}"
  {
    echo "phase=$phase"
    echo "status=$status"
    echo "ts=$(date -Iseconds 2>/dev/null || date)"
    echo "detail=$detail"
  } >"$f"
  # remove opposite stamp
  if [[ "$status" == "PASS" ]]; then
    rm -f "$d/${phase}.FAIL"
  else
    rm -f "$d/${phase}.PASS"
  fi
  echo "$f"
}

# Marker that brackets the append-only reliability soft block in working-style.
ws_soft_marker() {
  echo "# Reliability stack (hermes-reliability-recipe)"
}

# True if profile working-style carries the soft LIE / truth_run block.
# Usage: profile_has_ws_soft_block <profile_home>
profile_has_ws_soft_block() {
  local home_p="$1"
  local ws="$home_p/working-style-instruction.md"
  local marker
  marker="$(ws_soft_marker)"
  [[ -f "$ws" ]] || return 1
  grep -qF "$marker" "$ws" 2>/dev/null \
    && grep -q 'LIE/HALLUCINATION' "$ws" 2>/dev/null \
    && grep -qi 'truth_run_wrap' "$ws" 2>/dev/null
}

# Ensure profile working-style has the reliability soft block (idempotent).
# Never overwrites existing non-marker content — appends under marker, or
# installs the template when the file is missing.
# Usage: ensure_working_style_soft_block <profile_home> <recipe_root>
# Prints one of: installed | appended | skipped
# Exit 0 on success, 1 on failure (stdout may be failed:...).
ensure_working_style_soft_block() {
  local home_p="$1"
  local recipe_root="$2"
  local marker ws_target ws_template ws_bak
  marker="$(ws_soft_marker)"
  ws_target="$home_p/working-style-instruction.md"
  ws_template="$recipe_root/recipe/templates/working-style-instruction.md"

  if [[ ! -f "$ws_template" ]]; then
    echo "failed:template_missing"
    return 1
  fi
  mkdir -p "$home_p"

  if [[ ! -f "$ws_target" ]]; then
    cp -f "$ws_template" "$ws_target"
    if profile_has_ws_soft_block "$home_p"; then
      echo "installed"
      return 0
    fi
    echo "failed:postcondition_install"
    return 1
  fi

  if profile_has_ws_soft_block "$home_p"; then
    # Upgrade path: older soft blocks lack host-facts bullets — append if missing.
    if ! grep -qF 'Host / live facts' "$ws_target" 2>/dev/null; then
      ws_bak="$ws_target.bak.$(date +%Y%m%d-%H%M%S)"
      cp -a "$ws_target" "$ws_bak"
      cat >>"$ws_target" <<'HOSTFACTS'

# Host / live facts
Disk, git, processes, fleet, "what's on this machine": tools this turn or BLOCKED — not memory alone.
MEMORY.md is an index, not live state.
Never narrate tool use without real tool_calls.
User says check/verify/thoroughly → at least one real tool before the final answer.
HOSTFACTS
      echo "upgraded-host-facts"
      return 0
    fi
    echo "skipped"
    return 0
  fi

  # Backup before surgical edit (hard rule)
  ws_bak="$ws_target.bak.$(date +%Y%m%d-%H%M%S)"
  cp -a "$ws_target" "$ws_bak"

  # If a stale marker exists without content signals, strip it first so we
  # do not stack duplicate markers.
  if grep -qF "$marker" "$ws_target" 2>/dev/null; then
    WS="$ws_target" MARKER="$marker" "$(resolve_python)" - <<'PY'
import os
from pathlib import Path
ws = Path(os.environ["WS"])
marker = os.environ["MARKER"]
text = ws.read_text()
if marker in text:
    text = text.split(marker)[0].rstrip() + "\n"
    ws.write_text(text)
PY
  fi

  {
    echo ""
    echo "$marker"
    echo "---"
    cat "$ws_template"
  } >>"$ws_target"

  if profile_has_ws_soft_block "$home_p"; then
    echo "appended"
    return 0
  fi
  echo "failed:postcondition_append"
  return 1
}
