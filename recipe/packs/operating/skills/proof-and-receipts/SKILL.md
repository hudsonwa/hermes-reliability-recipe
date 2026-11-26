---
name: proof-and-receipts
version: 0.3.0
description: "Use before saying anything is done, written, passing or current: how to prove it with tools and receipts."
author: hermes-reliability-recipe operating pack
platforms: [macos, linux]
metadata:
  hermes:
    tags: [verification, reliability, receipts]
---

# Proof and receipts

## Before a finish-line sentence
- "Wrote / saved / created X": stat or re-read X this turn; quote its path and size or first line.
- "Tests pass": run them through `bin/truth_run_wrap.sh -- <cmd>` in the project folder and quote
  the result line and exit code. Call `mcp__truth__verify_turn` if it is available.
- "The page / register / deadline says …": quote it from a source you loaded this turn, with the
  URL or file path and the as-of date.
- Green results from a different folder or project do not count.
- Exit code 0 is not proof: a run can exit 0 with FAIL in its output or with writes skipped.
  Read the output and check the files exist.
- A check you did not actually record is NOT CHECKED, never PASS.
- "What is running / what is the status": answer from live state (process list, file, page)
  this turn, not from your last note.

## The claim gate
A stop-time gate reads your draft answer. If it prints `>>> LIE/HALLUCINATION CAUGHT ... <<<`,
it found a claim without proof. Do not argue with it in prose: run the missing check, or rewrite
the claim as PARTIAL/FAILED/NOT CHECKED.

## Report shape
Done: … (evidence) · Not done: … · Not checked: … · Next: …
