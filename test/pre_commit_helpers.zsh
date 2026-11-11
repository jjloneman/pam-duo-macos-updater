# Hook runs, staging steps and the signal test for the pre-commit tests.
#
# - Sourced by `test/pre-commit.test.zsh`, after `test/hook_helpers.zsh`.

typeset -g HOOK_OUTPUT=""
typeset -gi HOOK_STATUS=0

# Makes a scratch repo with notes.md committed, then edited again.
new_edited_notes_repo() {
  new_scratch_repo
  print -r -- "first" > notes.md
  git_setup add -- notes.md
  git_setup commit --quiet --no-verify -m notes
  print -r -- "second" >> notes.md

  return 0
}

# Runs pre-commit, and records its output and status.
run_hook() {
  local hook_output
  local -i hook_status

  hook_output="$(run_pre_commit 2>&1)"
  hook_status="$?"
  typeset -g HOOK_OUTPUT="${hook_output}"
  typeset -gi HOOK_STATUS="${hook_status}"

  return 0
}

# Commits one path through the real hook, and records the output and status.
#
# - The stub pnpm goes first on PATH.
run_partial_commit() {
  local commit_output
  local -i commit_status

  commit_output="$(PATH="${SCRATCH_ROOT}/stub:${PATH}" \
    run_watching_warnings git_setup \
    -c core.hooksPath="${REPO_ROOT}/.githooks" commit --quiet -m partial \
    -- notes.md 2>&1)"
  commit_status="$?"
  typeset -g HOOK_OUTPUT="${commit_output}"
  typeset -gi HOOK_STATUS="${commit_status}"

  return 0
}

# Stages a new notes.md, which the stub pnpm reformats.
stage_notes() {
  print -r -- "staged" > notes.md
  git_setup add -- notes.md

  return "$?"
}

# Tests that a TERM signal mid-hook still removes the hook's export.
test_signal_cleanup() {
  local -a leftovers
  local hook_temp="${SCRATCH_ROOT}/hook-temp"
  local -i hook_pid

  describe "pre-commit, when signalled mid-run"
  test_case "removes its export"

  # Given - a staged file, and a hook run held part-way by the stub
  new_scratch_repo
  mkdir -p -- "${hook_temp}"
  stage_notes
  TMPDIR="${hook_temp}/" STUB_SLEEP=1 PATH="${SCRATCH_ROOT}/stub:${PATH}" \
    "${REPO_ROOT}/.githooks/pre-commit" > /dev/null 2>&1 &
  hook_pid="$!"
  sleep 1

  # When - sending it TERM
  kill -TERM "${hook_pid}"
  wait "${hook_pid}"
  leftovers=("${hook_temp}"/*(N))

  # Then - nothing is left in its temp folder
  expect_equal "leftovers" "0" "${#leftovers}"

  return 0
}
