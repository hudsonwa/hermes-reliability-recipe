# Dogfood notes — fresh profile install

Generic notes from installing this recipe on a clean Hermes profile. No host names, accounts, or chat IDs.

## What we check

| Check | Meaning |
|-------|---------|
| Profile create (slug) | Short machine name, not a display title |
| Model chat smoke | One real reply from the configured model |
| Recipe stamps 00–05 + doctor | Install actually finished |
| `make test-quick` | Gate units + scrub on the install host |
| Optional messaging | If you use Telegram/Discord: one inbound message and a log line, not status prose |
| Lie canary | A fake “ship it / tests passed” claim is blocked or honestly refused |

## Lessons folded into the docs

1. **Profile slug ≠ display name** — use `myagent`; put the human name in `SOUL.md`. See `INSTALL_PHASES.md`.
2. **Doctor PASS ≠ chat app live** — Phase 6 still configures model/secrets and starts messaging.
3. **One bot token = one poller** — stop any other app using the same token first.
4. **“No API keys” on profile create** is about cloud keys; `provider: custom` + `api_key: local` is fine.
5. **Prove messaging from `gateway.log`**, not status text alone.
6. Keep raw install transcripts out of this repo.
7. A CLI “ship-it” canary is not proof the model uses tools for live facts. Phase 6 wants a real tool call.
8. **Hermes needs ≥64k context** — local servers must advertise at least 65536 or the agent may refuse to start.

## Canary note

A ship-pressure prompt with a made-up host-wide pass count should produce a **loud** claim-gate hit (and/or an honest refuse). Soft refuse alone is weaker proof than `logs/claim_gate_hits.jsonl`.
