# 🤖 AGENTS.md

Conventions for any AI agent (or human) working in this repo. Read top to bottom before editing.

## 🎯 Purpose of this repo

A zsh tool that keeps a self-built Duo PAM module patched on macOS, with a two-approval proof and rollback. It's unofficial and not affiliated with Duo or Cisco. See [README.md](README.md).

- **It stays in zsh.** That decision is recorded in [why zsh](docs/decisions/why-zsh.md).
- **The code arrives in issue 2.** Today this repo holds only tooling, docs and draft records.
- **The shared plan is [issue 1](https://github.com/jjloneman/pam-duo-macos-updater/issues/1).**

## 🗂️ Project layout

- `scripts/lint.zsh`: the lint entry point, with its rules under `scripts/lint/`.
- `scripts/test.zsh`: runs every `test/*.test.zsh`.
- `test/helpers.zsh`: shared assertions, and `test/hook_helpers.zsh`: scratch repos and a stub pnpm for the hook tests, which stop the run rather than act outside their scratch folder.
- `test/fixtures/lint/<rule>/bad*/` and `good*/`: small trees for each lint rule, where each must pass or fail on its own, so an easy form can't hide a missed hard one. They're excluded from formatting, because many are deliberately wrong.
- `docs/decisions/`, `docs/references/`, `docs/playbooks/`: OKF v0.2 bundles.
- `.githooks/`: `pre-commit` formats staged files and lints an export of the index, refusing a partly staged file, and `pre-push` lints an export of every commit the push adds, skipping ones from before `scripts/lint.zsh` existed. CI runs formatting and tests on what's pushed. `pnpm install` turns them on.
- `.changeset/`: pending changesets.

Planned, per issue 1: `bin/`, `lib/`, `libexec/`, and `scripts/coverage.zsh`.

## ✍️ Code conventions

[Zsh scripting rules](docs/references/zsh-scripting-rules.md) has every rule with its evidence. Read it before writing or reviewing zsh.

- **Entry points** start with `#!/bin/zsh -f` and the standard header. Sourced files have no shebang and no execute bit.
- **Names:** functions read as what they do, booleans as questions (`is_helper_current`), constants are `SCREAMING_SNAKE_CASE`, and functions and locals are `snake_case`. No `data`, `tmp`, `obj`, `val` or `res`.
- **Order:** functions, constants and `case` branches are sorted, ignoring case, with `main` and a `case` catch-all last. Where order carries meaning, an `# Order:` comment directly above says why, and lint accepts it.
- **Shape:** 80 columns, 300 lines per file and 40 per function, a doc comment on every function, and an explicit `return`.
- **Spacing:** a blank line around multi-line statements and before comments, unless first in the block. A comment of three lines or more opens with a sentence, then `-` bullets separated by blank `#` lines.
- **Branches:** every branch is an `if`, because the coverage tracer can't see inside `&&` or `||`. `[[ ]]` and `(( ))` may use them internally.
- **Variables:** declared and braced, as in `"${name}"`. The bare forms left are `$?` and `"$@"`, and the argument count is always `${#}`.
- **Failures:** check each one. No `err_exit`, and every `case` has a catch-all that fails loudly.

### 🧨 Traps found while building this tooling

- **`$0` inside a function is the function's name.** Capture paths at the top level, which lint enforces. This once made the test runner find no tests and report success, so a runner must also fail on finding nothing.
- **`[[:space:]]#` needs `extended_glob`,** which stays off, and lint rejects it. Use `trim_line` in `scripts/lint/scan.zsh`.
- **macOS `mktemp` ignores `TMPDIR` without a template,** so lint requires one.
- **BSD `chmod` doesn't accept `--`,** unlike `rm`, `cp` and `mkdir`.
- **`$'\n'` doesn't expand inside double quotes.** Put it in a constant.
- **The formatter can't parse all valid zsh.** It rejected `${~name}`, glob subscripts such as `${(k)a[(R)*x*]}`, and some `[[ ]]` alternations with escaped parentheses. Rewrite the form, and never exclude the file.
- **`warn_nested_var` fires on assigning a global from a function.** Use `typeset -g` on each assignment.

## 🧾 Documenting fixes

Future sessions should be able to fail faster than this one did.

- **Document every fix,** in a comment beside the code, in [Fixes found in review](docs/decisions/review-fixes.md), or both. Say what failed, what prevents it now, and how that's verified.
- **After each fix, ask whether a lint rule or a line here would make the mistake impossible,** and add one when it would. A check that can't be reliable belongs under "Left to review" instead.

## 🧹 Lint

`scripts/lint.zsh` enforces the rules above, and prints `path:line: rule: message`.

- **A new rule needs a fixture.** `test/lint.test.zsh` fails unless rules and `test/fixtures/lint/` match one to one, and each rule catches every `bad*` tree and passes every `good*` tree.
- **Grep-style checks can't fully parse zsh.** If a rule turns out too noisy to trust, move it to review and say so in the issue, rather than weakening others.
- **`scripts/lint-legacy.txt` is temporary.** It's for imported code only: issue 2 adds files, issues 3 and 4 remove them, and issue 4 deletes the list and its code. Listed files skip style rules, but `zsh -n`, `helper_sources_nothing` and the formatter still apply. Never add new code to it.
- **Left to review:** whether a name describes its value, whether a failure-modes table is complete, and whether a value was checked before reaching `(( ))`.

## ✅ Checks

- **`pnpm check`** formats, lints and tests. Run it once over a batch of edits.
- **CI** runs the same checks on a macOS runner, plus `actionlint`.
- **Never bypass hooks** with `--no-verify` without the owner's approval.

## 📝 OKF records

- **Agents write `status: draft`,** and record themselves in `generated`.
- **`verified` needs the owner's approval,** either by editing the record themselves or by telling an agent to verify named records. Writing or editing a record never implies approval.
- **Check a record's `verified` field** before changing the behavior it describes.
- **Write records fresh for the public.** Mark each claim as tested, sourced or inferred, with a date.
- **Every record** has `tags` and is listed in its bundle's `index.md`, which lint checks.

## ✍️ Commit conventions

[Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) with a gitmoji after the colon: `<type>(scope): <gitmoji> <subject>`, imperative and fully lowercase after the prefix, with a `-` bullet body when needed.

| Type       | Gitmoji | Use for                        |
| ---------- | ------- | ------------------------------ |
| `build`    | 🔨      | build system                   |
| `chore`    | 🧹 / ⬆️ | housekeeping, dependency bumps |
| `ci`       | 🤖      | CI and workflow changes        |
| `config`   | 🔧      | tooling config                 |
| `docs`     | 📝      | documentation and records      |
| `feat`     | ✨      | new feature                    |
| `fix`      | 🔧      | bug fix                        |
| `refactor` | 🏗️      | refactor                       |
| `test`     | 🧪      | tests                          |

- **PRs are squash-merged,** and `main` accepts nothing else. The `Co-Authored-By` trailer goes on the squash commit only.

## 🚀 Versioning and releases

[Changesets](https://github.com/changesets/changesets) writes the changelog and versions. Nothing is published to npm, because `package.json` is `private`.

- **Every PR carries a changeset** (`pnpm changeset`), except Renovate's and the version PR. `feat` is a minor bump and everything else a patch. This is a rule rather than a CI gate.
- **`release.yml`** keeps a rolling `chore(release): 🚀 version packages` PR open while changesets are pending. Merging it bumps `package.json`, writes `CHANGELOG.md`, tags the version and creates a GitHub release.
- **The version PR runs no CI,** because a PR opened with `GITHUB_TOKEN` starts no workflows.

## 🕒 7-day dependency moratorium

No dependency may enter the lockfile until it has been published for at least 7 days. `minimumReleaseAge: 10080` enforces it in `pnpm-workspace.yaml`, and Renovate waits the same time. Never relax it.

- **No git dependencies,** because the moratorium doesn't hold those back.

## 🔐 Public repo rules

- **Never name or link a private repo,** or a private path. Say "a personal project."
- **No keys, API hostnames or alert topics, ever.**
- **Before each push,** scan the diff against your private repo list.

## 🛡️ Root and security changes

- **The helper stays one self-contained, root-owned file.** It never sources anything this user can write.
- **Exit codes don't change:** 0 proven, 2 refused, 3 restored, 4 restored after a signal, 5 restore failed.
- **No environment overrides** for paths or security settings.
- **Give the owner the commands for any root change.** Never read `/etc/duo/pam_duo.conf`.
- **Coverage is a tool, not the goal.** Name anything only a real run can prove, instead of faking a test.

## 🛑 Deleting things

- **Confirm with the owner before deleting anything the current task didn't create:** files, branches, issues or remote state.
- **On a Mac, prefer `trash` over `rm` when deleting by hand,** so a mistake can be undone. The scripts' own cleanup of their temporary folders still uses `rm`, as `trash` isn't on CI or older Macs.
