#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent \
  warn_create_global warn_nested_var
unset CDPATH
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r

# Proves the test runner reports each file, and stops them when interrupted.
#
# - Each test case writes small test files to a scratch folder and runs the
#   runner on them by name.

typeset -gr REPO_ROOT="${0:A:h:h}"

# Order: this reads REPO_ROOT, so it has to follow it.
typeset -gr TEST_RUNNER="${REPO_ROOT}/scripts/test.zsh"

typeset -g PROBE_ROOT=""
typeset -g RUNNER_OUTPUT=""
typeset -gi RUNNER_STATUS=0

source "${0:A:h}/helpers.zsh"

# Runs the runner on the named test files, keeping its output and status.
run_runner() {
  local runner_output
  local -i runner_status

  runner_output="$(/bin/zsh -f "${TEST_RUNNER}" "$@" 2>&1)"
  runner_status="$?"
  typeset -g RUNNER_OUTPUT="${runner_output}"
  typeset -gi RUNNER_STATUS="${runner_status}"

  return 0
}

# Tests what the runner prints and returns for each test file.
test_results() {
  describe "scripts/test.zsh, running test files"
  test_case "fails the run, naming only the failing file"

  # Given - one passing and one failing test file
  print -r -- "print -r -- ok" > "${PROBE_ROOT}/pass.test.zsh"
  print -r -- "exit 1" > "${PROBE_ROOT}/fail.test.zsh"

  # When - running both
  run_runner "${PROBE_ROOT}/pass.test.zsh" "${PROBE_ROOT}/fail.test.zsh"

  # Then - the run fails, and names the failing file alone
  expect_equal "status" "1" "${RUNNER_STATUS}"
  expect_contains "failing file" "fail.test.zsh failed" "${RUNNER_OUTPUT}"
  expect_missing "passing file" "pass.test.zsh failed" "${RUNNER_OUTPUT}"

  test_case "prints each file's stdout and stderr"

  # Given - a test file writing to both
  print -r -- "print -r -- out-line; print -r -- err-line >&2" \
    > "${PROBE_ROOT}/streams.test.zsh"

  # When - running it
  run_runner "${PROBE_ROOT}/streams.test.zsh"

  # Then - both lines are printed
  expect_contains "stdout" "out-line" "${RUNNER_OUTPUT}"
  expect_contains "stderr" "err-line" "${RUNNER_OUTPUT}"

  return 0
}

# Tests that test files get signals as they would outside the runner.
test_signals() {
  describe "scripts/test.zsh, running test files"
  test_case "leaves SIGINT to act as it does outside the runner"

  # Given - a test file whose child sends itself INT
  print -r -- "/bin/zsh -f -c 'kill -INT \$\$; print -r -- survived'" \
    > "${PROBE_ROOT}/signal.test.zsh"

  # When - running it
  run_runner "${PROBE_ROOT}/signal.test.zsh"

  # Then - the child stopped, rather than ignoring INT
  expect_missing "output" "survived" "${RUNNER_OUTPUT}"

  return 0
}

# Tests that a stopped run stops the test files it started.
#
# - Signals are sent with TERM, as a background job in a script ignores INT,
#   and the runner handles both alike.
#
# - It waits for the slow file to start, which is after the runner's traps are
#   set, so a slow machine can't send TERM too early.
test_stop() {
  local has_finished=no
  local -i runner_pid runner_status waited=0

  describe "scripts/test.zsh, when stopped"
  test_case "exits 143 on TERM, and stops its test files"

  # Given - a running test file that would write a marker after 3 seconds
  print -r -- "print started > '${PROBE_ROOT}/started';" \
    "sleep 3; print -r -- finished > '${PROBE_ROOT}/marker'" \
    > "${PROBE_ROOT}/slow.test.zsh"
  /bin/zsh -f "${TEST_RUNNER}" "${PROBE_ROOT}/slow.test.zsh" \
    > /dev/null 2>&1 &
  runner_pid="$!"

  while [[ ! -e ${PROBE_ROOT}/started && ${waited} -lt 100 ]]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  # When - sending the runner TERM, then waiting past the marker's time
  kill -TERM "${runner_pid}"
  wait "${runner_pid}"
  runner_status="$?"
  sleep 4

  if [[ -e ${PROBE_ROOT}/marker ]]; then
    has_finished=yes
  fi

  # Then - the runner exits 143, and the test file never finished
  expect_equal "status" "143" "${runner_status}"
  expect_equal "test file finished" "no" "${has_finished}"

  return 0
}

# Makes the scratch folder, runs every test, then removes it.
main() {
  local probe_root

  if ! probe_root="$(mktemp -d "${${TMPDIR:-/tmp}%/}/runner-test.XXXXXX")"; then
    print -r -- "the runner tests need a scratch folder" >&2

    return 1
  fi

  typeset -g PROBE_ROOT="${probe_root}"
  test_results
  test_signals
  test_stop
  finish_checks "runner"

  return "$?"
}

# Removes the scratch folder however the run ends.
trap 'if [[ -n ${PROBE_ROOT} ]]; then rm -rf -- "${PROBE_ROOT:?}"; fi' EXIT

main "$@"
exit "$?"
