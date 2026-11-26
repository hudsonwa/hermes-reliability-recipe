---
name: plan-to-issues
version: 0.3.0
description: "Use when asked to plan work, cut a plan into tracker issues, or run planned work item by item with proof."
author: hermes-reliability-recipe operating pack
platforms: [macos, linux]
metadata:
  hermes:
    tags: [planning, issues, receipts, verification]
---

# Plan → issues → proven close

Your SOUL's approval rules always win over this skill.

## 1. Plan request = plan only
When asked to plan: read the real sources first, then write in your work folder
`plans/<topic>/spec.md` (problem, what "done" means as a check, constraints, out of scope) and
`plans/<topic>/plan.md` (approach, files/sources, order, risks, checklist). Every checklist item
has a done-test someone else can run or look at. Then STOP and report the plan. Do not start work
and do not create issues as a side effect.

## 2. Cut into issues (preview first)
Write `plans/<topic>/issues.preview.md` before touching any tracker. One issue per outcome that a
fresh agent can finish in one sitting with one proof. Every issue has:

    Title: [area] one concrete outcome
    Why: what it unblocks
    Change: exact files / sources
    Proof: exact command or check
    Do not touch: explicit list
    Blocked by: issue or none
    Default if stuck: the named fallback
    Receipt on close: command, exit code / evidence path, what this did NOT prove

Not issues: "investigate", "clean up", "Phase 2", "make X work". A 12-step plan is usually 6–12 issues.
Split an issue that has two proofs. Keep together only if splitting puts two workers on the same lines.

## 3. Creating issues on a forge
Creating, editing or closing issues on GitHub/Forgejo is outward: only with the owner's yes for
that action. Before creating: dedupe against open issues. Never put secrets, client data or
private compliance evidence in an issue.

## 4. Working the checklist (after GO)
- One item at a time. Run its done-test. Mark done only on a pass, with the evidence in log.md.
- Never delete or weaken a checklist item to look finished.
- A routine decision: record "Decision: …" in log.md and continue. A decision covered by an
  approval rule: stop and ask.
- Wrong-but-moving: write a follow-up item rather than silently changing the spec.
- Finish: list each item PASS / FAIL / NOT DONE with its evidence. Done means every done-test passed.
