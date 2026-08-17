# Doctor

## What

Single health check: prints **PASS** or **FAIL** for the reliability stack on one Hermes profile. This is the only authority for “install done.”

## Who

Human or agent. After install, after Hermes upgrade, after config edits. Agents must not claim install success without doctor PASS (`AGENTS.md`).

## Where

Reads the recipe repo and `~/.hermes/profiles/<NAME>/` (config, bin, working-style, state). Optionally checks Hermes `conversation_loop.py` for always-on `pre_verify`.

## When

- Right after install
- After every Hermes upgrade
- After toggle / manual config edits
- When something feels wrong

## Why

One command replaces “I think it’s installed.” Failures name the missing piece.

## What it checks

1. **Hermes on PATH**
2. **PyYAML** (via resolved Python — Hermes venv / python3 / python3.11 / …)
3. **Recipe claim gate** present
4. **Gate unit tests** (8 tests)
5. **Truth binary** — present **and runnable** (not just `chmod +x`)
6. **Truth-mcp binary** present
7. **Profile stack** — `pre_verify` hook, `verify_on_stop`, truth MCP (unless `--allow-no-truth`), coding_instructions, state, gate in profile bin, working-style soft block (marker + `LIE/HALLUCINATION` + `truth_run_wrap`)
8. **Always-on pre_verify** in Hermes source (unless `--skip-patch`)
9. **Recipe template** hazard lines
10. **Profile working-style soft block** live file

## Tradeoffs

| Tradeoff | Pro | Con |
|----------|-----|-----|
| Single PASS/FAIL | Clear | Only checks this checklist (not API keys, not model quality) |
| Truth must run | Catches GLIBC “file exists but crashes” | Older Linux needs `--allow-no-truth` |
| `--allow-no-truth` | Claim-gate-only installs can still PASS | You knowingly drop receipt layer |

## Recommendation

- Full stack: `./scripts/doctor.sh --profile YOUR_PROFILE` → need PASS with no truth warnings.
- Claim-gate-only (old GLIBC / no truth download):  
  `./scripts/doctor.sh --profile YOUR_PROFILE --allow-no-truth`
- Skip global patch check if you refused the Hermes patch: `--skip-patch`

## Plain English

Doctor is the “is the lie detector plugged in?” button. Green means the pieces we install are present and wired. It does not mean your model is smart or your API key works.

## Commands

```bash
./scripts/doctor.sh --profile YOUR_PROFILE

# Also require gateway up
./scripts/doctor.sh --profile YOUR_PROFILE --require-gateway

# Do not fail on missing Hermes always-on patch
./scripts/doctor.sh --profile YOUR_PROFILE --skip-patch

# Claim-gate-only: do not fail if truth / truth-mcp missing or not runnable
./scripts/doctor.sh --profile YOUR_PROFILE --allow-no-truth
```

## Output

Success:
```text
DOCTOR PASS profile=YOUR_PROFILE
```

Failure names issues:
```text
  - FAIL: <what's wrong>
DOCTOR FAIL profile=YOUR_PROFILE issues=<list>
```

With `--allow-no-truth`, missing/unrunnable truth is a **WARN**, not a FAIL.

## Dogfood note

On WSL2 Debian 11, doctor without `--allow-no-truth` correctly failed once truth was present but not runnable; with `--allow-no-truth`, claim-gate-only install reported PASS after patch + soft working-style were fixed.
