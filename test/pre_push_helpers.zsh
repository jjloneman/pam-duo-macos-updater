# Commits, pushes and hook runs for the pre-push tests.
#
# - Sourced by `test/pre-push.test.zsh`, after `test/hook_helpers.zsh`, which
#   sets REPO_ROOT and ZERO_SHA first.

typeset -g CLEAN_COMMIT=""
typeset -g FIXED_COMMIT=""
typeset -gi PUSH_STATUS=0
typeset -g REMOTE_PATH=""

# Commits a change to scripts/test.zsh, without hooks, and prints its sha.
commit_test_line() {
  print -r -- "${1}" >> scripts/test.zsh
  git_setup add -- scripts/test.zsh
  git_setup commit --quiet --no-verify -m "${2}"
  git_setup rev-parse HEAD

  return "$?"
}

# Makes a scratch repo with a clean commit, a bad one, and a fix for it.
#
# - It sets CLEAN_COMMIT and FIXED_COMMIT, the first and last of the three.
new_fixed_repo() {
  local clean_commit fixed_commit

  new_scratch_repo
  clean_commit="$(git_setup rev-parse HEAD)"
  commit_test_line "echo hello" bad > /dev/null

  # The clean commit has no scripts/test.zsh, so the fix removes it again.
  if ! git_setup rm --quiet -- scripts/test.zsh; then
    abort_setup "could not remove scripts/test.zsh"
  fi

  if ! git_setup commit --quiet --no-verify -m fix; then
    abort_setup "could not commit the fix"
  fi

  fixed_commit="$(git_setup rev-parse HEAD)"
  typeset -g CLEAN_COMMIT="${clean_commit}" FIXED_COMMIT="${fixed_commit}"

  return 0
}

# Pushes a branch and its tag to a new bare remote through the real hook.
#
# - It sets REMOTE_PATH to the remote, and PUSH_STATUS to the push's status.
push_branch_and_tag() {
  local remote_path

  new_scratch_repo
  remote_path="${PWD:h}/remote.${PWD:t}.git"
  git_setup init --quiet --bare -- "${remote_path}"
  git_setup tag --annotate -m v1 v1
  run_watching_warnings git_setup -c core.hooksPath="${REPO_ROOT}/.githooks" \
    push --quiet --follow-tags -- "${remote_path}" HEAD:refs/heads/main \
    > /dev/null 2>&1
  typeset -gi PUSH_STATUS="$?"
  typeset -g REMOTE_PATH="${remote_path}"

  return 0
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
