# Toggle

## What it does

Turns the reliability hooks, truth MCP server, coding instructions, SOUL lines, and `verify_on_stop` on or off in your profile's `config.yaml`. Does not remove files from disk — only changes config.

When turning **on**: adds the pre_verify hook, connects the truth MCP server, sets coding instructions, appends reliability lines to SOUL.md, and sets `verify_on_stop: true`.

When turning **off**: removes all of the above from config, and strips the reliability section from SOUL.md and working-style-instruction.md. Creates a backup of `config.yaml` before making changes.

## Who should run this

Human or agent. It's reversible and low risk — the toggle always backs up config before changing it.

## Where it operates

- `~/.hermes/profiles/<NAME>/config.yaml` — hooks, MCP, coding_instructions, verify_on_stop
- `~/.hermes/profiles/<NAME>/SOUL.md` — reliability section (appended on, stripped on off)
- `~/.hermes/profiles/<NAME>/working-style-instruction.md` — reliability section (appended on, stripped on off)

## When to run it

- **Off:** To temporarily disable the stack without uninstalling (e.g. debugging, testing agent behavior without the gate)
- **On:** To re-enable after turning off, or after a Hermes upgrade that may have reset config
- **Status:** To check the current state without changing anything

## Why it exists

Sometimes you want the gate off temporarily. Toggle off is faster than uninstall + reinstall — files stay on disk, only config changes. Use uninstall for permanent removal.

## Tradeoffs

| Tradeoff | Pro | Con |
|----------|-----|-----|
| Fast on/off without file removal | Quick to toggle, no re-download needed | Files remain on disk (minor — use uninstall to remove them) |
| Creates config backup before changes | Can restore if something goes wrong | None |
| SOUL and working-style sections are stripped on off | Clean reversal of the prompt-level changes | The strip is deterministic (not from backup) — if you had custom edits in the reliability section, they're lost |

## Recommendation

Use `off` for temporary disabling. Use `uninstall.sh` for permanent removal. Use `status` to check what's active.

## Plain English

This is a light switch for the reliability stack. Off: the gate stops running, the truth MCP disconnects, the coding instructions are removed from config. On: everything comes back. Your files aren't deleted — just deactivated. Use this when you want to temporarily test something without the gate, or when you're upgrading Hermes and want a clean slate.

## Commands

```bash
# Check current state
./scripts/reliability-toggle.sh status --profile YOUR_PROFILE

# Turn on (no gateway restart by default)
./scripts/reliability-toggle.sh on --profile YOUR_PROFILE --no-restart

# Turn on + restart gateway (requires human approval)
./scripts/reliability-toggle.sh on --profile YOUR_PROFILE --restart

# Turn off (no gateway restart by default)
./scripts/reliability-toggle.sh off --profile YOUR_PROFILE --no-restart

# Turn off + restart gateway
./scripts/reliability-toggle.sh off --profile YOUR_PROFILE --restart
```

## Gateway restart

The toggle defaults to `--no-restart`. Pass `--restart` only with human approval. Gateway restart is needed for the config changes to take effect if you're running a gateway — but if you're in the CLI, just start a new session.

## Multiple profiles

The toggle operates on one profile at a time. To toggle all profiles:

```bash
# Toggle off all profiles
for p in $(./scripts/lib.sh && source scripts/lib.sh && discover_profiles); do
  ./scripts/reliability-toggle.sh off --profile "$p" --no-restart
done

# Or use a comma-separated list
for p in agent1 agent2 agent3; do
  ./scripts/reliability-toggle.sh off --profile "$p" --no-restart
done
```

The `--all-profiles` flag is available on `install.sh` and `uninstall.sh` but not on `reliability-toggle.sh` — toggling is a quick on/off that's meant to be targeted. If you need to toggle all profiles, the loop above works.
