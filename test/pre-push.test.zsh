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

# Checks clean commits, deleted refs and commits before lint all pass.
check_allowed_pushes() {
  local clean_commit plain_commit
  local -i hook_status

  new_scratch_repo
  clean_commit="$(git_setup rev-parse HEAD)"
  run_pre_push origin "" \
    "refs/heads/a ${clean_commit} refs/heads/a ${ZERO_SHA}" \
    "refs/tags/v1 ${clean_commit} refs/tags/v1 ${ZERO_SHA}"
  hook_status="$?"
  expect_equal "two refs sharing a commit pass" "0" "${hook_status}"
  run_pre_push origin "" "(delete) ${ZERO_SHA} refs/heads/a ${clean_commit}"
  hook_status="$?"
  expect_equal "a deleted ref passes" "0" "${hook_status}"
  new_plain_repo
  print -r -- "notes" > notes.md
  git_setup add -- notes.md
  git_setup commit --quiet --no-verify -m notes
  plain_commit="$(git_setup rev-parse HEAD)"
  run_pre_push origin "" "refs/tags/v0 ${plain_commit} refs/tags/v0 ${ZERO_SHA}"
  hook_status="$?"
  expect_equal "a commit before lint is skipped" "0" "${hook_status}"
  return 0
}

# Checks a bad commit is refused under a clean tip, from a clean tree, or
# when only another remote holds it, and that removing lint is refused.
check_bad_commits() {
  local bad_commit clean_commit fixed_commit removal_commit
  local -i hook_status

  new_scratch_repo
  clean_commit="$(git_setup rev-parse HEAD)"
  bad_commit="$(commit_test_line "echo hello" bad)"
  git_setup checkout --quiet "${clean_commit}" -- scripts/test.zsh
  git_setup commit --quiet --no-verify -m fix
  fixed_commit="$(git_setup rev-parse HEAD)"
  run_pre_push origin "" \
    "refs/heads/a ${fixed_commit} refs/heads/a ${clean_commit}"
  hook_status="$?"
  expect_equal "a bad middle commit is refused" "1" "${hook_status}"
  git_setup update-ref refs/remotes/fork/a "${fixed_commit}"
  run_pre_push origin "" "refs/heads/b ${fixed_commit} refs/heads/b ${ZERO_SHA}"
  hook_status="$?"
  expect_equal "a fork's commits are still linted" "1" "${hook_status}"
  git_setup rm --quiet -- scripts/lint.zsh
  git_setup commit --quiet --no-verify -m "remove lint"
  removal_commit="$(git_setup rev-parse HEAD)"
  run_pre_push origin "" \
    "refs/heads/a ${removal_commit} refs/heads/a ${fixed_commit}"
  hook_status="$?"
  expect_equal "removing lint is refused" "1" "${hook_status}"
  return 0
}

# Checks a real `git push --follow-tags` of a branch and its tag passes, and
# that commits a bare URL already holds aren't linted again.
check_real_pushes() {
  local hook_output remote_path
  local -i push_status

  new_scratch_repo
  remote_path="${PWD:h}/remote.${PWD:t}.git"
  git_setup init --quiet --bare -- "${remote_path}"
  git_setup tag --annotate -m v1 v1
  run_watching_warnings git_setup -c core.hooksPath="${REPO_ROOT}/.githooks" \
    push --quiet --follow-tags -- "${remote_path}" HEAD:refs/heads/main \
    > /dev/null 2>&1
  push_status="$?"
  expect_equal "a branch and its tag push together" "0" "${push_status}"
  commit_test_line "# A note." note > /dev/null
  hook_output="$(run_pre_push "${remote_path}" "${remote_path}" \
    "refs/heads/b $(git_setup rev-parse HEAD) refs/heads/b ${ZERO_SHA}" 2>&1)"
  expect_contains "only the new commit is linted" "lint: 1" "${hook_output}"
  return 0
}

# Checks an unknown remote tip falls back to everything the remote lacks.
check_unknown_remote_tip() {
  local clean_commit
  local -i hook_status
  local unknown_sha=1111111111111111111111111111111111111111

  new_scratch_repo
  clean_commit="$(git_setup rev-parse HEAD)"
  run_pre_push origin "" \
    "refs/heads/a ${clean_commit} refs/heads/a ${unknown_sha}"
  hook_status="$?"
  expect_equal "an unknown remote tip falls back" "0" "${hook_status}"
  return 0
}

# Commits a change to scripts/test.zsh, without hooks, and prints its sha.
commit_test_line() {
  print -r -- "${1}" >> scripts/test.zsh
  git_setup add -- scripts/test.zsh
  git_setup commit --quiet --no-verify -m "${2}"
  git_setup rev-parse HEAD
  return "$?"
}

# Feeds ref lines to the real pre-push hook, after its remote name and URL.
run_pre_push() {
  if ! is_in_scratch; then
    abort_setup "pre-push ran outside the scratch folder"
  fi

  local remote_name="${1}" remote_url="${2}"

  shift 2
  print -rl -- "$@" | run_watching_warnings \
    "${REPO_ROOT}/.githooks/pre-push" "${remote_name}" "${remote_url}" \
    > /dev/null
  return "$?"
}

# Runs every check and reports the totals.
main() {
  check_allowed_pushes
  check_bad_commits
  check_real_pushes
  check_unknown_remote_tip
  check_no_hook_warnings

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
