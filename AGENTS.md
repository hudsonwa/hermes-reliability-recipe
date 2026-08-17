# AGENTS.md — rules for agents installing or modifying this recipe

You may be a **weak / low-context** model. These rules are fail-closed.

## Hard rules

1. **Never claim DONE / installed / green / ship** unless the matching `.truth-stamps/*.PASS` files exist and you have **read them back** this turn.
2. **Follow `INSTALL_PHASES.md` in order.** Do not skip phases. On failure: stop, print the failing command output, status PARTIAL/FAILED.
3. **Human-only steps** (you must stop and ask):
   - Filling API tokens / bot tokens in `.env`
   - Enabling `--lab-yolo` / `approvals.mode: off`
   - Restarting any gateway (`--restart` or `hermes gateway run`)
   - Pushing git remotes or making the repo public
4. **Do not invent** file paths, test counts, checksums, or “already installed” state. Run the command.
5. **Do not** copy personal memory, session backups, or messaging identifiers into this tree.
6. **Do not** vendor opaque binaries into git; use `scripts/fetch-truth.sh`.
7. Prefer `make test-quick` / `./scripts/doctor.sh` over prose verification.
8. If claim gate or doctor fails, obey loudly — fix or admit FAILED.

## Allowed autonomous work

- Read docs, run fetch-truth, install.sh (without lab yolo), apply-patch --check, doctor, unit tests, scrub.
- Edit recipe code with tests green after.

## Done criteria (install task)

All of:

- `.truth-stamps/00-prereq.PASS`
- `.truth-stamps/01-truth.PASS`
- `.truth-stamps/02-files.PASS`
- `.truth-stamps/03-patch.PASS` (or documented skip with human OK)
- `.truth-stamps/04-stack.PASS`
- `.truth-stamps/05-doctor.PASS`

and `cat` of each file shows `status=PASS`.
