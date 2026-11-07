#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent \
  warn_create_global warn_nested_var
unset CDPATH
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r

# Proves what the pre-commit hook refuses and allows, in scratch repos.

typeset -gr REPO_ROOT="${0:A:h:h}"
typeset -g SCRATCH_ROOT=""

source "${0:A:h}/helpers.zsh"
source "${0:A:h}/hook_helpers.zsh"

# Checks a staged lint finding blocks the commit, and an untracked one doesn't.
check_bad_staged_file() {
  local -i hook_status

  new_scratch_repo
  print -r -- "echo hello" >> scripts/test.zsh
  git_setup add -- scripts/test.zsh
  run_pre_commit > /dev/null 2>&1
  hook_status="$?"
  expect_equal "a staged finding is refused" "1" "${hook_status}"
  new_scratch_repo
  mkdir -p bin
  print -r -- "echo hello" > bin/tool
  print -r -- "staged" > notes.md
  git_setup add -- notes.md
  run_pre_commit > /dev/null 2>&1
  hook_status="$?"
  expect_equal "an untracked finding doesn't block" "0" "${hook_status}"
  return 0
}

# Checks a bracketed staged name doesn't re-stage the file it looks like.
check_bracketed_name() {
  local staged_names
  local -i hook_status

  new_scratch_repo
  print -r -- "first" > a.md
  git_setup add -- a.md
  git_setup commit --quiet --no-verify -m a
  print -r -- "unfinished" >> a.md
  print -r -- "new" > "[a].md"

  # The test's own add needs a literal name too, or it stages a.md itself.
  GIT_LITERAL_PATHSPECS=1 git_setup add -- "[a].md"
  run_pre_commit > /dev/null 2>&1
  hook_status="$?"
  expect_equal "a bracketed name commits" "0" "${hook_status}"
  staged_names="$(git_setup diff --cached --name-only)"
  expect_equal "only the bracketed file is staged" "[a].md" "${staged_names}"
  return 0
}

# Checks that deleting a file lint needs is refused.
check_deleted_rule_file() {
  local -i hook_status

  new_scratch_repo
  git_setup rm --quiet -- scripts/lint/rules_banned.zsh
  run_pre_commit > /dev/null 2>&1
  hook_status="$?"
  expect_equal "a delete-only commit is still linted" "2" "${hook_status}"
  return 0
}

# Checks a failed re-stage or formatter stops the commit and says why.
check_failures_stop() {
  local hook_output
  local -i hook_status

  new_scratch_repo
  print -r -- "staged" > notes.md
  git_setup add -- notes.md
  STUB_HOLD_INDEX=1 run_pre_commit > /dev/null 2>&1
  hook_status="$?"
  rm -f -- .git/index.lock
  expect_equal "a failed re-stage is refused" "1" "${hook_status}"
  new_scratch_repo
  print -r -- "staged" > notes.md
  git_setup add -- notes.md
  hook_output="$(STUB_FAIL=1 run_pre_commit 2>&1)"
  hook_status="$?"
  expect_equal "a failed formatter is refused" "1" "${hook_status}"
  expect_contains "it names what it rewrote" "notes.md" "${hook_output}"
  return 0
}

# Checks that a reformatted file is re-staged and the commit allowed.
check_format_restages() {
  local staged_text
  local -i hook_status

  new_scratch_repo
  print -r -- "staged" > notes.md
  git_setup add -- notes.md
  run_pre_commit > /dev/null 2>&1
  hook_status="$?"
  expect_equal "a clean commit passes" "0" "${hook_status}"
  staged_text="$(git_setup show :notes.md)"
  expect_contains "the reformat is re-staged" "formatted" "${staged_text}"
  return 0
}

# Checks that a commit is refused when the index has no lint to run.
check_missing_lint() {
  local hook_output
  local -i hook_status

  new_plain_repo
  print -r -- "staged" > notes.md
  git_setup add -- notes.md
  hook_output="$(run_pre_commit 2>&1)"
  hook_status="$?"
  expect_equal "no lint in the index is refused" "1" "${hook_status}"
  expect_contains "the refusal says why" "scripts/lint.zsh" "${hook_output}"
  return 0
}

# Checks nothing staged passes, and a partly staged file is refused.
check_nothing_or_partly_staged() {
  local hook_output
  local -i hook_status

  new_plain_repo
  run_pre_commit > /dev/null 2>&1
  hook_status="$?"
  expect_equal "nothing staged passes" "0" "${hook_status}"
  print -r -- "staged" > notes.md
  git_setup add -- notes.md
  print -r -- "unfinished" >> notes.md
  hook_output="$(run_pre_commit 2>&1)"
  hook_status="$?"
  expect_equal "a partly staged file is refused" "1" "${hook_status}"
  expect_contains "the refusal names the file" "notes.md" "${hook_output}"
  return 0
}

# Checks `git commit -- <path>` asks for a retry, which then leaves it clean.
check_partial_commit() {
  local status_text
  local -i first_status second_status

  new_scratch_repo
  print -r -- "first" > notes.md
  git_setup add -- notes.md
  git_setup commit --quiet --no-verify -m notes
  print -r -- "second" >> notes.md
  run_partial_commit > /dev/null 2>&1
  first_status="$?"
  expect_equal "a reformatted partial commit retries" "1" "${first_status}"
  run_partial_commit > /dev/null 2>&1
  second_status="$?"
  expect_equal "the retry commits" "0" "${second_status}"
  status_text="$(git_setup status --porcelain -- notes.md)"
  expect_equal "the file ends up clean" "" "${status_text}"
  return 0
}

# Checks a TERM signal mid-hook still removes the hook's export.
check_signal_cleanup() {
  local -a leftovers
  local hook_temp="${SCRATCH_ROOT}/hook-temp"
  local -i hook_pid

  new_scratch_repo
  mkdir -p -- "${hook_temp}"
  print -r -- "staged" > notes.md
  git_setup add -- notes.md
  TMPDIR="${hook_temp}/" STUB_SLEEP=1 PATH="${SCRATCH_ROOT}/stub:${PATH}" \
    "${REPO_ROOT}/.githooks/pre-commit" > /dev/null 2>&1 &
  hook_pid="$!"
  sleep 1
  kill -TERM "${hook_pid}"
  wait "${hook_pid}"
  leftovers=("${hook_temp}"/*(N))
  expect_equal "a signal still removes the export" "0" "${#leftovers}"
  return 0
}

# Checks a staged symlink isn't handed to the formatter.
check_symlink_skipped() {
  local formatter_arguments
  local -i hook_status

  new_scratch_repo
  ln -s scripts/test.zsh link.zsh
  print -r -- "staged" > notes.md
  git_setup add -- link.zsh notes.md
  run_pre_commit > /dev/null 2>&1
  hook_status="$?"
  expect_equal "a staged symlink commits" "0" "${hook_status}"
  formatter_arguments="$(< .git/stub-arguments)"
  expect_missing "the symlink isn't formatted" "link.zsh" \
    "${formatter_arguments}"
  expect_contains "the regular file is formatted" "notes.md" \
    "${formatter_arguments}"
  return 0
}

# Commits one path through the real hook, with the stub pnpm first on PATH.
run_partial_commit() {
  PATH="${SCRATCH_ROOT}/stub:${PATH}" run_watching_warnings git_setup \
    -c core.hooksPath="${REPO_ROOT}/.githooks" commit --quiet -m partial \
    -- notes.md
  return "$?"
}

# Runs every check and reports the totals.
main() {
  check_bad_staged_file
  check_bracketed_name
  check_deleted_rule_file
  check_failures_stop
  check_format_restages
  check_missing_lint
  check_nothing_or_partly_staged
  check_partial_commit
  check_signal_cleanup
  check_symlink_skipped
  check_no_hook_warnings
  cd -- "${REPO_ROOT}"
  finish_checks "pre-commit"
  return "$?"
}

start_scratch
trap remove_scratch EXIT
main "$@"
exit "$?"
