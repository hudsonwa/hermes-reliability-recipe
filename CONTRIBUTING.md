# Contributing

This is an unofficial community recipe for Hermes Agent. Best-effort maintenance.

PRs welcome, especially for:
- New Hermes version compatibility (patch patterns, config keys)
- New claim gate patterns (foreign suites, lie phrasings)
- Documentation improvements
- Cross-platform testing (Linux, macOS, x86_64, aarch64)

## Before submitting

- Run `make test-quick` — must pass
- Run `make scrub` — must pass (no token-shaped secrets; maintainer needles stay in gitignored `scripts/scrub-needles.local`)
- Keep docs in plain English with the What/Who/Where/When/Why/Tradeoffs/Recommendation format
- Do not commit `scripts/scrub-needles.local`, `.env`, session dumps, or `recipe/bin/truth`

## Documentation standard

Every documented action must answer all of:
- **What** it does (what files change, what gets added, what gets removed)
- **Who** should run it (human? agent? both?)
- **Where** it operates (which profile, which file, which directory — exact paths)
- **When** you should run it (first install? after upgrade? on failure? optional?)
- **Why** it exists (what problem it solves, what happens if you skip it)
- **Tradeoffs** (what you gain, what you risk, what the alternatives are)
- **Recommendation** (should most users do this? is it optional? when to skip?)
- **Plain English** (no jargon without a one-line definition; no acronyms without expansion)

If any of those are missing for a step, the doc is not done.

## What this is NOT

- NOT an official Nous Research product
- NOT a security sandbox
- Do not direct support requests to Nous Research for this recipe
