# Changelog

All notable changes to the reliability recipe. Dates are UTC.

## v0.2.0 — 2026-09-01

The hardening pass after a real production incident (three simultaneous
degradations of the stack, documented in `docs/WHY-2026-09-01.md`).

### Added
- **Finish-line rule** in the claim gate: "verified / done / task complete"
  claims without a named check + coverage clause are nudged, then
  hard-downgraded to PARTIAL at max attempts.
- **Self-heal drift detection + auto-repair**: the watchdog now checks the
  live Hermes tree for the always-on `pre_verify` form and re-applies the
  patch when an update wipes it (hermetic test GT10).
- **Dead-man's switch** (`scripts/deadman-check.sh`): self-heal runs stamp a
  heartbeat; a daily check fails loudly when a heartbeat goes stale. Catches
  a silently dead watchdog within a day.
- **Config-parity check** (`scripts/config-parity-check.sh`): compares
  reliability-critical settings across managed profiles; fails on drift or
  missing pieces (catches config clobbers mechanically).
- **Independent scenario scorer** (`recipe/bin/claim_auditor.py`): machine
  scores agent final text + sandbox state against scenario expectations;
  no LLM self-judgment.
- **Documentation**: `docs/FEATURES.md` (full feature list with tests),
  `docs/WHY-2026-09-01.md` (incident-driven rationale with A/B evidence).
- **CI**: GitHub Actions workflow (bash syntax, python compile, unit tests,
  scrub check, hermetic GT suite) + `requirements-dev.txt`.

### Fixed
- **Test/log isolation**: the GT suite no longer writes test rows into the
  live `claim_gate_hits.jsonl`; tests run against a temp log so organic
  catches stay countable.
- **Publication audit round** (fresh-eyes review findings, all fixed):
  seam-ledger files + GT10 shipped so docs match the tree; private-incident
  SHAs removed from docs; gate "planted stats" and foreign-suite markers are
  now generic with operator-injectable env knobs (`CLAIM_GATE_STATS_EXTRA`,
  `CLAIM_GATE_FOREIGN_EXTRA`); FEATURES no longer mislabels the
  deterministic gate as an "LLM judge"; PyYAML prerequisite documented
  (README + TROUBLESHOOTING); bash-3.2 array-subscript fix in uninstall;
  duplicate README doc sections merged; doc counts and timing claims
  corrected; toggle rejects flag-first argument order with a helpful
  message; `scripts/sync-from-kernel.sh` added for deterministic kernel→export
  propagation (with kernel-freshness check).

## v0.1.0 — 2026-08-31

Initial public kernel: always-on claim gate (one-line Hermes patch + judge
script), self-heal watchdog, toggle, doctor, GT suite, truth integration,
install phases, scrub tooling.
