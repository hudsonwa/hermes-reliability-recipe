# Fetch truth

## What

Downloads the `truth` binary (and `truth-mcp` when present) for your OS/CPU from the official GitHub releases, verifies SHA256 **against checksums pinned in this repo** (`recipe/checksums/truth-<version>.sha256`), and checks the binary **actually runs** on this machine (catches GLIBC mismatches). A checksum file shipped next to the same GitHub release is **not** trusted by itself.

## Who

Human or agent. One-time before install; again after `TRUTH_VERSION` changes or on a new machine.

## Where

Writes `recipe/bin/truth` and `recipe/bin/truth-mcp` in the repo. `install.sh` copies them into `~/.hermes/profiles/<NAME>/bin/`.

## When

- Before install (install can call fetch, or you run it yourself)
- New machine / new arch
- After bumping `TRUTH_VERSION`

## Why

Truth is **layer 2** (receipts): records real command output so the agent cannot invent “tests passed” without a receipt.  
The claim gate is **layer 1** and does **not** require truth.

**Important:** Needing a modern Linux glibc for prebuilt truth is a **truth binary** constraint, not a Hermes Agent requirement. Hermes can run elsewhere; this download only cares where *truth* runs.

## Tradeoffs

| Tradeoff | Pro | Con |
|----------|-----|-----|
| Downloaded per-arch | Small git repo, no huge binaries committed | Needs network once (~5–20MB) |
| SHA256 verify | Tamper check | Upstream compromise still a residual supply-chain risk |
| Run-after-download check | Clear fail on old GLIBC instead of silent “file exists” | Older distros must use `--skip-truth` |
| Optional layer | Claim gate still useful without truth | Weaker than full stack |

## Recommendation

- Prefer full stack: run `./scripts/fetch-truth.sh` on macOS or Linux with GLIBC 2.32+ (Ubuntu 22.04+, Debian 12+).
- If fetch fails with GLIBC errors: keep going with claim gate only:
  ```bash
  ./scripts/install.sh --profile YOUR_PROFILE --skip-truth
  ./scripts/doctor.sh --profile YOUR_PROFILE --allow-no-truth
  ```
- Offline: copy working `truth` + `truth-mcp` from a matching OS/arch machine into `recipe/bin/`.

## Plain English

Truth is a receipt printer for shell commands. We download the right build for your computer, check the checksum, then try to run it. If your Linux is too old for the prebuilt file, we tell you clearly — you can still use the lie detector (claim gate) without truth.

## Commands

```bash
# Download for this machine
./scripts/fetch-truth.sh

# Pin a version
./scripts/fetch-truth.sh --version v0.3.15
# or: TRUTH_VERSION=v0.3.15 ./scripts/fetch-truth.sh

# Custom destination
./scripts/fetch-truth.sh --dest /path/to/dir
```

## Supported platforms

| OS | Architecture | Prebuilt truth |
|----|--------------|----------------|
| macOS | arm64 / x86_64 | Yes |
| Linux | x86_64 / aarch64 | Yes, if **GLIBC ≥ 2.32** |
| Linux older (e.g. Debian 11, GLIBC 2.31) | x86_64 | Download may succeed; **run check fails** — use `--skip-truth` or build from source |
| Windows native | any | No — use WSL2 (Ubuntu 22.04+ recommended for truth) |

## Dogfood note (clean Windows WSL2)

On Debian 11 (GLIBC 2.31), fetch downloaded the binary and checksum passed, then run failed with `GLIBC_2.32 not found`. The script now deletes the unusable binaries and prints workarounds instead of claiming PASS.

## Build from source (advanced)

If prebuilts will not run: https://github.com/blasrodri/truth — build on that machine, place binaries in `recipe/bin/`, then install.
