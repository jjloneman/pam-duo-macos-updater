---
type: Decision
title: Why it builds from source
description: The module and its OpenSSL are compiled from source with root-owned paths built in, because Homebrew's copies depend on files the user can write.
tags: [build, openssl, pam, security]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-11-07T03:20:57Z }
sources:
  - id: duo-unix-docs
    resource: https://duo.com/docs/duounix
    title: Duo Unix - two-factor authentication with PAM
  - id: openssl-config
    resource: https://docs.openssl.org/3.5/man5/config/
    title: OpenSSL 3.5 manual, config
---

# Why it builds from source

Nothing `sudo` loads may depend on a file the user can write, and Homebrew's `pam_duo` can't meet that.

## Decision

This is the plan for the code arriving in [issue 2](https://github.com/jjloneman/pam-duo-macos-updater/issues/2), based on the setup it comes from.

- **Compile both from source:** a private, static OpenSSL, then `pam_duo` against it, both as the normal user.
- **Build in only root-owned paths:** OpenSSL's prefix is `/usr/local/duo-openssl` and its config folder is `/etc/duo/ssl`.
- **Check before installing.** A build is rejected unless it:
  - links only `/usr/lib` libraries;
  - has no user-writable paths in its strings;
  - has its OpenSSL config folder under `/etc/duo/ssl`;
  - reports the expected versions;
  - exports `pam_sm_authenticate`, and really loads.
- **Install only the module:** to `/usr/local/lib/pam/pam_duo.so`. A full `make install` also adds `login_duo`, setuid root, which this doesn't use.
- **A script keeps it patched:** Homebrew can't update a self-built module, so this tool watches for releases and rebuilds. Its waiting period and checksum sources get their own record.

## Why

- **Every process you run can write to Homebrew's folder.** On the Mac tested, `/opt/homebrew` belongs to the normal user (Tested 2026-11-06).
- **Homebrew's `duo_unix` installs into that folder.** `brew info duo_unix` lists the formula at 2.3.0 (Tested 2026-11-06).
- **Linking Homebrew's OpenSSL statically doesn't fix it:**
  - Its compiled-in config folder is `/opt/homebrew/etc/openssl@3`, as `openssl version -d` prints (Tested 2026-11-06).
  - An OpenSSL config file can load code, such as an engine by its `dynamic_path` [openssl-config].
  - So a user-owned `openssl.cnf` could load code as root.
  - Found during the original setup, and not rebuilt for this record: `otool -L` doesn't show this, and `strings` does. That's why verification reads both.
- **Duo doesn't list macOS.** As of 2026-11-06, Duo's page lists Linux, BSD, Solaris and AIX as tested, not macOS [duo-unix-docs].

## Consequences

- **Builds take about a minute.** One full build measured 56 s on 2026-11-06, 49 s of it compiling, on the one Mac tested.
- **The build itself is still untrusted:** it runs as the normal user, so a process running as that user could tamper with it. See [Why the helper is root-owned](root-owned-helper.md), and the known limits in [SECURITY.md](../../SECURITY.md#-known-limits).
- **The OpenSSL series is pinned:** to 3.5 LTS as of 2026-11-06, so a new major version can't break the build. Moving series is a deliberate code change.

## Not verified

- A static build against Homebrew's OpenSSL wasn't repeated for this record.
- That no other macOS path offers a safer prebuilt module wasn't surveyed.
