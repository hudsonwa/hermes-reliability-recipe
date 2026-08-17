# Self-heal

## What it does

Checks the reliability stack health, and if anything is broken, re-syncs files and re-toggles the stack on. Then re-checks to confirm the fix worked.

## Who should run this

Can be run by a cron job (automated) or by a human or agent. Use `--check-only` to diagnose without fixing.

## Where it operates

`~/.hermes/profiles/<NAME>/` — checks and repairs config, bin files, working-style, and state.

## When to run it

- On a schedule (cron) for automated recovery
- After a Hermes upgrade that may have reset config
- After someone edited config by hand and broke something
- Use `--check-only` to diagnose without making changes

## Why it exists

If a Hermes upgrade or manual config edit knocks out the hooks, self-heal puts them back without you doing it manually. It re-syncs the gate script, restores the working-style, and re-toggles the stack on.

## Tradeoffs

| Tradeoff | Pro | Con |
|----------|-----|-----|
| Automatic recovery | No manual intervention needed | It re-toggles on — if you intentionally turned the stack off, self-heal would turn it back on |
| `--check-only` mode | Diagnose without changes | Still need to run full heal to fix |
| Profile path from `--profile` only | Can't accidentally heal the wrong profile | Ignores ambient `HERMES_HOME` env var (by design) |

## Recommendation

Use `--check-only` for diagnosis. Use full heal for cron or automated recovery. **Don't run full heal if you intentionally turned the stack off** — it will turn it back on.

## Plain English

If something knocks the reliability stack out of alignment — like a Hermes update or someone editing config by hand — this script detects it and puts everything back. You can also run it in check-only mode to see what's broken without it fixing anything.

## Commands

```bash
# Check only (diagnose, no changes)
./scripts/reliability-selfheal.sh --profile YOUR_PROFILE --check-only

# Full heal (check → fix → recheck)
./scripts/reliability-selfheal.sh --profile YOUR_PROFILE

# Force heal even if check says OK
./scripts/reliability-selfheal.sh --profile YOUR_PROFILE --force-heal

# Verbose output
SELFHEAL_VERBOSE=1 ./scripts/reliability-selfheal.sh --profile YOUR_PROFILE
```

## Log

Self-heal writes to `~/.hermes/profiles/<NAME>/logs/reliability_selfheal.jsonl` with timestamps, before/after status, and actions taken.
