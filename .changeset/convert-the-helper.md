---
"pam-duo-macos-updater": patch
---

Convert the root-owned helper to the repo's code conventions, and rename its module path constant so it no longer shadows zsh's own module search path. It now restores at once if it can't record the run ID, rather than waiting out the timeout, with the same exit status.
