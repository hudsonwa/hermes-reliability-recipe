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

1. **Hermes on PATH** (falls back to known venv install locations in non-interactive shells)
2. **PyYAML** (via resolved Python — Hermes venv / python3 / python3.11 / …)
3. **Recipe claim gate** present
4. **Gate unit tests** (11 unit tests + 5 seam-ledger tests)
5. **Truth binary** — present **and runnable** (not just `chmod +x`)
6. **Truth-mcp binary** present
7. **Profile stack** — `pre_verify` hook, `verify_on_stop`, truth MCP (unless `--allow-no-truth`), coding_instructions, state, gate in profile bin
8. **Profile gate hash** — sha256 of profile `bin/pre_verify_claim_gate.py` must match `recipe/bin/pre_verify_claim_gate.py`. Mismatch = `profile_gate_stale` (fail-closed). Skip with `HRR_DOCTOR_ALLOW_STALE_BINS=1` for an intentionally diverged profile only.
9. **Profile gate-tests hash** — sha256 of profile `bin/test_claim_gate.py` vs recipe. Missing or mismatch = `profile_gate_tests_stale`. Same skip env as item 8 (not a second dialect).
10. **Pytest interpreter** — if profile `coding_instructions` contain `python3 -m pytest` **and** that `python3` cannot `import pytest`, fail `pytest_python_cannot_import`. Venv/import-ok instructions skip. No pytest instruction → WARN only (do not force pytest on every public clone).
11. **Always-on pre_verify** in Hermes source (unless `--skip-patch`)
12. **Recipe template** hazard lines
13. **Profile working-style soft block** — one of three failure codes (see below)

## Working-style soft block codes

The soft block (marker + `LIE/HALLUCINATION` + `truth_run_wrap` lines) is checked in three distinct states, so a failure names the actual missing piece:

- `working_style_missing` — no `working-style-instruction.md` in the profile at all. Fix: `./scripts/install.sh --profile NAME` (or `./scripts/reliability-toggle.sh on --profile NAME`).
- `working_style_marker_missing` — the file exists but lacks the `# Reliability stack (hermes-reliability-recipe)` marker. A clone can ship the LIE/truth_run lines without the marker; doctor still names the marker miss. Fix: `./scripts/reliability-toggle.sh on --profile NAME` appends the soft block (existing content is kept).
- `working_style_lie_truth_run_missing` — the marker is present but the LIE/truth_run lines are missing. Fix: re-run `toggle on`, or restore from the `.bak` backup.

The working-style file is **required**, not optional; install and toggle create/restore it.

## Non-interactive shells (SSH, cron, CI)

A login shell usually puts the Hermes venv on PATH; an SSH command, cron job, or CI step does not. Doctor still passes the hermes prereq in that case by falling back to the known install locations (honoring `HERMES_AGENT_ROOT` and `HERMES_PROFILES_ROOT`):

1. `$HERMES_AGENT_ROOT/venv/bin/hermes` (default `~/.hermes/hermes-agent/venv/bin/hermes`)
2. `<profile home>/hermes-agent/venv/bin/hermes`
3. `~/.local/bin/hermes`, `~/bin/hermes`

It prints the found binary and the PATH line to add; only when none exists does doctor fail `hermes_missing`. To remove the fallback entirely, invoke doctor with the venv on PATH:

```bash
export PATH="$HOME/.hermes/hermes-agent/venv/bin:$PATH"
./scripts/doctor.sh --profile YOUR_PROFILE
```

## Profile gate hash (`profile_gate_stale`)

Doctor used to PASS when the live profile still ran an old `pre_verify_claim_gate.py`. It now sha256-compares that file to the recipe copy and fails `profile_gate_stale` on mismatch.

`.truth-stamps/05-doctor.PASS` is **last-writer**: a PASS for profile A does not mean profile B is hashed-fresh. Re-run doctor per profile.

Intentionally diverged profiles (you keep a patched gate on purpose):

```bash
HRR_DOCTOR_ALLOW_STALE_BINS=1 ./scripts/doctor.sh --profile YOUR_PROFILE
```

Default is fail. Do not set this on a normal install.

The same skip env covers `test_claim_gate.py` (`profile_gate_tests_stale` when the profile copy is missing or its hash differs). There is not a second skip dialect.

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

# Intentionally diverged profile gate (skip sha256 vs recipe)
HRR_DOCTOR_ALLOW_STALE_BINS=1 ./scripts/doctor.sh --profile YOUR_PROFILE
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
