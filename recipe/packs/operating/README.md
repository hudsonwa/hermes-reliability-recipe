# Operating pack (opt-in, v0.3.0)

The core recipe checks *claims* in code. This pack adds short working habits on top,
for bots on smaller or local models that need them spelled out:

| Piece | What it does |
|---|---|
| `soul/operating-pack.md` | SOUL block (marked `hrr:begin/end operating-pack`): proof before claims, plan-only means plan only, GO line before work, browser etiquette, final clicks need a yes |
| `skills/` | `proof-and-receipts`, `plan-to-issues`, `browser-etiquette` → `skills/operating/` |
| `bin/truth-mcp-workdir` | Starts `truth-mcp` in the bot's work folder (from `~/.hermes` it indexes the whole tree and `verify_turn` times out) |
| `captcha/` | `--captcha handoff` (default: never touch, hand to the owner) or `tick` (owner allows ticking). Exactly one rule is rendered into both SOUL and skill |
| `modules/progress-continue/` | Opt-in module (`--module progress-continue`): a plugin that continues a turn at its step limit only while the bot makes real progress; stops with a "stuck on X" report otherwise. See its README |

Install (after or together with the core recipe):

    scripts/install.sh --profile NAME --pack operating --owner "Name" --workdir /abs/path [--captcha handoff|tick]
    # or, core already installed:
    recipe/packs/operating/install-pack.sh --profile NAME --owner "Name" --workdir /abs/path

It never widens permissions: any hard rule elsewhere in SOUL.md wins. It appends its block at the
end of SOUL.md, so botport/twin blocks stay before it. Re-running replaces the block (and migrates
a legacy `botstack` block). Backups: `SOUL.md.bak.pack-*`, `config.yaml.bak.pack-*`.

Undo: delete the `hrr:begin/end operating-pack` block, `skills/operating/`, and point the truth MCP
`command:` back at `bin/truth-mcp`.

Limits: this is prompt text plus one MCP launcher. It does not stop a forbidden click; an action
guard (`pre_tool_call`) is separate work.

Tests: `bash recipe/packs/operating/tests/test_pack.sh` (hermetic, temp profile).
