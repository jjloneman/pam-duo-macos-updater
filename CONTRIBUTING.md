# 🤝 Contributing

Thanks for your interest. This is one person's project that touches how `sudo` works, so expect careful review, and please open an issue before starting anything large.

## 📖 Table of contents

- [🧰 Setup](#-setup)
- [✅ Checks](#-checks)
- [🌿 Pull requests](#-pull-requests)
- [🧪 What tests can't prove](#-what-tests-cant-prove)
- [🔒 Security problems](#-security-problems)

## 🧰 Setup

You need macOS, because the tool targets its `/bin/zsh`, plus Node and pnpm for the formatter and Changesets.

```sh
pnpm install
```

This also turns on the git hooks in `.githooks/`, by setting this clone's `core.hooksPath`, but only if it has none of its own.

- **Your global hooks stop running here,** because a repo's `core.hooksPath` overrides a global one. If you rely on one, such as a secret scanner, don't edit `.githooks/`, which is tracked and could be committed. Instead, point this clone's `core.hooksPath` at a folder of your own whose hooks run yours and then `.githooks/<hook>`. `pnpm install` leaves that setting alone.

## ✅ Checks

```sh
pnpm check
```

This formats, lints and tests. CI runs the same checks on a macOS runner.

The code conventions and lint rules are in [AGENTS.md](AGENTS.md), with their evidence in the [zsh scripting rules](docs/references/zsh-scripting-rules.md). Two surprises:

- **The argument count is `${#}`.** The formatter corrupts the short form.
- **A new lint rule needs a fixture,** a bad tree and a good one under `test/fixtures/lint/`.

## 🌿 Pull requests

- **Titles** follow the [commit conventions](AGENTS.md#️-commit-conventions), because PRs are squash-merged.
- **Add a changeset** with `pnpm changeset`, for the changelog.
- **Keep to one concern,** with tests alongside the change.
- **Never include keys, API hostnames or alert topics,** including in logs and examples.

## 🧪 What tests can't prove

Tests fake `sudo`, Duo and the compile. Real `sudo`, a real Duo push and a real build are run only by the maintainer, on a real Mac, because a mistake there can lock someone out of `sudo`.

- **Don't test against your own PAM setup** to try out a change unless you know how to recover from it.
- **Name anything only a real run can prove** in your PR, rather than writing a test that fakes it.

## 🔒 Security problems

Please report these privately, as [SECURITY.md](SECURITY.md) describes, and not in an issue or a PR.
