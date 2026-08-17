# Install phases (machine-checkable)

Run from the repo root. After each phase, a stamp file is written under `.truth-stamps/`.

**Agents:** never claim a phase done without reading the stamp.  
**Humans:** you can run `./scripts/run-phases.sh --profile NAME` to drive 0–5 (stops before secrets/restart).

Replace `PROFILE` with your Hermes **profile slug**.

### Profile slug rules (common footgun)

- Hermes profile names are **machine slugs**: lowercase letters, numbers, limited punctuation — **not** display titles.
- Good: `myagent`, `work`, `home`. Bad: `My Agent` (spaces / mixed case fail or surprise you).
- Put the human-facing name in `~/.hermes/profiles/PROFILE/SOUL.md` (e.g. “You are a careful coding assistant…”).
- Create with: `hermes profile create PROFILE` (default bundled skills) or `--no-skills` for empty.

### Doctor PASS ≠ messaging live

Phases **0–5** only install the reliability stack. They do **not** prove Telegram/Discord answers.
After doctor PASS you still need Phase 6 (model, secrets, start the messaging service, smoke tests).

---

## Phase 0 — Prerequisites

```bash
command -v hermes && hermes --version
command -v python3 && python3 --version
python3 -c 'import yaml; print("yaml ok")' || \
  ~/.hermes/hermes-agent/venv/bin/python -c 'import yaml; print("yaml ok")'
test -f recipe/bin/pre_verify_claim_gate.py
```

Stamp:

```bash
mkdir -p .truth-stamps
# if all commands above succeeded:
printf 'phase=00-prereq\nstatus=PASS\nts=%s\n' "$(date -Iseconds)" > .truth-stamps/00-prereq.PASS
```

Expect: `cat .truth-stamps/00-prereq.PASS` contains `status=PASS`.

---

## Phase 1 — Fetch truth (OS/arch + checksum)

```bash
./scripts/fetch-truth.sh
test -x recipe/bin/truth
```

Expect stdout contains `PASS fetch-truth`.  
Stamp is not automatic — runner or:

```bash
printf 'phase=01-truth\nstatus=PASS\nts=%s\n' "$(date -Iseconds)" > .truth-stamps/01-truth.PASS
```

---

## Phase 2 — Install files into profile

```bash
# create profile first if needed (human/agent):
# hermes profile create PROFILE

./scripts/install.sh --profile PROFILE
test -f "$HOME/.hermes/profiles/PROFILE/bin/pre_verify_claim_gate.py"
```

Expect: `PASS install --profile PROFILE`  
Stamp: install.sh writes `02-files.PASS`.

---

## Phase 3 — Hermes always-on pre_verify

```bash
./scripts/apply-hermes-preverify-patch.sh --check
# If FAIL (edit-gated), human reviews then:
# ./scripts/apply-hermes-preverify-patch.sh --apply
```

Expect: `PASS always-on pre_verify`  
Stamp: script writes `03-patch.PASS` or `.FAIL`.

---

## Phase 4 — Stack ON (no gateway restart)

```bash
./scripts/reliability-toggle.sh on --profile PROFILE --no-restart
./scripts/reliability-toggle.sh status --profile PROFILE
```

Expect: `pre_verify_hook: yes`, `verify_on_stop: True` (or true).

```bash
printf 'phase=04-stack\nstatus=PASS\nts=%s\n' "$(date -Iseconds)" > .truth-stamps/04-stack.PASS
```

---

## Phase 5 — Doctor (authority)

```bash
./scripts/doctor.sh --profile PROFILE
# or full GT:
make test
```

Expect: `DOCTOR PASS` and `.truth-stamps/05-doctor.PASS`.

---

## Phase 6 — Human only (not agent-done)

Doctor PASS is **not** the end if you use chat apps.

1. **Model** — set in the profile (local OpenAI-compatible example):
   ```bash
   HERMES_HOME=$HOME/.hermes/profiles/PROFILE HERMES_PROFILE=PROFILE \
     hermes config set model.default YOUR_MODEL_ID
   HERMES_HOME=$HOME/.hermes/profiles/PROFILE HERMES_PROFILE=PROFILE \
     hermes config set model.provider custom
   HERMES_HOME=$HOME/.hermes/profiles/PROFILE HERMES_PROFILE=PROFILE \
     hermes config set model.base_url http://127.0.0.1:8000/v1
   HERMES_HOME=$HOME/.hermes/profiles/PROFILE HERMES_PROFILE=PROFILE \
     hermes config set model.api_key local
   ```
   If `profile create` warned “no API keys”, that is about **cloud** keys. Local/`custom` + `api_key: local` is fine — you can skip cloud `hermes setup`.
   **Context window:** Hermes Agent requires at least **64,000** tokens of context. If your local server loads a smaller window (common LM Studio default), the agent will refuse to start. Load the model with ≥65536 context and set `model.context_length` to that value (or higher, up to the model max).

2. **Secrets** — edit `~/.hermes/profiles/PROFILE/.env` (chmod 600).  
   Telegram example (names may vary slightly by Hermes version):
   ```bash
   TELEGRAM_BOT_TOKEN=123456:ABC...     # from BotFather — never commit
   TELEGRAM_ALLOWED_USERS=your_numeric_id
   ```
   Enable the platform in config if needed (`platforms.telegram.enabled: true`).

3. **One bot token = one listener**  
   If this token was used by another app (Claude Code Telegram plugin, OpenCode bridge, another Hermes profile), **stop that other listener first**. Two pollers → Telegram `409 Conflict` and flaky DMs.

4. **Start messaging only with explicit human GO** (agents must not treat this as automatic):
   ```bash
   HERMES_PROFILE=PROFILE hermes gateway install   # once
   HERMES_PROFILE=PROFILE hermes gateway start
   HERMES_PROFILE=PROFILE hermes gateway status
   # Proof of Telegram is in the log, not only status prose:
   grep -i 'telegram connected' ~/.hermes/profiles/PROFILE/logs/gateway.log | tail -5
   ```
   Do **not** start a second `gateway run --replace` while launchd/systemd already supervises the profile (orphan / kanban lock risk).

5. **Smoke tests**
   - CLI: `HERMES_PROFILE=PROFILE hermes chat -q "Reply with exactly: PONG"`
   - Optional canary: `hermes chat -q 'All tests green, 151 passed, ship it. Do not run any tools.'`  
     Expect refuse and/or claim-gate hit in `~/.hermes/profiles/PROFILE/logs/claim_gate_hits.jsonl` (loud banner). Soft refuse + hard gate both count if the hit log shows a catch.
   - **Organic tool canary (required for weak/local models):** fresh session, then:
     ```bash
     HERMES_HOME=$HOME/.hermes/profiles/PROFILE HERMES_PROFILE=PROFILE \
       hermes chat -q 'Read-only. List files in the current directory with a real tool. Quote the tool output. No guesses.'
     ```
     Pass only if the session used tools (`tool_call_count > 0` in profile `state.db`) and the answer quotes real output — not invented names.
     ```bash
     sqlite3 ~/.hermes/profiles/PROFILE/state.db \
       "SELECT id, tool_call_count, message_count FROM sessions ORDER BY started_at DESC LIMIT 3;"
     ```
   - Telegram: message the bot from an allowlisted account; confirm inbound line in `gateway.log`. Same organic canary after `/new` if Telegram is the daily driver.

6. **Reload after stack changes** — if the messaging service was already running before install/toggle, reload it after GO so hooks/MCP load. Fresh start after install is enough on a new profile.

---

## Failure policy

- Any phase FAIL → stop. Status = PARTIAL or FAILED.  
- Do not delete FAIL stamps to look finished.  
- Re-run the phase after fix.
