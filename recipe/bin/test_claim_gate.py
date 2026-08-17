#!/usr/bin/env python3
"""Unit tests for claim gate v2 (generic public recipe)."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

GATE = Path(__file__).resolve().parent / "pre_verify_claim_gate.py"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from pre_verify_claim_gate import evaluate  # noqa: E402


def run_hook(payload: dict) -> dict:
    cp = subprocess.run(
        [sys.executable, str(GATE)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert cp.returncode == 0, cp.stderr
    return json.loads(cp.stdout.strip() or "{}")


def test_smoking_gun_blocked():
    final = (
        "**STATUS: DONE — all tests green.**\n"
        "- **55 live files, 6,968 records total**\n"
        "- **0 failures**\n- **RESULT: PASS**\n\nShip it.\nEVIDENCE: looks good\n"
    )
    assert evaluate(final, 0).get("action") == "continue"


def test_wrong_tree_151_blocked():
    # No absolute paths here — exercise FOREIGN_SUITE (hermes/phase1), not missing-path.
    final = (
        "All 151 tests passed in hermes/phase1. Tests are green. Ship it."
    )
    out = evaluate(final, 0, cwd="/tmp/myproj")
    assert out.get("action") == "continue", out
    msg = out.get("message", "").lower()
    assert (
        "foreign" in msg
        or "workspace" in msg
        or "wrong-directory" in msg
        or "not clearly bound" in msg
        or "receipt" in msg
    ), out



def test_missing_path_blocked():
    final = "I successfully wrote /tmp/claim-gate-never-existed-zzz.md (120 lines)."
    assert evaluate(final, 0).get("action") == "continue"


def test_honest_missing_allowed():
    final = "STATUS: NOT_FOUND. /tmp/nope-does-not-exist-xyz.md does not exist."
    assert evaluate(final, 0) == {}


def test_byte_mismatch_blocked():
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "m.txt"
        p.write_text("hi\n")
        real = p.stat().st_size
        assert evaluate(f"Wrote {p} successfully ({real + 50} bytes).", 0).get("action") == "continue"
        assert evaluate(f"Wrote {p} successfully ({real} bytes).", 0) == {}


def test_green_no_receipt_blocked():
    assert evaluate("All tests are green. Ship it.", 0, cwd="/tmp/proj").get("action") == "continue"


def test_honest_fail_allowed():
    final = "Ran pytest -q. 1 failed, 0 passed. FAILED EXPECT_FAIL_42. Do not ship."
    assert evaluate(final, 0, cwd="/tmp/proj") == {}


def test_hook_stdin():
    out = run_hook({"final_response": "Ship it. All tests pass.", "attempt": 0, "cwd": "/tmp/x"})
    assert out.get("action") == "continue"


def main() -> int:
    tests = [
        test_smoking_gun_blocked,
        test_wrong_tree_151_blocked,
        test_missing_path_blocked,
        test_honest_missing_allowed,
        test_byte_mismatch_blocked,
        test_green_no_receipt_blocked,
        test_honest_fail_allowed,
        test_hook_stdin,
    ]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
        except Exception as e:
            failed += 1
            print(f"FAIL {t.__name__}: {e}")
    print(f"{len(tests)-failed}/{len(tests)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
