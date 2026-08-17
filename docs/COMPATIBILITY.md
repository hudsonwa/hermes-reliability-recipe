# Compatibility

## Plain English first

**Hermes Agent does not require Ubuntu or Debian.** Hermes runs on macOS, Linux, Windows (native), and WSL. You pick the OS Hermes already runs on.

**This recipe** is a set of bash scripts + a small Python claim gate + optional prebuilt `truth` binaries. That is a *different* requirement set:

| Layer | What it is | Needs Ubuntu/Debian? |
|-------|------------|----------------------|
| Hermes Agent | The AI agent itself | **No** — use whatever Hermes supports |
| Claim gate (this recipe, layer 1) | Python script + config hooks | **No** — needs Python 3.10+ and bash (macOS, Linux, or WSL) |
| Truth receipts (this recipe, layer 2) | Prebuilt `truth` / `truth-mcp` binaries | **Indirectly** — needs a Linux/macOS with **GLIBC 2.32+** (Ubuntu 22.04+, Debian 12+, modern macOS). Not a Hermes requirement. |
| Windows | Running this recipe | Use **WSL2** so bash + Linux `truth` work. Native Windows is not the primary path for *this recipe*. |

We used Ubuntu/Debian on a Windows box only to **dogfood this recipe** in a clean Linux environment (WSL2). That was a test vehicle for the reliability stack — not a statement that Hermes needs those distros.

---

## What (component matrix)

| Component | Notes |
|-----------|--------|
| Hermes Agent | Tested against **0.20.x**. Re-run doctor after upgrades. Hermes install path is upstream docs — not this repo. |
| Python | 3.10+ with PyYAML (Hermes venv usually has it). Scripts resolve `python3`, `python3.11`, `python3.12`, Hermes venv python, or `python`. |
| OS for claim gate | macOS, Linux, WSL2 (x86_64 + aarch64). Bash required for install/toggle/uninstall scripts. |
| OS for truth layer | Same, **plus** GLIBC **2.32+** for prebuilt Linux binaries (or macOS release assets). |
| truth version | Default pin **v0.3.15** (override `TRUTH_VERSION`). |
| Older Linux (e.g. Debian 11 / GLIBC 2.31) | Claim gate: **yes**. Truth prebuilts: **no**. Use `--skip-truth` + doctor `--allow-no-truth`. |

## Who this page is for

Public users choosing a machine/OS, and anyone confused whether “Ubuntu required” means Hermes or this recipe.

## Where it applies

Anywhere you install Hermes *and* this recipe. Hermes lives under `~/.hermes/`; this recipe installs into a profile under `~/.hermes/profiles/<NAME>/` and optionally patches Hermes source once.

## When to re-check

After OS upgrades, Hermes upgrades, moving to a new machine, or switching WSL distros.

## Why Ubuntu 22.04+ shows up in the docs

Only because the **prebuilt `truth` binary** (optional layer 2) is built against a modern glibc. Ubuntu 22.04+ and Debian 12+ meet that bar. macOS uses separate release assets and does not use Linux GLIBC.

If you only want the claim gate, you do **not** need a new distro — install with `--skip-truth`.

## Tradeoffs

| Choice | Pro | Con |
|--------|-----|-----|
| Full stack (gate + truth) | Receipts for real command output; stronger fail-closed | Needs modern Linux/macOS; extra download |
| Claim gate only (`--skip-truth`) | Works on older GLIBC; still blocks “ship it / tests green” lies | No command-receipt MCP; weaker against faked run evidence |
| WSL2 on Windows | Same scripts as Linux; matches how most Windows Hermes users run agents | Extra Windows feature; pick a modern Ubuntu for full truth |
| Native Windows for this recipe | — | Bash scripts + Linux truth prebuilts are not the supported primary path |

## Recommendation

1. Install Hermes however Nous documents for your machine.
2. For **this recipe** on Windows: WSL2 + **Ubuntu 22.04 or 24.04** if you want truth; any recent WSL Linux if claim-gate-only is enough.
3. On macOS/Linux you already use for Hermes: run the recipe there — no need to install Ubuntu just for Hermes.

## WSL2 (Windows users of this recipe)

```powershell
wsl --install -d Ubuntu-22.04
```

Then inside WSL: install Hermes (upstream), create a profile, clone this repo, run install.

**Debian 11 (bullseye) dogfood note:** claim gate, patch, toggle, uninstall all worked; prebuilt `truth` failed with `GLIBC_2.32 not found`. Prefer Ubuntu 22.04+ for full stack.

### Headless / SSH install tips (from clean-machine dogfood)

- Install system deps **before** Hermes installer if you can: `git`, `curl`, `xz-utils` (Node extract), and optionally `ripgrep` / `ffmpeg` so the installer does not hang on `sudo` prompts.
- Hermes installer may open an **interactive setup wizard** — over SSH that hangs. Configure `.env` + `config.yaml` manually (OpenRouter key, model id) instead of waiting on the wizard.
- uv-managed Python may expose `python3.11` but not `python3`. This recipe’s scripts fall back automatically; you can also `ln -s $(which python3.11) ~/.local/bin/python3`.
- OpenRouter: some models return privacy/guardrail 404s depending on account settings. Try another model id if smoke chat fails.
- After `wsl --shutdown`, remount `/mnt/c` if your scripts read files from the Windows home directory.

## Hermes pre_verify patch

| State | Meaning |
|-------|---------|
| always-on | `if has_hook("pre_verify")` without requiring `_edited` |
| edit-gated | pure no-edit lies skip the gate — **doctor fails** |

Apply: `scripts/apply-hermes-preverify-patch.sh --apply`  
This patch is about Hermes source behaviour — **not** about Ubuntu vs Debian.

## What we do not claim

- Works on every Hermes commit forever
- Makes weak models smart
- Replaces OS sandboxing / approvals discipline
- Official Nous support
- That Hermes itself requires Ubuntu/Debian
- That native Windows (non-WSL) is fully tested for this recipe — use WSL2 for the recipe
