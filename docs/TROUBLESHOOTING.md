# Troubleshooting

## What

Fixes for problems people hit installing or running this recipe — especially clean machines and WSL2. Drawn from a full dogfood on Windows WSL2 + Hermes 0.20.x.

## Who

Anyone installing the recipe (human). Agents may follow the same steps but must not claim success without `doctor` PASS.

## Where

Your machine’s Hermes home (`~/.hermes/`), this repo, and (Windows) WSL2.

## When

Install fails, doctor FAIL, truth download fails, toggle/uninstall misbehaves, or “it worked on my Mac but not here.”

## Why

Public users should not need private chat history. Capture the foot-guns once.

## Plain English

If something breaks, match the symptom below. Most “Ubuntu” talk is about the optional truth tool, not Hermes.

---

## Symptom → fix

### “Does Hermes need Ubuntu?”

**No.** Install Hermes per official docs on whatever OS you use.  
Ubuntu/Debian appear in *this* repo only for:

1. WSL2 as a comfortable place to run **bash scripts**, and  
2. **GLIBC 2.32+** for optional prebuilt `truth` binaries.

Claim gate alone does not require a new distro.

### `python3: command not found` but Hermes works

uv/Hermes often installs `python3.11` without a `python3` name.

**Fix:** Update to latest recipe scripts (they call `resolve_python`). Or:

```bash
mkdir -p ~/.local/bin
ln -sf "$(command -v python3.11)" ~/.local/bin/python3
export PATH="$HOME/.local/bin:$PATH"
```

### `truth` download OK but `GLIBC_2.32 not found`

Your Linux is older than the prebuilt binary (e.g. Debian 11 / GLIBC 2.31).

**Fix (full stack):** use Ubuntu 22.04+ / Debian 12+ / modern macOS.  
**Fix (claim gate only):**

```bash
./scripts/install.sh --profile YOUR_PROFILE --skip-truth
./scripts/doctor.sh --profile YOUR_PROFILE --allow-no-truth
```

### `FAIL: working-style soft block missing after ensure`

Template marker must be exactly:

`# Reliability stack (hermes-reliability-recipe)`

Use a current recipe checkout. Re-run install.

### Doctor FAIL: `pre_verify_still_edit_gated`

Stock Hermes only runs the gate after file edits. Apply the patch:

```bash
./scripts/apply-hermes-preverify-patch.sh --check
./scripts/apply-hermes-preverify-patch.sh --apply
# restart CLI session / gateway so the process reloads source
```

### Hermes installer hangs on “Choice [default 1]” over SSH

Interactive setup wizard. Ctrl+C, then write `.env` + `config.yaml` yourself (API key + model). Recipe install does not need the wizard.

### Hermes installer hangs on `sudo` for ripgrep/ffmpeg

Pre-install as root, or passwordless sudo for the install user:

```bash
sudo apt-get update && sudo apt-get install -y git curl xz-utils ripgrep ffmpeg
```

### OpenRouter `HTTP 404` privacy / guardrails

Account or model policy. Try another model id (dogfood: `meta-llama/llama-3.3-70b-instruct` worked when some others did not).

### Scrub FAIL on `._*` files after copying from a Mac

macOS AppleDouble sidecars. Latest `check-scrub.sh` ignores `._*`. When tarring from macOS:

```bash
export COPYFILE_DISABLE=1
tar --exclude='._*' ...
```

### Toggle off removed working-style reliability text and it did not come back

Current `toggle on` re-appends the soft block via `ensure_working_style_soft_block`. Upgrade scripts and run:

```bash
./scripts/reliability-toggle.sh on --profile YOUR_PROFILE --no-restart
./scripts/doctor.sh --profile YOUR_PROFILE
```

### Uninstall cannot unapply patch (no `.bak`)

Patch restore needs the backup created at apply time. Without it, restore the file from Hermes git checkout or reinstall Hermes. Prefer `--skip-patch` if other profiles still need always-on pre_verify.

### WSL stuck / empty command output over SSH

```powershell
wsl --shutdown
wsl -d <Distro> -- echo ok
```

Remount drives if needed: `sudo mount -t drvfs C: /mnt/c`.

---

## Tradeoffs of claim-gate-only vs full stack

| Mode | You get | You give up |
|------|---------|-------------|
| Full (gate + truth + patch) | Strongest fail-closed | Needs runnable truth + patch maintenance after Hermes upgrades |
| Gate + patch, no truth | Blocks many “ship it / green” lies | No command receipts / truth MCP |
| Gate only, no patch | Soft + hook when Hermes runs pre_verify | Pure-talk lies may skip stock edit-gated pre_verify |

## Recommendation

1. Prefer full stack on a normal modern OS (macOS or Ubuntu 22.04+ WSL).  
2. Do not install Ubuntu “for Hermes” — only if you want easy truth prebuilts on Windows/WSL.  
3. Always finish with doctor PASS (use `--allow-no-truth` only when you knowingly skip truth).

## Related docs

- [COMPATIBILITY.md](COMPATIBILITY.md) — Hermes vs recipe vs truth requirements  
- [FETCH-TRUTH.md](FETCH-TRUTH.md) — download and GLIBC  
- [DOCTOR.md](DOCTOR.md) — health check flags  
- [HERMES-PATCH.md](HERMES-PATCH.md) — always-on pre_verify  
- [UNINSTALL.md](UNINSTALL.md) — clean removal  
