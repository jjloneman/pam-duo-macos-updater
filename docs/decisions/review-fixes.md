---
type: Decision
title: Fixes found in review
description: What code reviews and the owner's review found wrong in this repo's lint, test and coverage tooling, what prevents each now, and how that's verified, so similar work can fail faster.
tags: [linting, review, testing, zsh]
status: stable
generated: { by: claude-code/claude-opus-5-5, at: 2026-11-11T06:48:05Z }
verified: { by: human:jjloneman, at: 2026-11-11T06:49:46Z }
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

| What failed                                                                                                          | What prevents it now                                                  |
| :------------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------- |
| A failed setup step left a hook test running in the real repo, as `cd -- ""` succeeds and stays put                  | `abort_setup` and a scratch-folder guard, and `unchecked_cd`          |
| Inherited `GIT_DIR` aimed a hook test at the real repo                                                               | `start_scratch` clears `git rev-parse --local-env-vars`               |
| Global git config changed test results                                                                               | `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`             |
| Scope warnings were printed and ignored                                                                              | The test runner and hook tests fail on them                           |
| Hook tests copied all of `scripts/`, so the legacy list named files their repos lacked, and lint failed every commit | `new_scratch_repo` copies only `scripts/lint.zsh` and `scripts/lint/` |

## Found in issue 2

Five reviews of the coverage tool, the test runner and the import found these. Coverage rows are verified by `test/coverage.test.zsh`, and the plist and sandbox rows by the harness.

| What failed                                                                                                                                                                              | What prevents it now                                                                                                                        |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------ |
| A line like `((waited += 1))` ended in `)`, read as a case pattern, and left the totals                                                                                                  | A line starting with `(` is always a statement                                                                                              |
| An empty branch such as `*) ;;` counted as a line the tests missed, though the trap never fires                                                                                          | `) ;;` endings are structure                                                                                                                |
| A real-only entry on a comment, or on a path that only ended like a traced file, passed silently                                                                                         | Each entry must name a traced path exactly, and a statement, or coverage fails                                                              |
| Coverage ran tests without the runner's scope-warning check                                                                                                                              | Coverage runs tests through `scripts/test.zsh`                                                                                              |
| Coverage had its own copy of lint's statement scanner                                                                                                                                    | It uses `load_views` from `scripts/lint/scan.zsh`, and joins lines ending in a pipe or `&&` itself, so lint's findings keep their own lines |
| The launchd plist put the repo's path into XML unescaped, so `&` or `<` in a folder broke it                                                                                             | `write_plist` escapes both paths                                                                                                            |
| An interrupted test run left its test files running, as background jobs in a script ignore SIGINT                                                                                        | `scripts/test.zsh` stops each file's whole process tree on INT or TERM, which `test/runner.test.zsh` checks                                 |
| The runner printed a file's stdout and stderr as two blocks                                                                                                                              | Each file has one log, with stderr copied to it through multios                                                                             |
| A `(pattern)` case line counted as a statement                                                                                                                                           | Inside a case block, a `(word)` line with nothing after it but `;;` is structure, and elsewhere it's a subshell                             |
| Coverage would insert zsh into a non-zsh script under `bin/` or `libexec/`                                                                                                               | Only `lib/*.zsh` and files with a zsh shebang are traced                                                                                    |
| Two harness runs at once shared one fixed sandbox and cleared each other's                                                                                                               | The harness makes its own with `mktemp`, and removes it on exit                                                                             |
| Test files started as background jobs inherited ignored SIGINT, so their signals acted differently than when run alone                                                                   | Each job restores INT and QUIT first, which `test/runner.test.zsh` checks                                                                   |
| A run stopped by TERM exited 130, as if interrupted                                                                                                                                      | TERM exits 143 and INT 130                                                                                                                  |
| The runner's interrupt check could send TERM before the traps were set                                                                                                                   | It waits for the slow test file to start                                                                                                    |
| A real-only line listed twice silently kept only the last reason                                                                                                                         | A repeated entry fails the run                                                                                                              |
| Once scratch repos stopped copying `scripts/test.zsh`, the pre-push "bad middle commit" setup couldn't make its fix commit, so it tested a bad tip, and a symlink test linked to nothing | The fix removes the file and stops loudly if it can't commit, and the symlink points at `scripts/lint.zsh`                                  |
| Imported comments renamed past 80 columns, with the files exempt from `line_width`                                                                                                       | Lint checks comment width in legacy files too, trailing comments included                                                                   |
| `test_shape` flagged prose starting with a phase word, and closed a test case at any `}`                                                                                                 | Near misses count only inside a test case, and only a `}` in column 0 ends one                                                              |
| A test function without `describe` reported failures under the previous one's unit                                                                                                       | Lint requires `describe` in each `test_*` function with test cases, unless it takes arguments as a shared case                              |
| A coverage test case reused the previous case's scratch copy                                                                                                                             | It copies a fresh fixture                                                                                                                   |
| A comment between two `source` lines let them go unsorted                                                                                                                                | Comment lines keep the run going                                                                                                            |
| A test case outside a `test_*` function was reported at line 0                                                                                                                           | Only `test_*` functions need `describe`                                                                                                     |
| The trailing-comment check flagged long legacy code with a short comment                                                                                                                 | Only a comment that starts before column 80 is measured                                                                                     |

- **No lint rule added:** each is a fault in one tool's logic rather than a pattern a rule could catch.

## Found in issue 15

A docs-only PR's CI run failed two harness checks, which passed on re-run.

| What failed                                                                                                                                                                                                                                   | What prevents it now                                                                                                       | Verified by                                                                                                                                                       |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The closing-terminal case waited only for the swapped marker to exist, but the helper writes it as `pending` before setting its trap and moving the module in, so CI compared too early and sent `HUP` that killed the helper with 129, not 4 | The case waits, for up to 30 seconds, until the marker holds this run's ID, and checks that it got there before signalling | Stalling the helper after `pending` failed the old wait every time and passes the new one, and 60 runs side by side under CPU load all passed (tested 2026-11-11) |

- **An `AGENTS.md` trap line was added** rather than a lint rule, because whether a wait proves a trap is set needs reading the code it waits on.

## Found in issue 17

Converting the helper took it off the legacy list, and `pnpm coverage` then failed although `pnpm check` passed.

| What failed                                                                                                                                                                                  | What prevents it now                                                                           | Verified by                                                                                              |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------- |
| Lint's test of the repo linted the traced scratch copy, where coverage inserts a 267-column trap as line 2 of each file, so the first converted file failed `line_width` only under coverage | Coverage exports `COVERAGE_REPO_ROOT`, and that test lints the untraced original when it's set | `pnpm coverage` failed on the converted helper before the change and passed after it (tested 2026-11-11) |

- **No lint rule added:** it was the test's choice of folder, not a pattern in the code.

## Why

- **Lint and tests are what the rest of this project trusts,** so a false pass costs more than a false alarm.
- **Grep-style checks can't fully parse zsh.** Writing down what they got wrong shows where the next gap is likely to be.

## Consequences

- **One check can't be reliable, and stays with review:** whether `$'...'` sits inside double quotes, which the masked views can't tell apart.
- **Not added as lint rules:** requiring a check on every external command, which would flag nearly every line, and requiring tests to clear git's variables, which one helper file already does.

## Not verified

- The issue 1 rows were found before the tool was imported. Only the issue 2 and issue 15 rows have run against it.
