---
type: Reference
title: Zsh scripting rules
description: Every code and lint rule this repo uses for zsh, each marked Tested, Source or Inference with its date, plus which linters support zsh.
tags: [linting, shell, zsh]
status: stable
generated: { by: claude-code/claude-opus-5-5, at: 2026-11-07T03:20:57Z }
verified: { by: human:jjloneman, at: 2026-11-11T22:29:32Z }
sources:
  - id: chazelas-arith
    resource: https://www.zsh.org/mla/workers/2021/msg01243.html
    title: Chazelas on zsh arithmetic and command injection, zsh-workers
  - id: google-shell
    resource: https://google.github.io/styleguide/shellguide.html
    title: Google Shell Style Guide
  - id: mvdan-sh
    resource: https://github.com/mvdan/sh/blob/master/CHANGELOG.md
    title: mvdan/sh changelog
  - id: mvdan-sh-1405
    resource: https://github.com/mvdan/sh/issues/1405
    title: mvdan/sh issue 1405, quoted count corrupted
  - id: schaefer-errexit
    resource: https://www.zsh.org/mla/workers/2022/msg01247.html
    title: Schaefer on ERR_EXIT, zsh-workers
  - id: shellcheck-809
    resource: https://github.com/koalaman/shellcheck/issues/809#issuecomment-3590684154
    title: ShellCheck issue 809, maintainer comment on zsh support
  - id: shellcheck-sc1071
    resource: https://www.shellcheck.net/wiki/SC1071
    title: ShellCheck wiki, SC1071
  - id: shuck
    resource: https://github.com/ewhauser/shuck
    title: shuck
  - id: zsh-lint
    resource: https://github.com/z-shell/zsh-lint
    title: zsh-lint
  - id: zsh-news
    resource: https://raw.githubusercontent.com/zsh-users/zsh/master/NEWS
    title: Zsh NEWS, including 5.10 changes
  - id: zsh-options
    resource: https://zsh.sourceforge.io/Doc/Release/Options.html
    title: Zsh manual, Options
  - id: zsh-params
    resource: https://raw.githubusercontent.com/zsh-users/zsh/zsh-5.9/Doc/Zsh/params.yo
    title: Zsh 5.9 manual source, Parameters
  - id: zsh-readme
    resource: https://raw.githubusercontent.com/zsh-users/zsh/master/README
    title: Zsh README, incompatibilities in 5.10
  - id: zshellcheck
    resource: https://github.com/afadesigns/zshellcheck
    title: zshellcheck
---

# Zsh scripting rules

The rules this repo's zsh follows, and what each one rests on. Read this before changing `AGENTS.md`'s conventions or `scripts/lint.zsh`.

## How to read the evidence

- **Tested:** run on 2026-11-06 with `/bin/zsh -f` (zsh 5.9, macOS 27.2, arm64), in a temp folder under `/tmp`. Outcomes are what was printed.
- **Source:** a cited document says so, read on 2026-11-06.
- **Inference:** reasoning or a project choice, with neither behind it, as of 2026-11-06.

Zsh's development NEWS says 5.10 refines `ERR_EXIT` and `ERR_RETURN` [zsh-news], and its README lists changes to `always`, `source` and `&&` / `||` [zsh-readme]. Rerun the error tests before adopting it.

## Which linters support zsh

As of 2026-11-06. None of the third-party tools below were run for this record.

| Tool                 | Zsh support                                | Use here                    | Basis                                                              |
| :------------------- | :----------------------------------------- | :-------------------------- | :----------------------------------------------------------------- |
| ShellCheck           | None, and rejects zsh shebangs             | Advisory at most            | Source [shellcheck-sc1071]; maintainer "unlikely" [shellcheck-809] |
| `zsh -n`             | Grammar only                               | Required, by exit status    | Tested                                                             |
| `prettier-plugin-sh` | Formats with `LangZsh`, with the bug below | Required formatter          | Tested                                                             |
| shfmt                | Since 3.13.0, "not complete"               | Skipped, a second formatter | Source [mvdan-sh]                                                  |
| zsh-lint             | Zsh only, 38 stars                         | Not a CI gate               | Source [zsh-lint]; capabilities are its own claim                  |
| zshellcheck          | Zsh only, 52 stars, created 2025-11        | Not a CI gate               | Source [zshellcheck]; capabilities are its own claim               |
| shuck                | Claims zsh, 167 stars, created 2026-04     | Not a CI gate               | Source [shuck]; capabilities are its own claim                     |

- **`--shell=bash` isn't a real check:** it reviews a different language (Inference). One earlier trial of ShellCheck 0.11.0 this way on 2026-11-06 gave 26 findings on a 1,389-line script, 3 useful and 22 false alarms. It wasn't rerun for this record.
- **What this repo runs:**
  1. `zsh -d -f -n +o shortloops` on every file.
  2. The formatter.
  3. `scripts/lint.zsh`, for the rules below.
  4. Tests under `warn_create_global` and `warn_nested_var`, which only warn on lines that run (Inference).

### Formatter bug

- **Tested, with `prettier-plugin-sh` 0.20.2, `sh-syntax` 0.7.0 and Prettier 3.9.10, under `LangZsh`:**
  - Corrupted: `"$#"` becomes `"$"`, `x="$#"` becomes `x="$"`, and `"count $# and $#"` loses its last `#`.
  - Not corrupted: `"$# args"`, `"${#}"`, `"a ${#} b"`, `(($# != 3))`, `[[ $# -eq 1 ]]`, `"$?"`, `"$@"`, `"$$"`, `"$!"`, `"$*"` and `"$#name"`.
  - Only these forms were tried.
- **Why it's dangerous (Tested):** the corrupted result still passes `zsh -n`, and `"$"` prints a literal `$` instead of the count.
- **The parser is incomplete too (Tested 2026-11-06):** it rejected `${~name}`, glob subscripts such as `${(k)a[(R)*x*]}`, and a `[[ ]]` alternation with escaped parentheses, all valid zsh. Those forms are rewritten, so no file is excluded from formatting. `sh-syntax` 0.8.3 accepts the first two, and still rejects the third (Tested 2026-11-09).
- **The rule:** the argument count is always `${#}`, and lint rejects the short form outside single quotes and comments. A fixture test catches a formatter upgrade bringing the bug back.
- **Upstream:** shfmt had the same bug, closed in its 3.14.1 release [mvdan-sh-1405] [mvdan-sh].
  - `sh-syntax` 0.8.3 no longer corrupts these forms (Tested 2026-11-09, calling `sh-syntax` directly).
  - `prettier-plugin-sh` 0.20.2 still depends on `sh-syntax` `^0.7.0`, so it keeps the bug until it updates. Tracked in [issue 9](https://github.com/jjloneman/pam-duo-macos-updater/issues/9).

## Entry points

Every entry point starts like this:

```zsh
#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent warn_create_global warn_nested_var
unset CDPATH
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r
```

- **The header runs as written.** A later unset name stopped the script with exit 1 (Tested). No source prescribes it, so the choice of options is Inference.
- **`#!/bin/zsh -f` on executable scripts; none in `lib/`.**
  - With a `.zshenv` in `ZDOTDIR`: running the script directly didn't run it, `zsh script` did, and `/bin/zsh -f script` didn't (Tested). So a shebang is ignored when a script is passed by name, and launchd jobs and tests name `/bin/zsh -f`.
  - `/etc/zshenv` still runs under `-f` [zsh-options] (Source).
  - `lib/*.zsh` files are sourced, so a shebang or execute bit there would be misleading (Inference).
- **`emulate -R zsh`, not plain `emulate`:** after `setopt no_case_match`, plain `emulate zsh` left it set, and `-R` reset it (Tested). So options go after it.
- **`unset CDPATH`:** with `CDPATH=/usr` exported, `cd lib` silently went to `/usr/lib`, and after unsetting it failed (Tested).
- **Pinned `path=` and `hash -r`:** a fake tool earlier on `path` ran, then wasn't found once `path` was pinned and `hash -r` run (Tested).
- **Every `setopt` name must be real:** `setopt no_such_option` printed an error, gave status 1, and the script carried on (Tested). So lint checks the names.
- **No `err_exit`; failures are checked one by one:** Schaefer says a script should be correct without `-e`, which exists to uncover mistakes [schaefer-errexit] (Source). Using none is this project's choice (Inference).
- **No bare `emulate -L zsh`:** under `no_unset`, a function starting with it read an unset name as empty and kept running. `emulate -L zsh -o no_unset` stopped it, with exit 1 (Tested).

## Expansion and quoting

- **Variables are quoted and always braced, as in `"${name}"`:** with `module=pam_duo`, `"$module:loaded"` printed `pam_duooaded`, because `:l` is a modifier, and `"${module}:loaded"` printed `pam_duo:loaded` (Tested). With `foo=abc`, `"$foo[1]"` printed `a`, and `"${foo}[1]"` printed `abc[1]` (Tested).
- **Bare forms stay only for `$?` and `"$@"`, and `(( ))` uses plain names** (Inference, a project choice).
- **Modifiers and subscripts go inside the braces:** `"${pam_module_path:t}"` gave `pam_duo.so`, and `"${versions[1]}"` gave the first entry (Tested).
- **`${name:-}` only where unset is valid:** under `no_unset` it gave an empty string, while the plain form stopped the script (Tested).
- **The argument count is `${#}`:** see [Formatter bug](#formatter-bug). It gave the same count as the short form it replaces (Tested).
- **`print -r --`, never `echo`:** with `v='a\nb'`, `echo "${v}"` and plain `print` printed a newline, and `print -r --` printed `a\nb`. With `v=-n`, `echo` and plain `print` both printed nothing, and `print -r --` printed `-n` (Tested).
- **Quote URLs:** unquoted, `http://x/a?b=1` stopped the script with `no matches found` (Tested). `=ls` also became `/bin/ls` (Tested).
- **Unquoted `$(...)` splits:** a value `a b` gave two words in a `for`, unlike a plain unquoted variable (Tested).

### Special names

- **Never use zsh's special parameter names as variables** (Tested, and Source [zsh-params] for special attributes surviving `local`):
  - `local path` made `ls` fail with status 127, while `local -h path` didn't.
  - `local status=x` and `local LINENO=1` stopped the script: `read-only variable`.
  - `MODULE_PATH` is tied to `module_path`. Set to `/tmp/nowhere`, `zmodload zsh/datetime` failed.
- **Lint reads the list from zsh:** `${(k)parameters[(R)*special*]}` gave 104 names on this build, after `zmodload zsh/parameter` (Tested). The list changes between versions (Inference).

## Functions

- **Name arguments on the first line:** `local pam_module_path=${1} checksum=${2}`. Zsh has no named arguments (Inference).
- **Check `(( ${#} == n ))` before reading arguments.** With `no_unset` and a missing `${1}` (Tested):
  - `if f; then ...; else ...; fi` stopped the script with exit 1, and `else` never ran.
  - `print -r -- "out=[$(f)]"` printed `out=[]`, status 0, and carried on.
  - `x="$(f)"` gave status 1, and carried on.
  - `local y="$(f)"` gave status 0, and carried on.
  - With the count check first, `else` ran and the script continued.
- **Every function ends in an explicit `return`:** a function ending in `[[ a == b ]] && print x` returned 1 (Tested).
- **No `local x=$(cmd)`:** `local x=$(false)` gave status 0, and declaring first then assigning gave 1 (Tested). Google says the same [google-shell] (Source).
- **Every variable is declared:** `local`, `local -a`, `local -A`, `local -i`, `typeset -gr` or `typeset -g`. `warn_create_global` and `warn_nested_var` each warned on an undeclared write (Tested), but neither stopped the script (Tested).
- **`typeset -gr` for constants:** `readonly R=1` in a function was gone on return, and `typeset -gr G=2` stayed (Tested).
- **Loop variables are declared:** `for i in 1` in a function warned `scalar parameter i created globally`, and a `local j` first didn't (Tested).
- **`typeset_silent` is on:** without it, a repeated `local y` printed `y=1` into captured output, and with it the output was empty (Tested).
- **EXIT traps at the top level only:** a trap set in a function fired when that function ended. At the top level it fired at exit and kept `exit 7` (Tested).
- **`always` isn't used for cleanup:** a top-level `exit` inside the block skipped it (Tested).
- **Sourced files can stop silently:** a `no_unset` stop in a sourced file ended only that file. `source` returned 126 and the caller carried on (Tested). So check after `source`.

## Numbers

- **Values reach `(( ))` or `-gt` only after `[[ ${x} == <-> && ${#x} -le 18 ]]`.**
  - A value holding `name[$(cmd)1]` ran the command in `(( ))`, `[[ -gt ]]`, `typeset -i` and `$(( ))`, whenever `name` was an existing parameter, including the variable itself (Tested). A value read from a file did too (Tested). `$(cmd)` alone, or a `name` that didn't exist, didn't run it (Tested). Chazelas reports the same with `psvar[$(reboot)1]` [chazelas-arith] (Source).
  - The check rejected an empty value, `-1`, `1.5`, a trailing newline and the injection form, and took 18 digits (Tested).
  - A 20-digit value passed `<->` alone, warned `number truncated`, and went negative, which is why there's a length cap (Tested).
- **`(( ))` for numbers, `[[ ]]` for strings and files, never `[ ]`:** `[ a == a ]` stopped the script with `= not found` (Tested). Google prefers `[[ ]]` over `[` [google-shell] (Source).
- **`is-at-least` for versions:** as text, `3.10.0` sorted before `3.9.0`, and `is-at-least` compared them correctly (Tested).

## Paths and input

- **`cd` only to absolute paths, and checked:**
  - A failed `cd` gave status 1, and the script carried on in the same folder (Tested).
  - `--` doesn't protect it: with a folder named `-2` present, `cd -- -2` failed with `no such entry in dir stack`, and `cd ./-2` worked (Tested).
- **`"${d:?}"` before any destructive path:** with an empty `d`, `"${d}/lib"` was `/lib`, and `"${d:?}/lib"` stopped with status 1 in a subshell. It doesn't catch `d=/`, which gave `//lib` (Tested).
- **`IFS= read -r`:**
  - Plain `read` turned `  a\b  ` into `ab`, `-r` into `a\b`, and `IFS= read -r` kept it all (Tested).
  - A last line with no newline was dropped from a `while` loop, and `|| [[ -n ${line} ]]` kept it (Tested).
- **`*(N)` only where empty is valid:** a glob with no match stopped the script on a builtin, and skipped an external command with status 1 while the script carried on. `(N)` gave 0 items (Tested).
- **Splitting lines:**
  - `lines=(${(f)"$(cmd)"})` gave 0 items on empty output, and dropped a blank line (Tested).
  - `"${(@f)output}"` kept the blank line, but gave 1 empty item on empty output (Tested). Choose on purpose.
- **Reads past an array's end stop the script under `no_unset`:** `${a[5]}` on a 1-item array gave exit 1 (Tested).
- **Long options where a tool has them, such as `curl --fail`:** they're clearer to review (Inference).

## Pipelines and patterns

- **No `grep -q` in a pipeline:** under `pipe_fail`, a writer of 200,000 lines into `grep -q` gave status 141 even though it matched, and `yes | head -n1` gave 141 too (Tested). A small writer may finish first, so the failure depends on timing (Inference).
- **No `=~`:**
  - Under plain `/bin/zsh -f`, `[[ abc =~ b ]]` worked, loading `zsh/regex` from a root-owned file (Tested). So the earlier report that the module fails to load on macOS didn't reproduce.
  - With `MODULE_PATH` set to a file path, as the earlier script's own constant was, `=~` failed to load the module, printed an error and stopped with exit 2 (Tested). That may be what the earlier failure was (Inference).
  - The rule stays because it adds a run-time module load that a setting can break, and `[[ == ]]` patterns are enough (Inference).
- **Every `case` has a catch-all that fails loudly,** unless it ignores input on purpose and says why: a `case` with no match gave status 0 and no output (Tested).

## Code shape

These are project choices, not consensus (Inference, 2026-11-06). Google's guide is the closest published style, and it's for Bash [google-shell].

- **Semantic names:** functions read as what they do, booleans as questions starting with `are`, `can`, `did`, `does`, `has`, `have`, `is`, `should`, `was`, `were` or `will`, as the owner's TypeScript repos enforce, constants are `SCREAMING_SNAKE_CASE`, functions and locals are `snake_case`, and vague names such as `data`, `tmp`, `obj`, `val` and `res` are banned outside trivial scopes.
- **Named exit codes:** `EXIT_PROVEN`, `EXIT_REFUSED`, `EXIT_RESTORED`, `EXIT_RESTORED_AFTER_SIGNAL`, `EXIT_RESTORE_FAILED`, keeping their numbers.
- **Lexicographic order, ignoring case:** constants, functions, array entries, `case` branches, runs of `source` lines, `setopt` lists, plist keys and test helpers. `main` goes last, above the call that runs it, and a `case` catch-all goes last. Where order carries meaning, a comment above says why.
- **Spacing:** 80 columns, one blank line between functions, a blank line around every multi-line statement, and a blank line before a comment or `return` unless it's first in its block. The `return` padding matches ESLint's `padding-line-between-statements` in the owner's TypeScript repos.
- **Comments:** one of three lines or more opens with a prose sentence, then `-` bullets. Bullets may sit together when each fits on one line; once any wraps, a blank `#` line separates every bullet. Every function has a doc comment.
- **Tests:** `describe "<unit>"` and `test_case "<scenario>"`, with `# Given -`, `# When -` and `# Then -` phase comments, the shape of the owner's vitest tests.
- **Limits:** 300 lines per file and 40 per function, as proposed in issue 1.
  - The helper in `libexec/` may run to 450 lines, because it must stay one self-contained file and the spacing rules alone add about 100 blank lines. Converted, it was 436 lines on 2026-11-11 (Tested, with `wc -l`).
- **No short forms, `function` or backticks:** Google says `$(command)` over backticks, and that `function` is extraneous with `()` [google-shell] (Source). `+o shortloops` rejected `for i in 1; print $i`, but accepted `if [[ a == a ]] { print x }` and `for i (1) { print $i }`, so lint must catch those (Tested).

## Lint rules

`scripts/lint.zsh` enforces these. Each links to its evidence above, or says what it rests on.

- **Shebangs:** `#!/bin/zsh -f` on executable scripts, and no shebang or execute bit in `lib/` ([Entry points](#entry-points)).
- **No `grep -q` in a pipeline, and no `=~`** ([Pipelines and patterns](#pipelines-and-patterns)).
- **File and function limits, doc comments, 80 columns, sorted code and blank lines** ([Code shape](#code-shape)).
- **The helper sources nothing:** see [Why the helper is root-owned](../decisions/root-owned-helper.md) (Inference).
- **No `local x=$(cmd)`** ([Functions](#functions)).
- **No bare `$name` or `$1`, and no short count form,** outside single quotes and comments ([Expansion and quoting](#expansion-and-quoting), [Formatter bug](#formatter-bug)).
- **No special parameter names as variables, with the list read from zsh** ([Special names](#special-names)).
- **Every `setopt` name is real** ([Entry points](#entry-points)).
- **No `echo`, backticks, `function`, `[ ]`, short forms, bare `emulate -L`, or `read` without `-r`** (sections above).
- **Bash-only forms rejected by name:**
  - `mapfile`, `readarray`, `shopt` and `compgen` gave status 127 (Tested).
  - `read -a` gave `bad option`, and `read -p` gave `no coprocess` (Tested).
  - `$BASH_SOURCE` and `$FUNCNAME` read as empty, and `$BASH_SOURCE` stopped the script under `no_unset` (Tested).
- **`zsh -d -f -n +o shortloops` on every file, judged by exit status, knowing it only checks grammar** (Tested):
  - It rejected an unbalanced quote, a missing `fi`, and `${x,,}` in a top-level command.
  - It accepted a misspelled command, `mapfile`, an unset name, a bad `setopt` name, and `${x,,}` inside a function or `if`.
- **Banned vague names, and undeclared variables through `warn_create_global`** ([Code shape](#code-shape), [Functions](#functions)).
- **Every branch is an `if`:** a `DEBUG` trap fired once for `false && print never`, so the line would count as covered though `print` never ran. An `if` body fired on its own line when it ran, and didn't when it was skipped (Tested). It can't see the empty false side of an `if`, so tests assert those (Inference).
- **A blank line before `return`, and sorted runs of `source` lines** ([Code shape](#code-shape)).
- **Test files name a unit and mark each test case's When and Then** ([Code shape](#code-shape)).
- **OKF frontmatter is present, and every record is listed in its `index.md`** (Inference, keeps the bundles usable).
- **Temporary exemption:** files in `scripts/lint-legacy.txt` skip the style rules until issues 3 and 4 convert them, and an entry naming a missing file fails lint. The list and its code are deleted at the end of issue 4 (Inference).

Left to review, because a script can't judge them (Inference):

- Whether a name really describes its value.
- Whether a boolean's name starts with a question word.
- Whether a failure-modes table is complete.
- Whether a value was checked before reaching `(( ))`, which the fault sweep tests too.

## Failure handling

These come from the project's plan, not a test (Inference, 2026-11-06).

- **Each module's failure-modes table covers** every external command, file operation, network call, parse and signal, including:
  - Non-zero exit.
  - Empty or malformed output that looks like success.
  - Missing, unwritable or full storage.
  - Network failure, partial downloads and rate limits.
  - Concurrent runs and leftover markers.
  - No terminal, a missing tool, or a path with spaces.
- **Anything unexpected fails loudly,** and the helper restores or refuses rather than guessing.
- **New failures found later get a row and a test.**

## Not verified

- **An earlier claim dropped:** a `no_unset` stop under `zsh -c` exiting 0 didn't reproduce. Five forms, inside and outside `if` and functions, all exited 1 on 2026-11-06, so nothing here relies on it. The mechanism behind the earlier report is unknown.
- **An earlier claim not reproduced:** `zsh -n` printing a spurious error for `$(< "$file")` while exiting 0. Nine forms printed nothing on 2026-11-06. Judging by exit status stays, as the only thing a script can rely on (Inference).
- **Third-party linters:** none were run, and ShellCheck's earlier trial wasn't repeated.
- **shfmt:** not run. The closing of its bug rests on the upstream issue and changelog.
- **The formatter:** only the forms listed were tried.
- **Signals:** EXIT traps on signals, `TRAPINT` and `zsystem flock` weren't exercised. Issue 4's signal sweep covers the helper.
- **`is-at-least`:** run only on dotted versions, not on empty or malformed values.
- **`/etc/zshenv` under `-f`:** rests on the manual, and wasn't tested because that needs editing a system file.
- **`sudo` and `HOME`:** whether macOS keeps `HOME`, and so runs a user's `.zshenv` as root without `-f`, is unconfirmed.
- **Other versions:** nothing was run on zsh 5.10, other macOS versions, or Intel Macs.
