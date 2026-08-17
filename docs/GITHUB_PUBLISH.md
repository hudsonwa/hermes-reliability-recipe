# Releasing

This repository is the public tree. Publish only this tree.

Do not import git history from any other checkout. A first publish should be a single new commit of the current files (`scripts/make-github-orphan.sh` builds that checkout; it does not push).

Use a noreply git identity. Do not commit real `.env` files, session dumps, or extra scrub needle lists (`scripts/scrub-needles.local` is gitignored on purpose).
