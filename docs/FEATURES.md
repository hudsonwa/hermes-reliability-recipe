# Feature list — hermes reliability recipe

Every feature below ships in this repo and is verified by the tests in
`recipe/bin/` and `scripts/gt_suite.sh`. Design rule: **hard controls do the
stopping, soft rules do the persuading, evidence files do the remembering.**

## 1. Always-on claim gate (`pre_verify`)

A per-profile deterministic Python check (no LLM, no API calls) inspects every final agent answer for success claims
("done", "all tests pass", "verified") that lack a named check or receipt, and
forces an in-turn correction before the message ships. A one-line core patch
removes the stock edit-gating so the gate fires on **every** turn — not only
turns where files were edited. Chat-only lies (no edits) are exactly the ones
that used to slip through.

- Judge: `recipe/bin/pre_verify_claim_gate.py` (registered as a `pre_verify`
  hook in the profile config)
- Patch: `patches/hermes/` via `scripts/apply-hermes-preverify-patch.sh`
- Evidence: `logs/claim_gate_hits.jsonl` (session-attributed)
- Tests: `recipe/bin/test_claim_gate.py` (11 cases, incl. the finish-line rule)

## 2. Mid-loop verification nudges (`verify_on_stop`)

While the agent works, Hermes inserts "verify before you claim" nudges
mid-turn (bounded by `max_verify_nudges`). Set `agent.verify_on_stop: true`.
Config changes apply on the next turn without a restart (the Python-side hook
patch does need a process restart — see `docs/HERMES-PATCH.md`).

## 3. Finish-line rule + seam ledger

"Verified/done" claims with no named check and no coverage clause are nudged
(and hard-failed to PARTIAL at max attempts). A machine seam ledger records
Verified/Open/Next/LastError so a retry of the same fingerprint cannot re-lie.
Ledger: `recipe/bin/seam_ledger.py`; tests: `test_seam_ledger.py` (5 cases).

## 4. Self-heal watchdog (6-hourly)

A cron runs `scripts/reliability-selfheal.sh` per profile. It checks the
config stack (`verify_on_stop`, hooks, gate binary, soft-rule markers) **and —
since the drift fix — whether the always-on patch is still present in the live
Hermes tree** (flag: `pre_verify_patch_drift`). Known wipes are repaired
automatically (patch re-applied from the canonical patcher). Silent when
healthy; loud when it fixes or fails something.

## 5. Dead-man's switch (who watches the watchers)

Every self-heal run stamps `state/reliability-heartbeat.txt`. A daily
`deadman-check.sh` fails loudly (nonzero exit + message) if any heartbeat is
older than 25 hours — i.e. a watchdog that died silently gets caught within a
day instead of a month. Deploy one per host covering that host's profiles.

## 6. Config-parity checker

`scripts/config-parity-check.sh` compares the reliability-critical settings
across profiles on a machine (verify_on_stop, enforcement mode, hook presence,
gate binary on disk) and fails on drift or missing pieces. Catches the
"config clobber" failure class mechanically instead of by manual audit.

## 7. Update-proof deployment pattern (operator-side)

When this stack is deployed on a machine, the operator is advised to pin the
applied Hermes patch: a dedicated branch + tag holding the patch, the exported
`.patch` file with a SHA256SUMS manifest, and an anchor probe that re-checks
the patched call sites after every Hermes update. The stack then largely
self-heals: self-heal detects patch drift and re-applies the patch
(GT10 in `scripts/gt_suite.sh`), and a full post-update doctor run verifies
the rest. The pin/doctor scripts live in the operator's deployment kit, not
in this repo — this repo ships the building blocks (patch applier, doctor,
self-heal, GT suite).

## 8. Update doctor (post-update + weekly)

`update-doctor.sh` is one command that verifies the full stack survived an
update: pin branch/tag, patch-in-tree, anchors, GT suite, recipe doctor, truth
binaries boot, gateway health, a cold-boot chat that must ground the hard
rule, and soft-file integrity (required markers FAIL on wipe; SHA256 baseline
WARN on silent drift — WARN-only because marker-appends cannot be reliably
distinguished from legitimate edits).

## 9. GT suite (ground-truth tests)

`scripts/gt_suite.sh` runs hermetic end-to-end checks (fake HERMES roots, temp
logs) including GT7 (live always-on form), GT10 (drift detection + auto
re-apply), and log-pollution guards that keep test traffic out of the live
hits log. `make test` is the done-bar for any stack claim.

## 10. Doctor + toggle

`scripts/doctor.sh --profile <p>`: full per-profile stack check with
`.truth-stamps/` receipts. `scripts/reliability-toggle.sh`: safe on/off with
timestamped config + soft-file backups (the toggle is the repair path when
parity check flags a clobbered profile).
