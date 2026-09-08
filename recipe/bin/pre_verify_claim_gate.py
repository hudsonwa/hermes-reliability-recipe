#!/usr/bin/env python3
"""Hermes pre_verify claim gate v2 — always-on capable stop gate (public kernel).

Blocks ungrounded success claims. Deterministic; no LLM.

v2 additions:
- Respect payload cwd / CLAIM_GATE_CWD / HERMES_CLAIM_GATE_CWD for test-claim binding
- Reject wrong-tree green theater (foreign suite names + ship/green without local receipt)
- Still refuses EVIDENCE-word cosplay as proof

stdin JSON (Hermes shell hook): final_response, attempt, changed_paths, cwd, ...
stdout JSON: {} or {"action":"continue","message":"..."}
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

SUCCESS_PAT = re.compile(
    r"\b("
    r"wrote|created|saved|generated|appended|updated|"
    r"all tests pass|tests? pass(?:ed|ing)?|tests? (?:are )?green|"
    r"0 failed|ready to (?:merge|ship)|ship it|"
    r"successfully|all done|STATUS:\s*DONE|RESULT:\s*PASS|"
    r"report (?:is )?at|file (?:is )?at"
    r")\b",
    re.I,
)

PATH_PAT = re.compile(r"(/(?:Users|home|tmp|var|opt|Users/Shared)/[^\s`\'\"\)\]\,\:]+)")

FAIL_OK = re.compile(
    r"\b("
    r"NOT_FOUND|FAILED|PARTIAL|FAIL\b|does not exist|do not exist|"
    r"no such file|could not|couldn't|cannot find|not found|"
    r"tests? fail|not pass|not green|still fail|1 failed|failed,"
    r")\b",
    re.I,
)

TEST_RECEIPT = re.compile(
    r"("
    r"exit[_ ]?code\s*[=:]?\s*\d+"
    r"|pytest"
    r"|\b\d+\s+failed\b"
    r"|\b\d+\s+passed\b"
    r"|\b\d+\s+error(s)?\b"
    r"|====+|FAILURES|AssertionError"
    r"|returned non-zero|returncode\s*=\s*\d+"
    r"|EXPECT_FAIL"
    r")",
    re.I,
)

TESTS_PASS_CLAIM = re.compile(
    r"\b("
    r"all tests? pass"
    r"|tests? (?:are )?(?:pass(?:ed|ing)?|green)"
    r"|0 failed"
    r"|ready to (?:merge|ship)"
    r"|ship it"
    r"|RESULT:\s*PASS"
    r"|STATUS:\s*DONE[^\n]{0,40}(test|green|pass)"
    r")\b",
    re.I,
)

BYTES_NEAR_PATH = re.compile(
    r"(/(?:Users|home|tmp|var|opt|Users/Shared)/[^\s`'\"\)\]\,\:]+).{0,80}?(\d+)\s*bytes"
    r"|(\d+)\s*bytes.{0,80}?(/(?:Users|home|tmp|var|opt|Users/Shared)/[^\s`'\"\)\]\,\:]+)",
    re.I | re.S,
)
LINES_NEAR_PATH = re.compile(
    r"(/(?:Users|home|tmp|var|opt|Users/Shared)/[^\s`'\"\)\]\,\:]+).{0,80}?(\d+)\s*lines"
    r"|(\d+)\s*lines.{0,80}?(/(?:Users|home|tmp|var|opt|Users/Shared)/[^\s`'\"\)\]\,\:]+)",
    re.I | re.S,
)


# Planted / canned "success theater" numbers. Base patterns are intentionally
# generic (grouped-number stats). Add your own incident patterns via
# CLAIM_GATE_STATS_EXTRA (comma-separated regex fragments). Built per call so
# in-process users (tests) can set the env dynamically.
def _stats_pattern() -> "re.Pattern[str]":
    base = r"\b\d{1,3}(?:,\d{3})+\s+(?:bytes|records|files)\b"
    extra = os.environ.get("CLAIM_GATE_STATS_EXTRA", "").strip()
    parts = [p.strip() for p in extra.split(",") if p.strip()]
    return re.compile(base + ("|" + "|".join(parts) if parts else ""), re.I)

# Foreign suite markers: common wrong-tree / host-wide theater.
# Extra patterns: CLAIM_GATE_FOREIGN_EXTRA (comma-separated regex fragments).
# Generic wrong-tree markers. Machine-specific incident markers belong in
# CLAIM_GATE_FOREIGN_EXTRA (comma-separated regex fragments), not in the
# shipped defaults — a fixed "151 passed" can misfire on innocent suites.
def _foreign_pattern() -> "re.Pattern[str]":
    base = (
        r"/\.hermes/hermes-agent(?:/|$)"
        r"|site-packages/.+/tests"
    )
    extra = os.environ.get("CLAIM_GATE_FOREIGN_EXTRA", "").strip()
    parts = [p.strip() for p in extra.split(",") if p.strip()]
    if parts:
        base = base + "|" + "|".join(parts)
    return re.compile(rf"\b({base})\b", re.I)

# Finish-line "verified/done" without a named check + coverage (J-Space --by).
VERIFIED_DONE_CLAIM = re.compile(
    r"\b("
    r"verified the\b"
    r"|the task is done\b"
    r"|task is complete\b"
    r")",
    re.I,
)
COVERAGE_CLAUSE = re.compile(
    r"\b(coverage|covers\b|covered by|verified by)\b"
    r"|pytest"
    r"|exit[_ ]?code",
    re.I,
)

MAX_ATTEMPT_SOFT = 2
MAX_ATTEMPT_HARD = 3


def _paths_in(text: str) -> list[str]:
    found = []
    for m in PATH_PAT.findall(text):
        p = m.rstrip(".,;:)*`")
        if p not in found:
            found.append(p)
    return found


def _line_count(path: Path) -> int:
    try:
        data = path.read_bytes()
    except OSError:
        return -1
    if not data:
        return 0
    n = data.count(b"\n")
    if not data.endswith(b"\n"):
        n += 1
    return n


def _resolve_cwd(payload: dict | None = None) -> str:
    payload = payload or {}
    for key in ("cwd", "workdir", "working_directory"):
        v = payload.get(key)
        if isinstance(v, str) and v.strip():
            return v.strip()
    extra = payload.get("extra") if isinstance(payload.get("extra"), dict) else {}
    for key in ("cwd", "workdir"):
        v = extra.get(key)
        if isinstance(v, str) and v.strip():
            return v.strip()
    for envk in ("CLAIM_GATE_CWD", "HERMES_CLAIM_GATE_CWD", "PWD"):
        v = os.environ.get(envk)
        if v and v.strip():
            return v.strip()
    try:
        return str(Path.cwd())
    except Exception:
        return ""


def _force_partial_msg(reason: str) -> dict:
    return {
        "action": "continue",
        "message": (
            "🚨🚨🚨 HALLUCINATION / LIE DETECTED — CLAIM GATE FINAL 🚨🚨🚨\n"
            f"REASON: {reason}\n"
            "You MUST open your next reply with exactly this line:\n"
            ">>> LIE/HALLUCINATION CAUGHT BY CLAIM GATE — CORRECTING NOW <<<\n"
            "Then revise to STATUS PARTIAL or FAILED. "
            "Do not claim DONE, green tests, or ship. Do not invent paths, sizes, or foreign suite results. "
            "Quote only tool output from THIS workspace. Fix the false claim before anything else."
        ),
    }


def _continue(msg: str) -> dict:
    # Normalize so every block is LOUD and actionable
    body = msg
    if not body.startswith("🚨"):
        body = (
            "🚨 HALLUCINATION / UNGROUNDED SUCCESS CLAIM DETECTED 🚨\n"
            f"REASON: {msg}\n"
            "Open your next reply with:\n"
            ">>> LIE/HALLUCINATION CAUGHT BY CLAIM GATE — CORRECTING NOW <<<\n"
            "Then fix the claim with tools or admit FAILED/PARTIAL/NOT_FOUND."
        )
    return {"action": "continue", "message": body}


def _local_test_receipt(final: str, cwd: str) -> bool:
    """True if test receipt appears bound to cwd / local tests."""
    if not TEST_RECEIPT.search(final):
        return False
    if not cwd:
        # No cwd binding available — fall back to any receipt (v1 behavior)
        return True
    cwd_n = os.path.normpath(cwd)
    base = os.path.basename(cwd_n.rstrip("/"))
    # Explicit local anchors
    if cwd_n in final or base and re.search(rf"\b{re.escape(base)}\b", final):
        return True
    if re.search(r"\b(tests?/test_[\w.-]+\.py|pytest\s+-q\s+\.|python3?\s+-m\s+pytest[^\n]{0,40}\.)", final, re.I):
        return True
    if "EXPECT_FAIL" in final:
        return True
    # Foreign suite with big pass counts is NOT local
    if _foreign_pattern().search(final):
        return False
    # Generic "N passed" without local anchor — not good enough when cwd known
    if re.search(r"\b\d+\s+passed\b", final, re.I) and not re.search(
        r"\b\d+\s+failed\b", final, re.I
    ):
        return False
    return bool(TEST_RECEIPT.search(final) and FAIL_OK.search(final))


def _strip_quoted_for_claims(text: str) -> str:
    """Drop fenced blocks and markdown '>' quotes before claim regexes.

    Quoted stamp dumps (RESULT: PASS / DOCTOR PASS) must not alone trip
    tests-green. Regexes themselves stay unchanged.
    """
    stripped = re.sub(r"```.*?```", "\n", text, flags=re.S)
    stripped = re.sub(r"(?m)^>[^\n]*\n?", "", stripped)
    return stripped


def evaluate(final: str, attempt: int, changed_paths: list | None = None, cwd: str = "") -> dict:
    changed_paths = changed_paths or []
    final = final or ""
    cwd = cwd or ""
    claims = _strip_quoted_for_claims(final)

    honest = bool(FAIL_OK.search(claims))
    claims_tests_pass = bool(TESTS_PASS_CLAIM.search(claims))
    has_success = bool(SUCCESS_PAT.search(claims)) or claims_tests_pass

    if honest and not claims_tests_pass and not _stats_pattern().search(final):
        return {}

    if (
        VERIFIED_DONE_CLAIM.search(final)
        and not COVERAGE_CLAUSE.search(final)
        and not claims_tests_pass
    ):
        reason = (
            "verified/done claimed without coverage: name the check and what it covered "
            "(command + scope), or say FAILED/PARTIAL."
        )
        if attempt >= MAX_ATTEMPT_HARD:
            return {}
        if attempt >= MAX_ATTEMPT_SOFT:
            return _force_partial_msg(reason)
        return _continue("CLAIM GATE: " + reason)

    if not has_success and not _stats_pattern().search(final) and not (
        claims_tests_pass and _foreign_pattern().search(final)
    ):
        return {}

    paths = _paths_in(final)
    missing = [p for p in paths if not Path(p).exists()]

    if missing:
        reason = (
            "You asserted success but these paths do not exist on disk: "
            + ", ".join(missing[:8])
        )
        if attempt >= MAX_ATTEMPT_HARD:
            return {}
        if attempt >= MAX_ATTEMPT_SOFT:
            return _force_partial_msg(reason)
        return _continue(
            "CLAIM GATE: "
            + reason
            + ". Create them with tools, or revise to FAILED/NOT_FOUND/PARTIAL. "
            "EVIDENCE alone is not proof."
        )

    stat_mismatches = []
    for m in BYTES_NEAR_PATH.finditer(final):
        path = m.group(1) or m.group(4)
        claimed = m.group(2) or m.group(3)
        if not path or claimed is None:
            continue
        path = path.rstrip(".,;:)*`")
        p = Path(path)
        if not p.is_file():
            continue
        try:
            real = p.stat().st_size
        except OSError:
            continue
        if abs(int(claimed) - real) > 2:
            stat_mismatches.append(f"{path}: claimed {claimed} bytes, real {real}")

    for m in LINES_NEAR_PATH.finditer(final):
        path = m.group(1) or m.group(4)
        claimed = m.group(2) or m.group(3)
        if not path or claimed is None:
            continue
        path = path.rstrip(".,;:)*`")
        p = Path(path)
        if not p.is_file():
            continue
        real_lines = _line_count(p)
        if real_lines < 0:
            continue
        if abs(int(claimed) - real_lines) > 1 and int(claimed) >= 50:
            stat_mismatches.append(f"{path}: claimed {claimed} lines, real {real_lines}")

    if stat_mismatches:
        reason = "Stat mismatch vs disk: " + "; ".join(stat_mismatches[:6])
        if attempt >= MAX_ATTEMPT_HARD:
            return {}
        if attempt >= MAX_ATTEMPT_SOFT:
            return _force_partial_msg(reason)
        return _continue(
            "CLAIM GATE: "
            + reason
            + ". Re-stat/read and correct numbers, or drop the claim."
        )

    if _stats_pattern().search(final) and not honest:
        reason = (
            "Suspicious invented corpus/prior stats "
            "(485 lines / 17571 bytes / 6968 records / 55 files / 412 lines) "
            "without honest FAILED/PARTIAL."
        )
        if attempt >= MAX_ATTEMPT_HARD:
            return {}
        if attempt >= MAX_ATTEMPT_SOFT:
            return _force_partial_msg(reason)
        return _continue(
            "CLAIM GATE: " + reason + " Verify with tools or remove the numbers."
        )

    # Wrong-tree / foreign suite greens
    if claims_tests_pass and _foreign_pattern().search(final) and not honest:
        reason = (
            "Test success cites a foreign suite or host-wide pass count "
            f"(not clearly bound to workspace {cwd or 'current project'}). "
            "Wrong-directory greens are not proof."
        )
        if attempt >= MAX_ATTEMPT_HARD:
            return {}
        if attempt >= MAX_ATTEMPT_SOFT:
            return _force_partial_msg(reason)
        return _continue(
            "CLAIM GATE: "
            + reason
            + f" Re-run `python3 -m pytest -q` with cwd={cwd or '.'} and quote THAT output, "
            "or say FAILED/PARTIAL."
        )

    if claims_tests_pass:
        # Honest fail/partial with local-ish receipt → allow
        if honest and (TEST_RECEIPT.search(final) or "EXPECT_FAIL" in final):
            return {}
        # Explicit local green: cwd/base in text + N passed + no failed + not foreign
        local_anchor = bool(
            cwd
            and (
                cwd in final
                or os.path.basename(cwd.rstrip("/")) in final
                or re.search(r"\btests?/test_[\w.-]+\.py\b", final)
            )
        )
        clean_green = bool(
            re.search(r"\b\d+\s+passed\b", final, re.I)
            and not re.search(r"\b\d+\s+failed\b", final, re.I)
            and not _foreign_pattern().search(final)
            and local_anchor
        )
        if clean_green:
            return {}

        reason = (
            "Tests pass/green/ship claimed without a receipt clearly bound to "
            f"THIS workspace ({cwd or 'unknown cwd'}): pytest output + path/cwd, "
            "exit code, passed/failed counts. EVIDENCE word is not enough. "
            "Foreign '151 passed' results do not count."
        )
        if attempt >= MAX_ATTEMPT_HARD:
            return {}
        if attempt >= MAX_ATTEMPT_SOFT:
            return _force_partial_msg(reason)
        return _continue(
            "CLAIM GATE: "
            + reason
            + " Re-run tests here and quote real output, or correct to FAILED/PARTIAL."
        )

    if (
        changed_paths
        and re.search(r"\b(DONE|successfully)\b", final, re.I)
        and attempt < 1
        and not paths
        and not TEST_RECEIPT.search(final)
    ):
        return _continue(
            "CLAIM GATE: Files were edited. Before finishing, re-read/stat outputs "
            "or run tests in this workspace and quote real tool output."
        )

    return {}


def evaluate_from_payload(payload: dict) -> dict:
    final = str(payload.get("final_response") or "")
    # Hermes may nest kwargs
    if not final and isinstance(payload.get("extra"), dict):
        final = str(payload["extra"].get("final_response") or "")
    attempt = int(payload.get("attempt") or 0)
    if not attempt and isinstance(payload.get("extra"), dict):
        try:
            attempt = int(payload["extra"].get("attempt") or 0)
        except Exception:
            attempt = 0
    changed = payload.get("changed_paths") or []
    if not changed and isinstance(payload.get("extra"), dict):
        changed = payload["extra"].get("changed_paths") or []
    if not isinstance(changed, list):
        changed = []
    cwd = _resolve_cwd(payload)
    return evaluate(final, attempt, changed, cwd=cwd)


def _log_hit(payload: dict, out: dict) -> None:
    """Append gate hits to JSONL for ops visibility (A: visibility)."""
    if not isinstance(out, dict) or out.get("action") != "continue":
        return
    try:
        log_path = os.environ.get("CLAIM_GATE_LOG", "").strip()
        if not log_path:
            # Prefer profile home if HERMES_HOME set
            home = os.environ.get("HERMES_HOME") or str(Path.home() / ".hermes")
            log_path = str(Path(home) / "logs" / "claim_gate_hits.jsonl")
        Path(log_path).parent.mkdir(parents=True, exist_ok=True)
        final = str(payload.get("final_response") or "")
        if not final and isinstance(payload.get("extra"), dict):
            final = str(payload["extra"].get("final_response") or "")
        rec = {
            "ts": __import__("datetime").datetime.now().isoformat(timespec="seconds"),
            "cwd": _resolve_cwd(payload),
            "attempt": payload.get("attempt")
            or (payload.get("extra") or {}).get("attempt"),
            "session_id": payload.get("session_id")
            or (payload.get("extra") or {}).get("session_id"),
            "platform": payload.get("platform")
            or (payload.get("extra") or {}).get("platform"),
            "reason_preview": str(out.get("message") or "")[:500],
            "final_preview": final[:400],
            "loud": "LIE/HALLUCINATION CAUGHT" in str(out.get("message") or ""),
        }
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        print(json.dumps({}))
        return 0
    if not isinstance(payload, dict):
        print(json.dumps({}))
        return 0
    try:
        out = evaluate_from_payload(payload)
    except Exception as e:
        out = {
            "action": "continue",
            "message": (
                "🚨 HALLUCINATION / UNGROUNDED SUCCESS CLAIM DETECTED 🚨\n"
                f"REASON: CLAIM GATE internal error: {e}\n"
                "Open your next reply with:\n"
                ">>> LIE/HALLUCINATION CAUGHT BY CLAIM GATE — CORRECTING NOW <<<\n"
                "Prefer PARTIAL and re-verify."
            ),
        }
    try:
        _log_hit(payload, out if isinstance(out, dict) else {})
    except Exception:
        pass
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
