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
source "${0:A:h}/pre_commit_helpers.zsh"

# Tests that a bracketed staged name doesn't re-stage the file it looks like.
test_bracketed_name() {
  local staged_names

  describe "pre-commit, with a bracketed file name"
  test_case "commits only the bracketed file"

  # Given - a.md edited but not staged, and a staged file named [a].md
  new_scratch_repo
  print -r -- "first" > a.md
  git_setup add -- a.md
  git_setup commit --quiet --no-verify -m a
  print -r -- "unfinished" >> a.md
  print -r -- "new" > "[a].md"

  # The test's own add needs a literal name too, or it stages a.md itself.
  GIT_LITERAL_PATHSPECS=1 git_setup add -- "[a].md"

  # When - running the hook
  run_hook
  staged_names="$(git_setup diff --cached --name-only)"

  # Then - it passes, and only the bracketed file is staged
  expect_equal "status" "0" "${HOOK_STATUS}"
  expect_equal "staged names" "[a].md" "${staged_names}"

  return 0
}

# Tests that deleting a file lint needs is refused.
test_deleted_rule_file() {
  describe "pre-commit, with a rule file deleted"
  test_case "still lints a delete-only commit"

  # Given - a commit that only deletes a lint rule file
  new_scratch_repo
  git_setup rm --quiet -- scripts/lint/rules_banned.zsh

  # When - running the hook
  run_hook

  # Then - it refuses, as lint can't run
  expect_equal "status" "2" "${HOOK_STATUS}"

  return 0
}

# Tests that a failed re-stage or formatter stops the commit and says why.
test_failures_stop() {
  describe "pre-commit, with a failing re-stage or formatter"
  test_case "refuses when the re-stage fails"

  # Given - a staged file, and an index lock held during the run
  new_scratch_repo
  stage_notes

  # When - running the hook
  STUB_HOLD_INDEX=1 run_hook

  # Then - it refuses
  expect_equal "status" "1" "${HOOK_STATUS}"

  # Cleanup
  rm -f -- .git/index.lock

  test_case "refuses when the formatter fails"

  # Given - a staged file, and a formatter that fails after rewriting it
  new_scratch_repo
  stage_notes

  # When - running the hook
  STUB_FAIL=1 run_hook

  # Then - it refuses, and names what it rewrote
  expect_equal "status" "1" "${HOOK_STATUS}"
  expect_contains "message" "notes.md" "${HOOK_OUTPUT}"

  return 0
}

# Tests that a reformatted file is re-staged and the commit allowed.
test_format_restages() {
  local staged_text

  describe "pre-commit, with a file the formatter changes"
  test_case "re-stages the reformat and passes"

  # Given - a staged file the formatter will rewrite
  new_scratch_repo
  stage_notes

  # When - running the hook
  run_hook
  staged_text="$(git_setup show :notes.md)"

  # Then - it passes, and the staged copy is the reformatted one
  expect_equal "status" "0" "${HOOK_STATUS}"
  expect_contains "staged text" "formatted" "${staged_text}"

  return 0
}

# Tests that a commit is refused when the index has no lint to run.
test_missing_lint() {
  describe "pre-commit, with no lint in the index"
  test_case "refuses the commit and says why"

  # Given - a staged file in a repo with no lint
  new_plain_repo
  stage_notes

  # When - running the hook
  run_hook

  # Then - it refuses, naming the missing script
  expect_equal "status" "1" "${HOOK_STATUS}"
  expect_contains "message" "scripts/lint.zsh" "${HOOK_OUTPUT}"

  return 0
}

# Tests that no hook run printed a zsh scope warning.
test_no_hook_warnings() {
  describe "pre-commit, across every test"
  test_case "prints no zsh warnings"

  # When/Then - the warnings file the runs above fill is empty
  check_no_hook_warnings

  return 0
}

# Tests that nothing staged passes, and a partly staged file is refused.
test_nothing_or_partly_staged() {
  describe "pre-commit, with nothing or part of a file staged"
  test_case "passes with nothing staged"

  # Given - a repo with nothing staged
  new_plain_repo

  # When - running the hook
  run_hook

  # Then - it passes
  expect_equal "status" "0" "${HOOK_STATUS}"

  test_case "refuses a partly staged file"

  # Given - a staged file with a further edit not staged
  stage_notes
  print -r -- "unfinished" >> notes.md

  # When - running the hook
  run_hook

  # Then - it refuses, naming the file
  expect_equal "status" "1" "${HOOK_STATUS}"
  expect_contains "message" "notes.md" "${HOOK_OUTPUT}"

  return 0
}

# Tests that `git commit -- <path>` asks for a retry, which then commits.
test_partial_commit() {
  local status_text

  describe "pre-commit, on git commit -- <path>"
  test_case "asks for a retry when the formatter changes the file"

  # Given - a committed file with a new edit
  new_edited_notes_repo

  # When - committing the path
  run_partial_commit

  # Then - the commit is refused, for a retry
  expect_equal "status" "1" "${HOOK_STATUS}"

  test_case "commits on the retry and leaves the file clean"

  # Given - a committed file with a new edit, and a first commit that asked
  # for a retry
  new_edited_notes_repo
  run_partial_commit

  # When - committing the path again
  run_partial_commit
  status_text="$(git_setup status --porcelain -- notes.md)"

  # Then - it commits, and the file is clean
  expect_equal "status" "0" "${HOOK_STATUS}"
  expect_equal "file status" "" "${status_text}"

  return 0
}

# Tests that a staged lint finding blocks the commit, and an untracked one
# doesn't.
test_staged_findings() {
  describe "pre-commit, with lint findings"
  test_case "refuses a staged finding"

  # Given - a staged script that breaks a lint rule
  new_scratch_repo
  print -r -- "echo hello" >> scripts/test.zsh
  git_setup add -- scripts/test.zsh

  # When - running the hook
  run_hook

  # Then - it refuses
  expect_equal "status" "1" "${HOOK_STATUS}"

  test_case "allows an untracked finding"

  # Given - an untracked script that breaks a rule, and a clean staged file
  new_scratch_repo
  mkdir -p bin
  print -r -- "echo hello" > bin/tool
  stage_notes

  # When - running the hook
  run_hook

  # Then - it passes
  expect_equal "status" "0" "${HOOK_STATUS}"

  return 0
}

# Tests that a staged symlink isn't handed to the formatter.
test_symlink_skipped() {
  local formatter_arguments

  describe "pre-commit, with a staged symlink"
  test_case "formats the regular file, not the symlink"

  # Given - a staged symlink, and a staged regular file
  new_scratch_repo
  ln -s scripts/lint.zsh link.zsh
  print -r -- "staged" > notes.md
  git_setup add -- link.zsh notes.md

  # When - running the hook
  run_hook
  formatter_arguments="$(< .git/stub-arguments)"

  # Then - it passes, and the formatter got only the regular file
  expect_equal "status" "0" "${HOOK_STATUS}"
  expect_missing "symlink" "link.zsh" "${formatter_arguments}"
  expect_contains "regular file" "notes.md" "${formatter_arguments}"

  return 0
}

# Runs every test and reports the totals.
main() {
  test_bracketed_name
  test_deleted_rule_file
  test_failures_stop
  test_format_restages
  test_missing_lint
  test_nothing_or_partly_staged
  test_partial_commit
  test_signal_cleanup
  test_staged_findings
  test_symlink_skipped
  test_no_hook_warnings

  if ! cd -- "${REPO_ROOT}"; then
    abort_setup "could not return to ${REPO_ROOT}"
  fi

  finish_checks "pre-commit"

  return "$?"
}

start_scratch
trap remove_scratch EXIT
main "$@"
exit "$?"
