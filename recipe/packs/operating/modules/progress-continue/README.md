# Module: progress-continue (opt-in)

A Hermes plugin (two hooks, no core patch) that gives a bot a dynamic step limit: when a turn hits
`agent.max_turns`, it continues while the bot makes real progress (plan ticks, file changes, new
tool results) and stops with a "stuck on X" report when it does not. Bounded by
`max_continuations × max_turns` and a wall-clock cap.

Install: `install-pack.sh ... --module progress-continue`. It copies `plugin/` to
`<profile>/plugins/progress-continue`, adds it to `plugins.enabled`, sets
`plugins.entries.progress-continue.allow_gateway_injection: true`, and adds one SOUL line.
It does not reload the gateway. Tuning: `plugins.entries.progress-continue.{max_continuations,
wall_clock_cap_s,min_novel_ratio,min_novel_calls,repeat_failure_limit,guardrail_hit_limit}`.

`bin/pc-run` drives one-shot `hermes chat -q` runs (no REPL to inject into); gateway chats don't need it.
Tests: `tests/run.sh`.
