# Changelog

All notable changes to the reliability recipe. Dates are UTC.

## v0.2.2 — 2026-09-08

### Fixed
- **Doctor profile gate hash (#3):** sha256 of profile
  `bin/pre_verify_claim_gate.py` vs recipe. Mismatch = `profile_gate_stale`.
  Skip with `HRR_DOCTOR_ALLOW_STALE_BINS=1` (intentionally diverged only).
- **Doctor profile tests-file hash (#4):** missing or mismatched
  `test_claim_gate.py` = `profile_gate_tests_stale`. Same skip env.
- **truth_run_wrap (#5):** missing truth exits 127 and does not run the
  wrapped command (no silent exec, no passthrough env).
- **Pytest interpreter (#6):** skills/toggle wrap a python that can
  `import pytest` (prefer `$HERMES_VENV/python`). Recipe suite is
  `python recipe/bin/test_claim_gate.py`. Doctor fails
  `pytest_python_cannot_import` only when instructions name
  `python3 -m pytest` and that python cannot import pytest.
- **Vacuous unittest (#7):** `load_tests` fails loud; keep `__main__`
  runner. Do not unittest this file.
- **Recopy hint (#8):** on stale bins, doctor prints
  `./scripts/reliability-toggle.sh on --profile NAME --no-restart`.
- **Quoted stamp PASS (#9):** strip fenced/`>`-quoted text before claim
  regexes. `SUCCESS_PAT` / `TESTS_PASS_CLAIM` unchanged. First-person
  “All tests passed. Ship it.” still blocked without a receipt.

### Tests
- GT12–GT17 on `scripts/gt_suite.sh`. Gate unit list is 14 cases.

## v0.2.1 — 2026-09-07

### Fixed
- **Doctor hermes prereq** no longer fails a PATH-only miss: under
  non-interactive shells (SSH/cron) doctor accepts the venv binary at the known
  install locations and prints how to add it to PATH. (#1)
- **Doctor working-style check** now names which piece is missing instead of
  one conflated soft-missing code: `working_style_missing`,
  `working_style_marker_missing` (a clone can ship the LIE/truth_run lines
  without the marker), or `working_style_lie_truth_run_missing`. (#2)
- **Docs**: non-interactive-shell guidance added to `docs/DOCTOR.md`; the
  working-style file is now listed as required in the Phase 2 checklist.

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
