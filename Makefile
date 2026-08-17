# hermes-reliability-recipe — ground-truth entrypoints
.PHONY: test test-quick test-gate scrub doctor help fetch-truth

# Prefer python3, fall back to versioned interpreters (uv-managed installs often only expose 3.11)
PYTHON ?= $(shell command -v python3 2>/dev/null || command -v python3.11 2>/dev/null || command -v python3.12 2>/dev/null || command -v python 2>/dev/null || echo python3)

help:
	@echo "make test        - full ground-truth suite"
	@echo "make test-quick  - gate units + artifacts + scrub (CI default)"
	@echo "make test-gate   - claim gate unit tests only"
	@echo "make scrub       - forbid private host/PII patterns"
	@echo "make fetch-truth - download truth for this OS/arch"
	@echo "make doctor PROFILE=name"

test:
	bash scripts/gt_suite.sh

test-gate:
	$(PYTHON) recipe/bin/test_claim_gate.py

test-quick:
	$(PYTHON) recipe/bin/test_claim_gate.py
	test -f recipe/templates/working-style-instruction.md
	test -f recipe/bin/pre_verify_claim_gate.py
	test -f scripts/doctor.sh
	test -f AGENTS.md
	test -f INSTALL_PHASES.md
	test -f recipe/checksums/truth-v0.3.15.sha256
	test -f SECURITY.md
	test ! -f scripts/scrub-needles.local || git check-ignore -q scripts/scrub-needles.local
	grep -qi 'do not finish' recipe/templates/working-style-instruction.md
	grep -q 'ensure_working_style_soft_block' scripts/lib.sh
	grep -q 'ensure_working_style_soft_block' scripts/reliability-toggle.sh
	grep -q 'profile_working_style_soft_missing\|profile working-style soft block' scripts/doctor.sh
	bash scripts/check-scrub.sh
	@echo "test-quick OK"

scrub:
	bash scripts/check-scrub.sh

fetch-truth:
	bash scripts/fetch-truth.sh

doctor:
	@test -n "$(PROFILE)" || (echo "USAGE: make doctor PROFILE=name" >&2; exit 2)
	bash scripts/doctor.sh --profile "$(PROFILE)"
