# Reliability stack (hermes-reliability-recipe)

Unofficial recipe for Hermes Agent. Not affiliated with Nous Research.

## Layers

1. **Claim gate** (`recipe/bin/pre_verify_claim_gate.py`) via Hermes `pre_verify` — cannot skip
2. **truth** CLI + MCP (`verify_turn`) + `truth_run_wrap.sh` — receipts
3. Soft: coding_instructions + SOUL lines + skills
4. **Doctor / GT** — only authority for “install done”

## Toggle

```bash
./scripts/reliability-toggle.sh on|off|status --profile YOUR_PROFILE
```

Gateway restart is **off by default**. Pass `--restart` only with human approval.

**Soft working-style is symmetric:**

| Action | Soft LIE / `truth_run` block in profile `working-style-instruction.md` |
|--------|------------------------------------------------------------------------|
| `toggle on` / install | Ensures block present (append under marker, or install template if missing) |
| `toggle off` | Strips the marked section only (keeps your personal prose) |
| `toggle on` again | **Restores** the soft block (does not leave you soft-thin) |

Doctor and self-heal fail closed if the stack is enabled but the profile soft block is missing.

## Lab YOLO (optional, dangerous)

```bash
CONFIRM_LAB_YOLO=I_UNDERSTAND LAB_YOLO=1 ./scripts/install.sh --profile YOUR_PROFILE --lab-yolo
```

Sets `approvals.mode: off`. Do **not** use on untrusted machines or shared hosts.

## Always-on pre_verify

Some Hermes builds only run `pre_verify` after file edits. Pure hallucination then skips the gate.

```bash
./scripts/apply-hermes-preverify-patch.sh --check
./scripts/apply-hermes-preverify-patch.sh --apply   # modifies local Hermes install
```

Re-check after every Hermes upgrade. Prefer an upstream config flag if/when available.

## Self-heal

```bash
./scripts/reliability-selfheal.sh --profile YOUR_PROFILE --check-only
SELFHEAL_VERBOSE=1 ./scripts/reliability-selfheal.sh --profile YOUR_PROFILE
```

Profile path comes from `--profile` only. Ambient `HERMES_HOME` is ignored for targeting.

## Design notes

- Gate must not require the model to call a tool.
- truth needs receipts (`truth run`) to Contradict false “tests pass”.
- Do not use heavy STATUS/EVIDENCE theater prompts (weak models fill them with fiction).
- This is **not** a sandbox. Claim gate ≠ OS isolation.
