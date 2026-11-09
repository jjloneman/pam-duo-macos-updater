---
type: Decision
title: Fixes found in review
description: What six code reviews and the owner's review found wrong in this repo's lint and test tooling, what prevents each now, and how that's verified, so similar work can fail faster.
tags: [linting, review, testing, zsh]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-11-09T21:00:00Z }
---

# Fixes found in review

Six rounds of code review on [issue 1](https://github.com/jjloneman/pam-duo-macos-updater/issues/1) kept finding the same kinds of mistake, so this records them for anyone writing similar tooling.

## Decision

- **Git hook fixes are documented in the hooks themselves,** guard by guard, each marked Tested or Probed. See `.githooks/pre-commit` and `.githooks/pre-push`.
- **Everything else that went wrong is listed here,** with what prevents it now.
- **After each fix, a lint rule or an `AGENTS.md` line is considered,** as [AGENTS.md](../../AGENTS.md#-documenting-fixes) requires.

## Silent passes

These were the most serious, because a broken check looked like a clean run.

| What failed                                                                                       | What prevents it now                                                   | Verified by                                        |
| :------------------------------------------------------------------------------------------------ | :--------------------------------------------------------------------- | :------------------------------------------------- |
| A test runner used `$0` inside a function, found no tests and reported success                    | The runner fails on finding none, and `no_argzero_in_function`         | Lint fixture                                       |
| Lint exited 0 for a missing root, an empty root or an unreadable file                             | Exit 2 through `tool_error`                                            | Exit-code tests                                    |
| A rule file that failed to load removed its rules and lint still exited 0                         | `load_rule_file` checks that each file's last function arrived         | Test                                               |
| A failed `grep` was hidden by `pipe_fail`, so a broken rule reported nothing                      | `report_pattern` runs its two greps separately                         | Test                                               |
| A rule with no bad fixture passed with zero checks                                                | Each rule needs `bad*` and `good*` trees, which must have been scanned | `test/lint.test.zsh`                               |
| A signal test watched an empty folder, because macOS `mktemp` ignores `TMPDIR` without a template | `mktemp_has_template`                                                  | Lint fixture, and removing the trap fails the test |
| A "fixed" commit in a test still failed lint, so two guards could break unnoticed                 | The commit is clean, and each guard was mutation-checked               | Mutation                                           |

## Lint reading zsh wrongly

| What failed                                                                  | What prevents it now                                                                       |
| :--------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------- |
| A here-string or `<<` shift read as a heredoc, blanking the rest of the file | `mask.awk` tracks `<<<` and arithmetic, including inside double quotes and continued lines |
| A quoted or hyphenated heredoc delimiter was misread                         | `mask.awk` accepts any quoted or backslashed delimiter                                     |
| `[[:space:]]#` never matched, because it needs `extended_glob`               | `trim_line`, and `no_glob_repeat_hash`                                                     |
| `$'\n'` inside double quotes stayed literal                                  | A `NEWLINE` constant, noted in AGENTS.md                                                   |
| `"${(oj: :)x}"` joined without sorting                                       | Sort first, then join                                                                      |
| A test or bracket class hid `&&` on later lines                              | `strip_tests.awk` opens tests only at a word start, and keeps `$(...)` visible             |
| A continued line or multi-line array hid a declaration                       | Statement view, joining `\` and open parentheses                                           |
| A one-line function or stray `{ }` block misaligned function lengths         | Ends are recorded only while a function is open                                            |
| A same-line `case` branch stopped lint                                       | The branch stack is guarded                                                                |

## Failures left unchecked

| What failed                                                                                         | What prevents it now                                         |
| :-------------------------------------------------------------------------------------------------- | :----------------------------------------------------------- |
| A failed setup step left a hook test running in the real repo, as `cd -- ""` succeeds and stays put | `abort_setup` and a scratch-folder guard, and `unchecked_cd` |
| Inherited `GIT_DIR` aimed a hook test at the real repo                                              | `start_scratch` clears `git rev-parse --local-env-vars`      |
| Global git config changed test results                                                              | `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`    |
| Scope warnings were printed and ignored                                                             | The test runner and hook tests fail on them                  |

## Why

- **Lint and tests are what the rest of this project trusts,** so a false pass costs more than a false alarm.
- **Grep-style checks can't fully parse zsh.** Writing down what they got wrong shows where the next gap is likely to be.

## Consequences

- **One check can't be reliable, and stays with review:** whether `$'...'` sits inside double quotes, which the masked views can't tell apart.
- **Not added as lint rules:** requiring a check on every external command, which would flag nearly every line, and requiring tests to clear git's variables, which one helper file already does.

## Not verified

- Nothing here has run against the imported tool, which arrives in [issue 2](https://github.com/jjloneman/pam-duo-macos-updater/issues/2).
