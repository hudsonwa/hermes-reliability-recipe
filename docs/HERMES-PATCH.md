# Hermes always-on pre_verify patch

## What it does

This patch changes one line in one file inside your Hermes installation.

**File:** `~/.hermes/hermes-agent/agent/conversation_loop.py`

**Before (stock Hermes):**
```python
if _edited and has_hook("pre_verify") and _attempt < max_verify_nudges():
```

**After (patched):**
```python
if has_hook("pre_verify") and _attempt < max_verify_nudges():
```

The `_edited and` condition is removed. That's the entire change.

## Plain English

Hermes has a checkpoint that runs before the agent's answer reaches you. By default, that checkpoint only fires if the agent edited files during that turn. That means if the agent just talks — claims tests pass, invents file paths, quotes results from the wrong directory — the checkpoint never runs.

This patch makes the checkpoint run every time, so the claim gate works even when the agent didn't edit anything.

Without this patch, the claim gate only catches lies on turns where the agent edited files. Turns where the agent just talked (pure hallucination) skip the gate entirely.

## Who should run this

The human runs this. It is not automatic. An agent following `INSTALL_PHASES.md` may run `--check` but should get human approval before `--apply`.

## Where it operates

`~/.hermes/hermes-agent/agent/conversation_loop.py` — this is your Hermes installation, not a profile directory.

**This is global.** It affects ALL profiles on your machine, not just the one you installed the recipe for. If you have multiple Hermes profiles, they all get the patched behavior.

## When to run it

- After installing the reliability recipe
- After every Hermes upgrade (`hermes update`, `pip install`, git pull) — the upgrade replaces `conversation_loop.py` and the patch is lost
- Run `--check` first; only `--apply` if the check fails

## Why it exists

Stock Hermes only runs `pre_verify` when the agent edited files during that turn. Pure hallucination (no edits, just lies) skips the gate entirely. This is the main failure mode the claim gate exists to catch — an agent saying "all tests pass, ship it" without editing anything. Without this patch, that lie sails straight through to you.

## Tradeoffs

| Tradeoff | Pro | Con |
|----------|-----|-----|
| Every turn gets gated | Catches pure-hallucination lies (the main threat) | Gate runs on every final answer, even simple chat. In practice it's fast — regex + filesystem checks, under 15ms. |
| Modifies upstream Hermes | Fixes a real gap in pre_verify behavior | Not an official change. Breaks on every Hermes upgrade — you must re-apply. |
| Global, not per-profile | One patch covers all profiles | Can't have some profiles gated and others not (unless you toggle hooks per-profile in config, which the recipe already does) |
| Regex-based patch | Works across versions that keep the same code pattern | Fragile — if Hermes changes variable names or condition structure, the patch can't find the pattern. Doctor will report FAIL and you re-apply manually. |

## Can I skip this?

Yes. The claim gate still works for turns where the agent edited files. You lose protection against pure-talk lies (agent claims tests pass without editing anything). Recommended, not mandatory.

## Can I undo this?

Yes. The patch creates a timestamped `.bak` backup beside `conversation_loop.py`. To restore:

```bash
./scripts/apply-hermes-preverify-patch.sh --unapply
```

This finds the most recent backup and restores it. It's global — affects all profiles.

## What if I update Hermes?

The update replaces `conversation_loop.py` and the patch is gone. Run:

```bash
./scripts/apply-hermes-preverify-patch.sh --check    # will show FAIL
./scripts/apply-hermes-preverify-patch.sh --apply    # re-applies
```

The doctor (`./scripts/doctor.sh --profile YOUR_PROFILE`) will also tell you if the patch is missing.

## Commands

```bash
./scripts/apply-hermes-preverify-patch.sh --check     # verify (no changes)
./scripts/apply-hermes-preverify-patch.sh --apply     # apply (backs up first)
./scripts/apply-hermes-preverify-patch.sh --unapply   # restore from backup
./scripts/apply-hermes-preverify-patch.sh --help      # usage
```

## Upstream

Prefer a first-class config flag in Hermes over perpetual patching. This recipe is unofficial; patch at your own risk. Long-term, a PR to Hermes for something like `agent.pre_verify_always: true` would eliminate the need for this patch.

## Verify

```bash
./scripts/doctor.sh --profile YOUR_PROFILE
# or
make test   # GT7 checks the patch when Hermes is present
```
