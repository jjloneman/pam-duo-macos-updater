---
type: Decision
title: Why the helper is root-owned
description: Root only runs one self-contained, root-owned helper that sources nothing, so editing the repo can't change what an approval runs.
tags: [pam, root, security, sudo]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-11-07T03:20:57Z }
---

# Why the helper is root-owned

An approval should only ever run code a person has already reviewed, whatever has happened to the repo since.

## Decision

This is the plan for the code arriving in issues 2 and 3.

- **Two parts:**
  - `bin/pam-duo-macos-updater` and `lib/*.zsh` run as the normal user, and the user can edit them.
  - `libexec/pam-duo-macos-updater-root` is the only code root runs. It's installed as a root-owned copy.
- **The helper is one self-contained file:** it sources nothing, and lint enforces that.
- **Changing it needs a person:** `install-helper` shows a text diff, then installs it with one approval.
- **If the copies differ, it stops:** an install refuses to run and the daily check alerts, because a difference is either a change waiting for review or tampering.
- **It refuses rather than guesses.** Before changing anything, it stops if:
  - `failmode` isn't `secure`;
  - the Duo config isn't `root:wheel` with mode 600;
  - Duo isn't turned on;
  - the module changed since it was verified, using a root-only copy checked against the checksum.
- **No environment overrides:** tests replace `lib/paths.zsh` in a sandbox copy, and a real run reads no paths or security settings from the environment.
- **New path and marker names:** the helper gets its own path under this project's name, so an earlier installed helper stays untouched until cutover.

## Why

- **Otherwise an edit becomes root.** If root ran the repo's script, anything running as the user could edit it, and a routine-looking approval would run the new code. That includes coding agents, which run as the user.
- **A shell script can be read.** The diff before `install-helper` is what protects root. A compiled helper would reduce that to comparing checksums of a file built as the user. See [Why zsh](why-zsh.md).
- **Small enough to review:** the helper was 232 lines, 109 of them code, as of 2026-11-06.
  - Converted to the code conventions in issue 17, it was 436 lines on 2026-11-11, most of the growth being comments and the blank lines the spacing rules need (Tested, with `wc -l`). It stays one file, so lint allows it 450 lines rather than the usual 300, since splitting it would mean several root-owned files and diffs to approve (Inference).
- **It has passed a real test:** an approved install and a denied install that rolled back passed with real root and real Duo on 2026-11-06, using the earlier copy of the helper this project starts from.

## Consequences

- **The module is still built as the normal user.** The helper stops an approval from running arbitrary new root code, but a process running as the user could feed in a malicious build, which an approval would install. Only approve installs you started. Building as a separate unprivileged user would close this, and is out of scope for now.
- **The other modules stay user-writable.** That matches the earlier script. They still choose what gets built and what's reported, but they can't run as root through the helper.
- **Any helper change costs a review, an approval and the real tests again,** so refactor it only with care.
- **Exit codes are a contract** between the helper and the main script: 0 proven, 2 refused, 3 restored, 4 restored after a signal, 5 restore failed. Their names change in issue 3, and the numbers don't.

## Not verified

- This repo's copy of the helper doesn't exist yet, so nothing above has been run from this repo as of 2026-11-06.
- The refusal branches for a held lock, a missing module, an unsafe OpenSSL folder and a failed swap had no test running them as of 2026-11-06. Issue 4 covers them.
