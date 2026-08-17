# Uninstall

## What it does

Removes all files this recipe installed, restores all files this recipe modified (from backups it created), and undoes the Hermes patch (restores `conversation_loop.py` from backup).

Nothing on your machine is damaged. It only touches files this recipe created or modified.

## Who should run this

The human. Not an agent — uninstall touches your Hermes installation.

## Where it operates

- `~/.hermes/profiles/<NAME>/` — removes installed files, skills, state files; restores working-style and SOUL from backups
- `~/.hermes/hermes-agent/agent/conversation_loop.py` — undoes the patch (only if you approve — it asks first because this is global)

## When to run it

Any time after install, when you want to remove the reliability stack.

## Why it exists

Clean reversal. No leftover files, no leftover config entries, no leftover hooks. Everything goes back to how it was before you installed.

## Tradeoffs

| Tradeoff | Pro | Con |
|----------|-----|-----|
| Complete reversal | Everything is removed and restored | If you want to re-enable later, you must re-run install |
| Asks before the global patch undo | You control whether all profiles are affected | The patch undo is global — but it asks first |
| `--dry-run` preview | See what would happen before committing | None |
| `--skip-patch` option | Keep always-on pre_verify for other profiles | Doctor will still show the patch as present (which is correct) |

## Recommendation

Use `--dry-run` first to preview. Use `--skip-patch` if you want to keep the always-on pre_verify behavior for other profiles but remove everything else.

## Plain English

This reverses the install. It takes out the files this recipe added, puts back the files this recipe changed (from the backups it made), and undoes the Hermes patch (but it asks you first because that part affects all your profiles). Nothing on your machine is damaged — it only touches files this recipe created or modified.

## Safety rules (hard-coded)

1. Never deletes `.env`, `config.yaml`, `SOUL.md`, or the profile directory itself
2. Never deletes files we didn't install — only the known install list
3. Never touches files outside the profile except the Hermes patch (which has its own `--unapply` with backup restore)
4. Always shows what will be removed and restored before doing anything
5. Requires explicit confirmation (yes/no) before executing — no auto-run
6. If a backup doesn't exist for a restore, skips that step, warns, and continues — never restores from nothing
7. If a file to remove doesn't exist, skips it silently — never errors on missing files
8. Logs every action to `~/.hermes/profiles/<NAME>/logs/uninstall.log`

## Commands

```bash
# Preview what would be removed (no changes made)
./scripts/uninstall.sh --profile YOUR_PROFILE --dry-run

# Full uninstall (asks for confirmation)
./scripts/uninstall.sh --profile YOUR_PROFILE

# Skip confirmation (for scripted use)
./scripts/uninstall.sh --profile YOUR_PROFILE --yes

# Remove everything EXCEPT the Hermes patch (keep always-on pre_verify)
./scripts/uninstall.sh --profile YOUR_PROFILE --skip-patch

# Help
./scripts/uninstall.sh --help
```

## Multiple profiles

To uninstall from multiple profiles at once:

```bash
# Uninstall from all profiles with config.yaml
./scripts/uninstall.sh --all-profiles --dry-run    # preview first
./scripts/uninstall.sh --all-profiles              # remove from all

# Uninstall from specific profiles (comma-separated)
./scripts/uninstall.sh --profile agent1,agent2,agent3
```

When uninstalling from multiple profiles:
- Each profile gets its own toggle-off, file removal, and SOUL/working-style strip
- The Hermes patch `--unapply` runs only ONCE (it's global, not per-profile)
- You get one confirmation prompt for all profiles, plus a second prompt for the patch
- A summary shows how many profiles succeeded and how many failed

## What gets removed

- `bin/pre_verify_claim_gate.py` — the claim gate script
- `bin/truth` — the truth binary
- `bin/truth-mcp` — the truth MCP server
- `bin/truth_run_wrap.sh` — the command wrapper
- `bin/test_claim_gate.py` — gate unit tests
- `skills/reliability/` — the reliability skill directory
- `state/reliability-stack.json` — stack state file
- `state/reliability-recipe-root.txt` — recipe root marker

## What gets restored

- `working-style-instruction.md` — the reliability section is stripped (original content preserved)
- `SOUL.md` — the reliability section is stripped (original content preserved)
- `config.yaml` — hooks, MCP server, coding_instructions, verify_on_stop are removed (toggle off makes a backup first)
- `conversation_loop.py` — restored from `.bak` backup (only if you approve; this is global)

## What does NOT get touched

- `.env` — never deleted or modified
- `config.yaml` — restored by toggle off from its own timestamped backup
- `SOUL.md` — only the reliability section is removed; rest preserved
- Profile directory itself — never deleted
- Any other files in `bin/`, `skills/`, `state/` that we didn't install
