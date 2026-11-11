---
type: Reference
title: Exit codes
description: What each exit status of the script and the root-owned helper means, and what has happened to the installed module at each.
tags: [exit-codes, pam, root]
status: stable
generated: { by: claude-code/claude-opus-5-5, at: 2026-11-10T01:37:16Z }
verified: { by: human:jjloneman, at: 2026-11-11T05:54:03Z }
---

# Exit codes

Read from the code imported in issue 2, on 2026-11-10 (Inference, from reading the code, unless a row says Tested).

## The helper

`libexec/pam-duo-macos-updater-root` runs as root, through `sudo`, and swaps in a verified module. Its exit status says what happened to the installed module. **These numbers don't change**, because the script reads them, and a later rename only gives them names.

| Status | Name, from issue 3           | The module afterwards               | When                                                                                                                |
| -----: | :--------------------------- | :---------------------------------- | :------------------------------------------------------------------------------------------------------------------ |
|    `0` | `EXIT_PROVEN`                | The new one, proven                 | A Duo approval arrived through the new module before the timeout.                                                   |
|    `2` | `EXIT_REFUSED`               | Untouched                           | It refused before the swap: bad arguments, not root, the lock held, an unsafe config, no module, or a changed file. |
|    `3` | `EXIT_RESTORED`              | The old one, restored               | No approval arrived before the timeout.                                                                             |
|    `4` | `EXIT_RESTORED_AFTER_SIGNAL` | The old one, restored               | A hangup, interrupt or terminate signal arrived after the swap, such as a closed terminal.                          |
|    `5` | `EXIT_RESTORE_FAILED`        | Unknown: **test `sudo` right away** | Restoring the old module failed, after a timeout, a signal, or an earlier install's leftover marker.                |

- **A refusal after the swap is still `2`:** if moving the new module into place fails, the old module is still the live one, so nothing changed.
- **Restoring first:** a marker left by an unfinished install makes the helper restore the old module before anything else. If that fails, it exits `5` without swapping.
- **Any other status** is unexpected, and the script says to test `sudo`.
- **Tested, with a faked `sudo` and module paths in a sandbox:** the harness checks `2` and `4` as statuses, and the modules left by `0` and `3` through the script. `5`, and a real swap as root, need a real run.

## The script

`bin/pam-duo-macos-updater` runs as the user.

| Status | Meaning                                                                                                |
| -----: | :----------------------------------------------------------------------------------------------------- |
|    `0` | The command did what it was asked, or there was nothing to do, such as `auto` on a Mac with no module. |
|    `1` | Something failed, and the script printed why. The daily `check` also sends an alert where it can.      |
|    `2` | Usage: an unknown subcommand or option. Nothing ran.                                                   |

- **A helper failure becomes `1`:** the script maps the helper's status to a message, shows the last lines of the helper's log, and exits `1`.
