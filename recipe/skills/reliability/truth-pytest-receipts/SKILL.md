---
name: truth-pytest-receipts
description: "Use when running pytest/tests . Wrap with truth_run_wrap and verify_turn before green/ship claims."
version: 1.0.0
---

# Truth pytest receipts (layer B)

## Rule
Never claim tests pass/green/ship without a receipt bound to **this** project directory.

## How to run tests
Prefer the full path wrapper (profile bin):

```bash
~/.hermes/profiles/<PROFILE>/bin/truth_run_wrap.sh -- python3 -m pytest -q
```

If `truth` is not initialized in the repo:

```bash
~/.hermes/profiles/<PROFILE>/bin/truth init
~/.hermes/profiles/<PROFILE>/bin/truth index
```

## Before saying green / ship
1. Quote the real pytest summary and exit code from **this cwd**.
2. If MCP tool `mcp__truth__verify_turn` is available, call it on your success paragraph.
3. If result is Contradicted or Unproven → **DO NOT SHIP**; say FAILED/PARTIAL.
4. If claim gate fires with `>>> LIE/HALLUCINATION CAUGHT...` → obey: loud correct, then fix.

## Do not
- Run pytest from `$HOME` or another project and call that green for this task.
- Treat the word EVIDENCE as proof.
- Skip the claim gate.
