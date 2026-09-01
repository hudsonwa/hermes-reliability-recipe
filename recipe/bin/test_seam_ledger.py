#!/usr/bin/env python3
"""Unit tests for the machine-written seam ledger (no LLM)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from seam_ledger import extract_last_error, render_ledger, retry_decision  # noqa: E402


def test_extracts_traceback_signal():
    blob = (
        "running tests\n"
        "Traceback (most recent call last):\n"
        '  File "app.py", line 3, in <module>\n'
        "    open('missing.txt')\n"
        "FileNotFoundError: [Errno 2] No such file or directory: 'missing.txt'\n"
    )
    err = extract_last_error(blob)
    assert err is not None
    assert "FileNotFoundError" in err
    assert "missing.txt" in err


def test_clean_output_has_no_last_error():
    assert extract_last_error("ok\n3 passed in 0.12s\n") is None


def test_render_ledger_is_only_machine_fields():
    text = render_ledger(
        goal="OUT exists and matches ls",
        verified=["pytest -q in this cwd — 3 passed, unit tests only"],
        open_items=["Telegram path untested"],
        next_action="add coverage clause test",
        last_error="FileNotFoundError: missing.txt",
        model_opinion="I am sure the fix works",
    )
    assert "Goal: OUT exists and matches ls" in text
    assert "LastError: FileNotFoundError: missing.txt" in text
    assert "I am sure the fix works" not in text
    assert "Verified:" in text
    assert "Open:" in text
    assert "Next: add coverage clause test" in text


def test_same_fingerprint_twice_retries_once():
    fp = "filenotfounderror:missing.txt"
    assert retry_decision([], fp) == "none"
    assert retry_decision([fp], fp) == "retry"
    assert retry_decision([fp, fp], fp) == "stop"


def test_different_fingerprint_does_not_retry():
    assert retry_decision(["filenotfounderror:a"], "typeerror:b") == "none"


def main() -> int:
    tests = [
        test_extracts_traceback_signal,
        test_clean_output_has_no_last_error,
        test_render_ledger_is_only_machine_fields,
        test_same_fingerprint_twice_retries_once,
        test_different_fingerprint_does_not_retry,
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
