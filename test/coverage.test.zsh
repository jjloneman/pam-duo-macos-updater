#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent \
  warn_create_global warn_nested_var
unset CDPATH
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r

# Proves the coverage tool counts, reports and fails as it should.
#
# - Each test case copies a small fixture repo to a scratch folder, changes
#   what it needs, and runs the tool from there.

typeset -gr REPO_ROOT="${0:A:h:h}"

# Order: these read REPO_ROOT, so they have to follow it.
typeset -gr COVERAGE_COMMAND="${REPO_ROOT}/scripts/coverage.zsh"
typeset -gr FIXTURE_DIR="${REPO_ROOT}/test/fixtures/coverage/basic"

source "${0:A:h}/coverage_helpers.zsh"
source "${0:A:h}/helpers.zsh"

# Tests that one real-only entry fails the run with the message given.
test_real_only_entry() {
  if ((${#} != 3)); then
    print -r -- "test_real_only_entry needs a scenario, entry and message" >&2

    return 2
  fi

  test_case "${1}"

  # Given - a real-only list holding only the entry
  copy_fixture
  print -r -- "${2}" > "${PROBE_ROOT}/test/real-only.txt"

  # When/Then - the run fails and says why
  expect_run_fails "${3}"

  return 0
}

# Tests the real-only list's own mistakes.
test_real_only_errors() {
  describe "coverage.zsh, with a wrong real-only list"
  test_real_only_entry "fails on an entry for a line that ran" \
    "bin/demo:18: claimed" "but the tests ran it"
  test_real_only_entry "fails on an entry for a file not traced" \
    "nowhere/x:3: claimed" "isn't a traced file"
  test_real_only_entry "fails on a path that only ends like a traced one" \
    "lib/bin/demo:4: claimed" "isn't a traced file"
  test_real_only_entry "fails on an entry for a comment line" \
    "bin/demo:6: claimed" "isn't a statement"
  test_real_only_entry "fails on an entry with no line" \
    "bin/demo: no line" "not path:line: reason"
  test_case "fails on a line listed twice"

  # Given - one line listed with two reasons
  copy_fixture
  print -rl -- "bin/demo:25: one" "bin/demo:25: two" \
    > "${PROBE_ROOT}/test/real-only.txt"

  # When/Then - the run fails, naming the line
  expect_run_fails "is listed twice"

  return 0
}

# Tests the report on the fixture as it is.
test_report() {
  describe "coverage.zsh, on the fixture repo"
  test_case "counts statements, misses and real-only lines"

  # Given - a fresh copy of the fixture
  copy_fixture

  # When - measuring every test file
  run_coverage

  # Then - each file's totals, misses and real-only lines
  expect_equal "status" "0" "${COVERAGE_STATUS}"
  expect_contains "script totals" "bin/demo: 10 of 13 lines (76%)" \
    "${COVERAGE_OUTPUT}"
  expect_contains "missed lines" "missed: 13, 14, 15" "${COVERAGE_OUTPUT}"
  expect_contains "real-only lines" \
    "real-only bin/demo:25: needs a real run" "${COVERAGE_OUTPUT}"
  expect_contains "sourced file totals" \
    "lib/greet.zsh: 2 of 2 lines (100%)" "${COVERAGE_OUTPUT}"
  expect_missing "scope warnings" "enclosing scope" "${COVERAGE_OUTPUT}"

  # And - the source is left as it was
  expect_same_file "source" "${FIXTURE_DIR}/bin/demo" "${PROBE_ROOT}/bin/demo"

  return 0
}

# Tests the report with a named test file, and without a real-only list.
test_report_variants() {
  describe "coverage.zsh, on the fixture repo"
  test_case "runs only the test files named"

  # Given - a fresh copy of the fixture
  copy_fixture

  # When/Then - measuring one named test file passes
  run_coverage test/demo.test.zsh
  expect_equal "status" "0" "${COVERAGE_STATUS}"

  test_case "runs without a real-only list"

  # Given - a fresh copy of the fixture, with no test/real-only.txt
  copy_fixture
  rm -f -- "${PROBE_ROOT:?}/test/real-only.txt"

  # When - measuring every test file
  run_coverage

  # Then - the real-only line counts as missed
  expect_contains "script totals" "bin/demo: 10 of 14 lines (71%)" \
    "${COVERAGE_OUTPUT}"

  return 0
}

# Tests the ways a run fails because of its test files.
test_run_failures() {
  describe "coverage.zsh, when the tests fail"
  test_case "fails when a test file fails"

  # Given - a test file that exits 1
  copy_fixture
  print -r -- "exit 1" > "${PROBE_ROOT}/test/fail.test.zsh"

  # When/Then - the run fails, naming it
  expect_run_fails "fail.test.zsh failed"

  test_case "fails when a test prints a scope warning"

  # Given - a test file that creates a global
  copy_fixture
  print -r -- 'setopt warn_create_global; f() { leaked=1; }; f' \
    > "${PROBE_ROOT}/test/warn.test.zsh"

  # When/Then - the run fails, as the test runner would
  expect_run_fails "printed a zsh warning"

  test_case "fails with no test files"

  # Given - the only test file removed
  copy_fixture
  rm -f -- "${PROBE_ROOT:?}/test/demo.test.zsh"

  # When/Then - the run fails
  expect_run_fails "found no test files"

  return 0
}

# Tests which files can be traced, and how.
test_target_files() {
  describe "coverage.zsh, choosing files to trace"
  test_case "skips a script that isn't zsh"

  # Given - a sh script under libexec/
  copy_fixture
  mkdir -p -- "${PROBE_ROOT}/libexec"
  print -rl -- "#!/bin/sh" "echo hi" > "${PROBE_ROOT}/libexec/tool.sh"

  # When - measuring every test file
  run_coverage

  # Then - it passes, and says what it skipped
  expect_equal "status" "0" "${COVERAGE_STATUS}"
  expect_contains "message" "skipping libexec/tool.sh: not a zsh file" \
    "${COVERAGE_OUTPUT}"

  test_case "fails on code on line 1"

  # Given - a sourced file that starts with code
  copy_fixture
  print -r -- "greet() { return 0; }" > "${PROBE_ROOT}/lib/greet.zsh"

  # When/Then - the run fails, as line 1 can't be traced
  expect_run_fails "line 1 must be a shebang or a comment"

  return 0
}

# Tests the trees coverage can't trace at all.
test_targets() {
  describe "coverage.zsh, choosing files to trace"
  test_case "fails with nothing to trace"

  # Given - no bin/ or lib/
  copy_fixture
  rm -rf -- "${PROBE_ROOT:?}/bin" "${PROBE_ROOT:?}/lib"

  # When/Then - the run fails
  expect_run_fails "found nothing to trace"

  test_case "fails on two traced files with one name"

  # Given - the script copied under libexec/
  copy_fixture
  mkdir -p -- "${PROBE_ROOT}/libexec"
  cp -- "${PROBE_ROOT}/bin/demo" "${PROBE_ROOT}/libexec/demo"

  # When/Then - the run fails, as the trace couldn't tell them apart
  expect_run_fails "two traced files are named"

  return 0
}

# Runs every test, then removes the scratch folder.
main() {
  test_real_only_errors
  test_report
  test_report_variants
  test_run_failures
  test_target_files
  test_targets
  remove_probe_root
  finish_checks "coverage"

  return "$?"
}

# Removes the scratch folder however the run ends.
trap 'remove_probe_root' EXIT

main "$@"
exit "$?"
