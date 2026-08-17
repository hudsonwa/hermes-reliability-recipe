# Upstream sync

This public kernel may be updated from a separate development tree via an
**allowlisted** exporter (copy + transform, not a raw dump).

- Metadata: `sync/LAST_SYNC.json` (written on each successful export; gitignored)
- Public-only files (install, doctor, AGENTS, fetch-truth, …) are **protected**
  and not clobbered by that exporter
- You should still run `make test` / `make test-quick` after pulls
