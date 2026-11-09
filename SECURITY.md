# 🔒 Security policy

## 📖 Table of contents

- [🎯 Supported versions](#-supported-versions)
- [📣 Reporting a vulnerability](#-reporting-a-vulnerability)
- [🧭 What's in scope](#-whats-in-scope)
- [🚧 Known limits](#-known-limits)

## 🎯 Supported versions

As of 2026-11-06 nothing has been released, and the tool's code hasn't been imported yet. Once it is, only the latest release gets security fixes.

## 📣 Reporting a vulnerability

**Please don't open a public issue for a security problem.** Report it privately instead:

1. Go to the repo's [Security tab](https://github.com/jjloneman/pam-duo-macos-updater/security).
2. Choose **Report a vulnerability**.
3. Describe the problem, and include a proof of concept if you have one.

- **Who sees it:** only the maintainer.
- **What happens next:** you'll get a reply once it has been triaged. This is one person's project, so there's no promised response time.
- **Credit:** once a fix is released, the advisory is published and you're credited, unless you'd rather not be.
- **Leave out your own secrets:** never include your Duo keys or API hostname in a report.

## 🧭 What's in scope

Today that's this repo's docs and tooling. Once the code is imported, these count:

- **Root:** any way to get new code run as root through an approval, other than the known limits below.
- **The root-owned helper:** a way around its refusals, its checksum check, or its comparison with the source copy.
- **Failing open:** anything that lets `sudo` succeed with no valid approval or password, or installs a config with `failmode` other than `secure`.
- **Rollback:** a case where a failed or denied proof leaves the new module in place and reports success.
- **Verification:** a build that passes the checks while carrying a user-writable path or library.
- **Download checks:** a way to get a tampered release past the checksum check.
- **Environment overrides:** an environment variable that changes a path or security setting in a real run.
- **Leaks:** a key, API hostname or alert topic reaching a log, an alert, or this repo.

These don't count:

- **Upstream bugs:** problems in `pam_duo`, OpenSSL, macOS or Duo's service. Please report them to those projects.
- **Dev dependencies:** a problem in a formatter or Changesets dependency that never runs in the tool. Please report it upstream.
- **Already root:** an attack that needs root to begin with.

## 🚧 Known limits

These are known and accepted for now, so they aren't new findings. A report showing one is worse than described here is welcome. Each describes the plan for the imported code, as of 2026-11-06.

- **The module is built as a normal user.**
  - A process already running as that user can tamper with the build, and an approval would then install what it produced.
  - The verify step and the root-owned helper limit this but can't remove it.
  - Only approve installs you started. Building under a separate unprivileged user would close it, and that's out of scope for the current plan.
- **Touch ID could satisfy the second approval.**
  - The second approval proves the new module works by running `sudo` with password fallback off.
  - If `pam_tid.so` comes before Duo in `/etc/pam.d/sudo_local` and a fingerprint is enrolled, it could pass without using the new module, so a broken module could be marked proven.
  - This comes from PAM's order and hasn't been tested, because the one Mac tested had no fingerprints enrolled. It's the first fix planned in [issue 5](https://github.com/jjloneman/pam-duo-macos-updater/issues/5).
- **Modules are user-writable, and only the helper is root-owned.**
  - The main script and its `lib/*.zsh` modules can be edited by the user, or by anything running as that user.
  - Root only ever runs the separate, root-owned helper, which sources nothing. An install refuses to start if the installed helper differs from the repo's copy, until a person reviews the diff and reinstalls it. See [why the helper is root-owned](docs/decisions/root-owned-helper.md).
  - The user-writable code still decides what's built, and can show misleading output or send false alerts.
- **A forced kill can skip rollback.** `SIGKILL` during the proof leaves the new module live and unproven. A leftover marker then raises an alert, and the next install restores the proven module first.
- **Unexpected pushes:** anything running as you can start `sudo`, which sends a push. Treat a push you didn't start as a reason to deny.
- **Duo being down means passwords:** with `failmode = secure`, an outage falls back to the password prompt, never to open access. The setup keeps password fallback so an outage can't lock you out.
