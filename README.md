# 🔐 pam-duo-macos-updater

Keeps a self-built [Duo](https://duo.com/docs/duounix) [PAM](https://en.wikipedia.org/wiki/Pluggable_authentication_module) module (`pam_duo`) patched on macOS, with a two-approval proof and rollback. New to these? See [what PAM and Duo are, and why this exists](#-what-pam-and-duo-are-and-why-this-exists).

- **Unofficial:** this project is not affiliated with Duo or Cisco.
- **Not ready for use yet:** as of 2026-11-06 the code hasn't been imported, so there's nothing to install or run.
- **It changes who can become root:** the tool replaces a module that `sudo` loads, so a mistake or a tampered build can break `sudo` or weaken it. Read [the limits and risks](#-limits-and-risks) first.

## 📖 Table of contents

- [🚨 Limits and risks](#-limits-and-risks)
- [💡 What PAM and Duo are, and why this exists](#-what-pam-and-duo-are-and-why-this-exists)
- [📦 Status](#-status)
- [🧭 What the tool will do](#-what-the-tool-will-do)
- [🧪 What has been tested](#-what-has-been-tested)
- [🧰 Development](#-development)
- [📚 Docs](#-docs)
- [🔒 Security](#-security)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

## 🚨 Limits and risks

These describe the plan for the code arriving in [issue 2](https://github.com/jjloneman/pam-duo-macos-updater/issues/2), and the setup it comes from.

- **macOS isn't a platform Duo lists.** As of 2026-11-06, Duo's Unix page names Linux, BSD, Solaris and AIX as tested, not macOS ([Duo Unix docs](https://duo.com/docs/duounix)). You'd be on your own, with no vendor support for this setup.
- **An approved push stands in for your password.** A denied push, or Duo being unreachable, falls through to the normal password prompt. That only holds with `failmode = secure`: Duo's default is `safe`, which allows access on a service or configuration error.
- **The module is built as your normal user.** A process already running as you could feed in a malicious build, and an approval would then install it. Only approve installs you started. [SECURITY.md](SECURITY.md#-known-limits) has this and the other known limits.
- **Touch ID may defeat the proof.** With a fingerprint enrolled and `pam_tid.so` listed before Duo, the second approval could pass without using the new module. This is reasoned from PAM's order, not tested, and it's the first planned fix in [issue 5](https://github.com/jjloneman/pam-duo-macos-updater/issues/5).
- **Rollback isn't absolute.** A forced kill during the proof can skip the restore. The plan is to raise an alert from a leftover marker, not to promise recovery. Keep a root shell open while you're setting this up.
- **It runs on one Mac so far.** Its results come from one owner's machine, and it isn't built for anyone else's yet. Other macOS security settings, including System Integrity Protection, weren't tried, so results may differ. A setup guide and an undo guide are planned in [issue 6](https://github.com/jjloneman/pam-duo-macos-updater/issues/6), which is optional.
- **Nothing installs unattended, by design.** You need to be there, with your phone, for each install.

## 💡 What PAM and Duo are, and why this exists

- **PAM:** [Pluggable Authentication Modules](https://en.wikipedia.org/wiki/Pluggable_authentication_module) are the plug-ins macOS uses to decide whether a login or `sudo` is allowed. A file under `/etc/pam.d` lists which modules each service asks.
- **Duo:** [Duo](https://duo.com/product/multi-factor-authentication-mfa) is Cisco's two-factor authentication service, which sends an approval to your phone. [Duo Unix](https://duo.com/docs/duounix) includes `pam_duo`, the module that lets PAM ask Duo.
- **Together:** with `pam_duo` listed for `sudo`, you can approve `sudo` from your phone instead of typing your password.

A setup like this is hard to keep safe by hand, which is the gap this tool fills:

- **You have to build the module yourself.** Duo doesn't list macOS, and [Homebrew's copy depends on files your user can write](docs/decisions/build-from-source.md), which `sudo` shouldn't load.
- **A self-built module doesn't update itself.** It carries its own OpenSSL, and nothing tells you when that or Duo Unix gets a security release.
- **A bad replacement can lock you out of `sudo`,** which is what you'd need to fix it. So each install has to [prove the new module works](docs/decisions/two-approvals.md), and put the old one back if it doesn't.

## 📦 Status

As of 2026-11-06:

- **In this repo:** the license, these docs, the formatter and lint tooling, CI, and the first [draft records](docs/decisions/index.md).
- **Not in this repo yet:** the tool, its root helper and its tests. [Issue 2](https://github.com/jjloneman/pam-duo-macos-updater/issues/2) imports them from a private location, with a clean history.
- **There are no install steps,** because there's nothing to install. This section will say when that changes.

The full plan, in seven steps, is in [issue 1](https://github.com/jjloneman/pam-duo-macos-updater/issues/1).

## 🧭 What the tool will do

This is the plan for the imported code, not a description of anything you can run today.

- **Daily check:** reads the versions out of the installed module, compares them with published releases, and sends an alert when a release is ready or anything fails.
- **Waiting period:** a release must be 7 days old before it's used.
- **Build:** compiles OpenSSL and `pam_duo` from source, with a clean environment, so nothing `sudo` loads depends on files your user can write. See [why it builds from source](docs/decisions/build-from-source.md).
- **Verify:** rejects a build unless it links only `/usr/lib` libraries, has no user-writable paths built in, reports the expected versions, exports `pam_sm_authenticate`, and really loads.
- **Install, with two approvals:** one to start a root-owned helper that swaps the module, and one to prove the new module approves `sudo`. No proof within 3 minutes restores the old module. See [why the install takes two approvals](docs/decisions/two-approvals.md) and [why the helper is root-owned](docs/decisions/root-owned-helper.md).

## 🧪 What has been tested

Real runs, with real root and real Duo, used the earlier script this repo will import, not code from this repo. On 2026-11-06, on one Mac, with duo_unix 2.3.0 and OpenSSL 3.5.9:

- **Passed:**
  - An approved install.
  - A denied install, which sent exactly two pushes and restored the old module about 3 minutes after the swap.
  - Approving, denying and Duo being unreachable, for a plain `sudo`.
- **Not yet proven:**
  - A closed terminal during the proof, as a real run.
  - A real release going through the waiting period.
  - Anything in this repo's own layout, which is why the real tests are repeated in [issue 7](https://github.com/jjloneman/pam-duo-macos-updater/issues/7).

## 🧰 Development

You need Node and pnpm for the formatter and Changesets. The tool itself won't need either, and this isn't a Node project.

```sh
pnpm install
pnpm check
pnpm test
```

- **`pnpm install`** installs the formatter and Changesets, and turns on the git hooks.
- **`pnpm check`** formats, lints and tests.
- **`pnpm test`** runs the tests on their own.

[CONTRIBUTING.md](CONTRIBUTING.md) covers the rest of the setup.

## 📚 Docs

Records are [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) v0.2 bundles. Everything is an agent-written draft until its owner signs it off.

- [docs/decisions/](docs/decisions/index.md): why it's built the way it is.
- [docs/references/](docs/references/index.md): facts, including the [zsh scripting rules](docs/references/zsh-scripting-rules.md).
- [docs/playbooks/](docs/playbooks/index.md): procedures, none yet.

## 🔒 Security

Please report problems privately, as [SECURITY.md](SECURITY.md) describes, rather than in a public issue.

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## 📄 License

[MIT](LICENSE)
