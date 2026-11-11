#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent \
  warn_create_global warn_nested_var
unset CDPATH
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r

# Proves pre-push lints every pushed commit, not the working tree.

typeset -gr REPO_ROOT="${0:A:h:h}"
typeset -gr ZERO_SHA=0000000000000000000000000000000000000000
typeset -g SCRATCH_ROOT=""

source "${0:A:h}/helpers.zsh"
source "${0:A:h}/hook_helpers.zsh"
source "${0:A:h}/pre_push_helpers.zsh"

# Tests that clean commits and deleted refs pass.
test_allowed_pushes() {
  local clean_commit
  local -i hook_status

  describe "pre-push, with commits that pass"
  test_case "passes two refs sharing a commit"

  # Given - a clean commit, pushed as a branch and as a tag
  new_scratch_repo
  clean_commit="$(git_setup rev-parse HEAD)"

  # When - running the hook on both refs
  run_pre_push origin "" \
    "refs/heads/a ${clean_commit} refs/heads/a ${ZERO_SHA}" \
    "refs/tags/v1 ${clean_commit} refs/tags/v1 ${ZERO_SHA}"
  hook_status="$?"

  # Then - it passes
  expect_equal "status" "0" "${hook_status}"

  test_case "passes a deleted ref"

  # When - running the hook on a ref being deleted
  run_pre_push origin "" "(delete) ${ZERO_SHA} refs/heads/a ${clean_commit}"
  hook_status="$?"

  # Then - it passes
  expect_equal "status" "0" "${hook_status}"

  return 0
}

# Tests a bad commit is refused under a clean tip.
test_bad_commits() {
  local -i hook_status

  describe "pre-push, with a bad commit"
  test_case "refuses a bad middle commit"

  # Given - a bad commit, then a fix, so the tip is clean
  new_fixed_repo

  # When - running the hook on the push of the fix
  run_pre_push origin "" \
    "refs/heads/a ${FIXED_COMMIT} refs/heads/a ${CLEAN_COMMIT}"
  hook_status="$?"

  # Then - it refuses
  expect_equal "status" "1" "${hook_status}"

  return 0
}

# Tests a bad commit another remote holds is still linted, and removing lint
# is refused.
test_bad_commits_elsewhere() {
  local removal_commit
  local -i hook_status

  describe "pre-push, with a bad commit"
  test_case "lints commits another remote already holds"

  # Given - a fork that holds the fix, and a new branch to push
  new_fixed_repo
  git_setup update-ref refs/remotes/fork/a "${FIXED_COMMIT}"

  # When - running the hook on the new branch
  run_pre_push origin "" \
    "refs/heads/b ${FIXED_COMMIT} refs/heads/b ${ZERO_SHA}"
  hook_status="$?"

  # Then - it refuses, as the fork's commits are still linted
  expect_equal "status" "1" "${hook_status}"

  test_case "refuses a commit that removes lint"

  # Given - a commit that removes scripts/lint.zsh
  new_fixed_repo
  git_setup rm --quiet -- scripts/lint.zsh
  git_setup commit --quiet --no-verify -m "remove lint"
  removal_commit="$(git_setup rev-parse HEAD)"

  # When - running the hook on it
  run_pre_push origin "" \
    "refs/heads/a ${removal_commit} refs/heads/a ${FIXED_COMMIT}"
  hook_status="$?"

  # Then - it refuses
  expect_equal "status" "1" "${hook_status}"

  return 0
}

# Tests that a commit before lint existed is skipped.
test_commit_before_lint() {
  local plain_commit
  local -i hook_status

  describe "pre-push, with commits that pass"
  test_case "skips a commit before lint"

  # Given - a commit in a repo that has no lint
  new_plain_repo
  print -r -- "notes" > notes.md
  git_setup add -- notes.md
  git_setup commit --quiet --no-verify -m notes
  plain_commit="$(git_setup rev-parse HEAD)"

  # When - running the hook on it
  run_pre_push origin "" "refs/tags/v0 ${plain_commit} refs/tags/v0 ${ZERO_SHA}"
  hook_status="$?"

  # Then - it passes
  expect_equal "status" "0" "${hook_status}"

  return 0
}

# Tests that no hook run printed a zsh scope warning.
test_no_hook_warnings() {
  describe "pre-push, across every test"
  test_case "prints no zsh warnings"

  # When/Then - the warnings file the runs above fill is empty
  check_no_hook_warnings

  return 0
}

# Tests a real `git push --follow-tags` of a branch and its tag passes, and
# that commits a bare URL already holds aren't linted again.
test_real_pushes() {
  local hook_output

  describe "pre-push, on a real git push"
  test_case "pushes a branch and its tag together"

  # When - pushing a branch and its tag
  push_branch_and_tag

  # Then - the push succeeds
  expect_equal "status" "0" "${PUSH_STATUS}"

  test_case "lints only the new commit"

  # Given - a branch and tag already pushed, and one new commit
  push_branch_and_tag
  commit_test_line "# A note." note > /dev/null

  # When - running the hook on the new commit, with the bare URL as the remote
  hook_output="$(run_pre_push "${REMOTE_PATH}" "${REMOTE_PATH}" \
    "refs/heads/b $(git_setup rev-parse HEAD) refs/heads/b ${ZERO_SHA}" 2>&1)"

  # Then - it lints just that one
  expect_contains "message" "lint: 1" "${hook_output}"

  return 0
}

# Tests an unknown remote tip falls back to everything the remote lacks.
test_unknown_remote_tip() {
  local clean_commit
  local -i hook_status
  local unknown_sha=1111111111111111111111111111111111111111

  describe "pre-push, with an unknown remote tip"
  test_case "falls back to everything the remote lacks"

  # Given - a clean commit
  new_scratch_repo
  clean_commit="$(git_setup rev-parse HEAD)"

  # When - running the hook with a remote tip the repo doesn't have
  run_pre_push origin "" \
    "refs/heads/a ${clean_commit} refs/heads/a ${unknown_sha}"
  hook_status="$?"

  # Then - it passes
  expect_equal "status" "0" "${hook_status}"

  return 0
}

# Runs every test and reports the totals.
main() {
  test_allowed_pushes
  test_bad_commits
  test_bad_commits_elsewhere
  test_commit_before_lint
  test_real_pushes
  test_unknown_remote_tip
  test_no_hook_warnings

  if ! cd -- "${REPO_ROOT}"; then
    abort_setup "could not return to ${REPO_ROOT}"
  fi

  finish_checks "pre-push"

  return "$?"
}

start_scratch
trap remove_scratch EXIT
main "$@"
exit "$?"
