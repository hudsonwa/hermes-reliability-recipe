# Security policy

This recipe is **not a sandbox** and **not an OS security boundary**. It stops weak agents from *claiming* work they did not do. It does not stop a malicious prompt, a compromised model, or `approvals.mode: off` from running dangerous commands.

## What we hardened for a public clone

| Area | Control |
|------|---------|
| Secrets in git | `make scrub` fails on private-key / token-shaped strings. Extra local needles (if any) stay in gitignored `scripts/scrub-needles.local`. |
| Profile path traversal | `--profile ../.ssh` is rejected. Slugs only: `A-Za-z0-9._-` |
| Lab YOLO | `--lab-yolo` also requires `CONFIRM_LAB_YOLO=I_UNDERSTAND` |
| `truth` download | SHA256 **pinned in this repo** (`recipe/checksums/`). Same-release checksum files are not trusted alone. Only expected tar members are extracted. |
| Process reaper | Default is **dry-run**. `--apply` can kill stale `hermes chat` workers. Never run as root. |
| Hermes patch | Optional, **global**, backed up. Review `docs/HERMES-PATCH.md` before `--apply`. |
| Installer | Does not overwrite `.env`, does not restart a gateway unless you pass `--restart`. |

## Residual risk (be honest)

- **Pinned checksums are TOFU at pin time.** If GitHub `blasrodri/truth` is compromised *and* we bump the pin without review, you still lose. Review pin diffs.
- **The claim gate is not an exploit mitigator.** A hostile agent can still run tools the host allows.
- **`--all-profiles` writes every Hermes profile on the machine.** Do not run that on a shared box unless you mean it.

## Reporting

Open a GitHub issue on this repo (no exploit PoC against live hosts). Do not send tokens or private identifiers.
