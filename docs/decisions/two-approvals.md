---
type: Decision
title: Why the install takes two approvals
description: One approval starts the root helper and a second proves the new module approves sudo, with the old module restored if the proof doesn't pass.
tags: [duo, pam, rollback, sudo]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-11-07T03:20:57Z }
sources:
  - id: duo-unix-docs
    resource: https://duo.com/docs/duounix
    title: Duo Unix - two-factor authentication with PAM
---

# Why the install takes two approvals

A new module can only be judged by whether it really approves `sudo`, and if it can't, nobody should be left without `sudo`.

## Decision

This is the plan for the code arriving in issues 2 and 3.

1. **Build and verify** as the normal user, with no approval.
2. **First approval:** starts the root-owned helper, which refuses an unsafe setup, checks a root-only copy of the module against its checksum, keeps the old module as `pam_duo.so.previous`, and swaps atomically.
3. **Second approval:** with the helper still running, the script forgets cached approvals with `sudo -k`, then runs `SUDO_ASKPASS=/usr/bin/false sudo -A touch <flag>`, so a password can't stand in for Duo.
4. **The result:**
   - The helper sees the flag and exits 0. Markers hold this run's ID, so a leftover can't pass as this run.
   - No approval within 3 minutes, or a closed terminal: it restores the old module.

Helper exit codes:

| Code | Meaning                       |
| ---: | :---------------------------- |
|    0 | Proven                        |
|    2 | Refused, with nothing changed |
|    3 | Restored after no approval    |
|    4 | Restored after a signal       |
|    5 | The restore itself failed     |

- **It never runs unattended:** an install needs a terminal and a person each time.
- **Password fallback stays:** the PAM line is `sufficient`, and `failmode` must be `secure`.

## Why

- **The second approval tests what stubs can't.** Only a real push through the new module shows it works with real `sudo` and real Duo.
- **Unattended installs are too risky:** a root job compiling downloads and replacing what `sudo` loads could break `sudo` with nobody watching.
- **Ordering bugs have happened.** Each of these came from building or testing the earlier script:
  - `sudo` caches approvals for about 5 minutes per terminal, so a proof could send no push. Hence `sudo -k`.
  - A leftover flag looked like this run's swap. Hence the run ID.
  - A swap marker written before the rename could've let the proof run against the old module. Hence announcing after acting.
- **`failmode` must be replaced, not assumed:** Duo's default is `safe`, which allows access on a service or configuration error [duo-unix-docs].

Evidence, from the earlier script, on one Mac with duo_unix 2.3.0 and OpenSSL 3.5.9, on 2026-11-06:

- **Approved install:** the log recorded `proven after 16s`.
- **Denied install:**
  - Exactly two pushes arrived, so `sudo -k` does force a new approval.
  - `sudo -A` printed `no password was provided`, then `a password is required`, and sent no further push.
  - The old module was back about 3 minutes after the swap, by checksum, and no markers remained.

## Consequences

- **Two pushes per install,** roughly 10 installs a year based on past OpenSSL and duo_unix releases.
- **The live module and the backup match after a rollback,** because the install overwrites the backup with the live module before swapping.
- **Leftover state is handled first:** if an earlier install never finished, the proven module is restored before anything else, so an unproven one can't become the backup.
- **A forced kill can skip the restore.** A leftover marker then raises an alert.
- **Touch ID is a known gap.** With `pam_tid.so` before Duo and a fingerprint enrolled, the proof could pass without using the new module. Issue 5 fixes it first.

## Not verified

- A closed terminal during the proof hasn't had a real run. It's on the real-test list in issue 7.
- The Touch ID gap comes from PAM's order, and hasn't been tested, because the Mac tested had no fingerprints enrolled as of 2026-11-06.
- Whether a job with no terminal can trigger a push is unproven.
- Nothing above has run from this repo's code as of 2026-11-06.
