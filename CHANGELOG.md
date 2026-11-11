# pam-duo-macos-updater

## 0.1.1

### Patch Changes

- 7b6446a: Convert the root-owned helper to the repo's code conventions, and rename its module path constant so it no longer shadows zsh's own module search path. It now restores at once if it can't record the run ID, rather than waiting out the timeout, with the same exit status.

## 0.1.0

### Minor Changes

- 204f6e9: Import the tool, its root-owned helper and its test harness, renamed for this repo with no change in behavior. The harness runs against a compiled stand-in module where none is installed, and `pnpm coverage` reports line coverage.

### Patch Changes

- 9e528cd: Fix a flaky harness check that could send its closing-terminal signal before the helper had swapped the module and set its trap. It now waits until the helper records this run's ID.
- 87212c6: Record why the tool uses Duo rather than another authenticator, such as Google Authenticator, Microsoft Authenticator, Touch ID or a security key.
- 5bd3fe8: Set up the repo's public files, formatter, lint, hooks, CI, Renovate, Changesets, and first draft records. The tool's code isn't imported yet.
