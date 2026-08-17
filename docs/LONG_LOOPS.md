# Long autonomous loops (lean main)

For weaker models on long agentic runs:

1. **Keep the main context lean** — plan, integrate, verify.
2. **Delegate bulk work to fresh workers** when jobs would bloat context.
3. **Communicate via disk** (`plan.md`, `log.md`, OUT files).
4. **Never trust “worker said done”** — read the OUT file.

## Surfaces

| Surface | Long-loop fit |
|---------|---------------|
| Gateway / GUI / open chat | Best (parent stays alive) |
| `hermes chat -q` one-shot | Poor for async multi-agent (parent exit can kill kids) |
| Blocking worker + wait | OK for CI |

## Prompt vs harness

| Control | Role |
|---------|------|
| System-prompt worker essay | Weak — often ignored |
| Hard OUT contract in task | Required |
| Claim gate | Stops success-lies |
| Parent stays alive + join | Required for async |

## Anti-patterns

- Main `-q` + background delegate + “I’ll resume later”
- Scoring success by model prose
- Giant worker policy in the system prompt
