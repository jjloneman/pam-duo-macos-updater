---
"pam-duo-macos-updater": patch
---

Fix a flaky harness check that could send its closing-terminal signal before the helper had swapped the module and set its trap. It now waits until the helper records this run's ID.
