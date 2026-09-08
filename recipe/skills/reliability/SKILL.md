---
name: truth-receipts
description: "Use when running tests or claiming code/file/test success. Record receipts via truth and verify_turn."
version: 1.0.0
---

# Truth receipts (layer 2)

Always-on claim gate is the hard stop. Truth strengthens **test/code** claims.

## When claiming tests pass / green / ship

1. Run tests from the **project workdir** only.
2. Prefer wrapping a python that can `import pytest` (typically `"$HERMES_VENV/python" -m pytest -q` via `truth_run_wrap.sh`, or `truth run -- "$HERMES_VENV/python" -m pytest -q`). Do not assume system `python3` has pytest.
3. The recipe's own gate suite is **not** pytest: run `python recipe/bin/test_claim_gate.py` (not unittest, not `python3 -m pytest` on that file).
4. If MCP tool `mcp_truth_verify_turn` / `verify_turn` is available, call it on your own success paragraph before finishing.
5. If verify_turn returns Contradicted or Unproven, do **not** ship — report FAILED/PARTIAL with the verdict.
6. Foreign suites (e.g. 151 passed from another tree) never count.

## When claiming file/code edits

- Stat/read the paths. Gate checks existence/bytes.
- For structured code claims ("added route X"), prefer verify_turn after real edits + index (`truth init` / `truth index` once per repo).

## Do not

- Skip the claim gate.
- Treat the word EVIDENCE as proof.
- Call tests done without a local receipt.
