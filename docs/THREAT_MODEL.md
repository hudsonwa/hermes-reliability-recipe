# Threat model & what this is not

## What we protect against

- Weak/fast coding agents **claiming** green tests, written files, or ship-ready work **without** filesystem/tool evidence
- Wrong-directory “tests passed” theater
- Invented byte/line counts next to paths

## What we do **not** protect against

- Malicious user prompts that intentionally destroy data
- Unsandboxed shell with `approvals.mode: off` (lab YOLO)
- Supply-chain compromise of downloaded `truth` binaries (we checksum official releases; still review)
- Model still being wrong in ways that avoid success-language (gate is success-claim oriented)
- Multi-agent orchestration correctness (see long-loop docs: OUT contracts are separate)
- **Skipping tools** and answering host/fleet/git questions from memory or guesses (soft prompts + `tool_use_enforcement` help; they are not a hard lock)
- **Tool cosplay** (“let me run bash…”) with zero real tool calls
- **Every wrong chat answer** — this is not a general truth oracle

## Trust boundaries

| Actor | Trust |
|-------|--------|
| Claim gate process | Trusted local code; reads final_response + disk |
| truth MCP | Local binary; no cloud |
| Installer agent (weak model) | **Untrusted for DONE** — doctor stamps only |
| Human | Required for secrets + gateway restart + YOLO |

## Safe defaults

- No auto gateway restart
- No approvals.mode=off unless `--lab-yolo` **and** `CONFIRM_LAB_YOLO=I_UNDERSTAND`
- Profile names must be Hermes slugs (no `../` path traversal)
- `truth` downloads verified against **in-repo pinned** SHA256 files
- No personal session history in this repo
- No vendored opaque binaries in git
- First public GitHub snapshot must be history-free (see `docs/GITHUB_PUBLISH.md`)

## Soft layers (not the gate)

| Layer | Role |
|-------|------|
| `tool_use_enforcement: true` | Hermes soft text: call tools, don’t only describe them |
| SOUL / working-style host-facts bullets | Nudge live-machine questions toward tools |
| Organic canary (Phase 6) | Proves a fresh session actually used tools |

The **hard** control for coding lies remains the claim gate. Soft layers and canaries cover the rest.
