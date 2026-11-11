---
type: Decision
title: Why Duo
description: It uses Duo because its phone push approves sudo from anywhere for free, while other authenticators need a typed code, a work account, or someone at the Mac.
tags: [duo, pam, sudo, alternatives]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-11-11T06:13:17Z }
sources:
  - id: duo-free
    resource: https://duo.com/pricing/duo-free
    title: Duo Free
  - id: duo-unix-docs
    resource: https://duo.com/docs/duounix
    title: Duo Unix - two-factor authentication with PAM
  - id: entra-linux-ssh
    resource: https://learn.microsoft.com/entra/identity/devices/howto-vm-sign-in-azure-ad-linux
    title: Sign in to a Linux virtual machine in Azure by using Microsoft Entra ID and OpenSSH
---

# Why Duo

The goal is to approve `sudo` from a phone, without typing a password or code, even when nobody is at the Mac. Duo's push is the option that does that for free on a personal Mac.

## Decision

- **Use `pam_duo` for phone approval.** Duo sends a push to the Duo Mobile app, and tapping Approve lets `sudo` through.
- **Keep Touch ID first where it's set up.** On the Mac tested, `/etc/pam.d/sudo_local` lists `pam_tid.so` and then `pam_duo.so`, both `sufficient` (Tested 2026-11-11). Touch ID covers `sudo` at the keyboard, and Duo covers it everywhere else.
- **Don't support other PAM modules.** This tool only builds and patches `pam_duo`.

## Why

A push needs a service that receives the request and notifies the phone. Duo runs one, and `pam_duo` is the PAM client for it [duo-unix-docs]. The options compared:

| Option                                                                                | How you approve         | Why it wasn't picked                                                                                               |
| :------------------------------------------------------------------------------------ | :---------------------- | :----------------------------------------------------------------------------------------------------------------- |
| Code apps, such as Google Authenticator, via `pam_google_authenticator` or `pam_oath` | Type a 6-digit code     | Works remotely, but typing a code is no easier than typing the password.                                           |
| Microsoft Authenticator push                                                          | Tap a push              | Needs a Microsoft Entra ID work account, and Microsoft's PAM sign-in targets Linux VMs in Azure [entra-linux-ssh]. |
| Touch ID, via `pam_tid`                                                               | Fingerprint             | Needs you at the Mac with a sensor, so it can't approve `sudo` over SSH or while you're away.                      |
| Security keys, via `pam_u2f`                                                          | Touch the key           | The key must be plugged into the Mac, the same limit as Touch ID.                                                  |
| Duo push, via `pam_duo`                                                               | Tap a push on the phone | Picked. It works from anywhere, with no typing.                                                                    |

- **Code apps aren't push apps.** Google Authenticator only shows codes, and Microsoft Authenticator only shows codes for accounts other than Microsoft's own (Inferred 2026-11-11).
- **Duo is free for one person.** Duo Free covers up to 10 users at no cost [duo-free], as of 2026-11-11.
- **Touch ID can't be used remotely.** That `pam_tid` fails over SSH is reasoned from it needing the sensor, not tested (Inferred 2026-11-11).
- **The alternatives exist on macOS.** `pam_tid.so.2` ships in `/usr/lib/pam`, and Homebrew has formulas for `pam-u2f`, `google-authenticator-libpam` and `oath-toolkit` (Tested 2026-11-11).

## Consequences

- **The other modules wouldn't remove the need for this tool.** Homebrew's `pam-u2f` and `google-authenticator-libpam` install into the same user-writable folder as its `duo_unix`, so they'd also need building from source and patching, as in [Why it builds from source](build-from-source.md) (Inferred 2026-11-11).
- **Touch ID needs none of this.** Apple ships and updates `pam_tid`, so someone who only uses `sudo` at the Mac may not need Duo or this tool at all.
- **It depends on a third party.** Duo must be reachable for a push, and Duo doesn't list macOS as tested [duo-unix-docs]. With `failmode = secure`, an outage falls back to the password prompt. See the README's limits.

## Not verified

- No alternative module was installed or tried for this record.
- That no free push service other than Duo offers a PAM module wasn't surveyed.
