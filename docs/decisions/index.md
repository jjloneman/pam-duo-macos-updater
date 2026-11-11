---
okf_version: "0.2"
---

# Decisions

- [Fixes found in review](review-fixes.md) - What six code reviews and the owner's review found wrong in this repo's lint and test tooling, what prevents each now, and how that's verified, so similar work can fail faster.
- [Why it builds from source](build-from-source.md) - The module and its OpenSSL are compiled from source with root-owned paths built in, because Homebrew's copies depend on files the user can write.
- [Why the helper is root-owned](root-owned-helper.md) - Root only runs one self-contained, root-owned helper that sources nothing, so editing the repo can't change what an approval runs.
- [Why the install takes two approvals](two-approvals.md) - One approval starts the root helper and a second proves the new module approves sudo, with the old module restored if the proof doesn't pass.
- [Why Duo](why-duo.md) - It uses Duo because its phone push approves sudo from anywhere for free, while other authenticators need a typed code, a work account, or someone at the Mac.
- [Why zsh](why-zsh.md) - It stays in zsh because root needs a root-owned shell that ships with macOS, a text helper can be reviewed, and runtime speed doesn't matter here.
