#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent \
  warn_create_global warn_nested_var
unset CDPATH
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r

# Proves each lint rule catches its bad form and passes its good one.

typeset -gr REPO_ROOT="${0:A:h:h}"

# Order: this reads REPO_ROOT, so it has to follow it.
typeset -gr FIXTURE_DIR="${REPO_ROOT}/test/fixtures"
typeset -gr LINT_COMMAND="${REPO_ROOT}/scripts/lint.zsh"

source "${0:A:h}/helpers.zsh"
source "${0:A:h}/lint_helpers.zsh"

# Tests the exit codes the hooks and CI rely on.
test_exit_codes() {
  describe "lint.zsh, exit codes"
  test_case "exits 1 on findings"

  # When - linting a tree with an echo in it
  run_lint --root "${FIXTURE_DIR}/lint/no_echo/bad"

  # Then - the status is 1
  expect_equal "status" "1" "${LINT_STATUS}"

  test_case "exits 2 on a missing root"

  # When - linting a folder that doesn't exist
  run_lint --root /nonexistent-lint-root

  # Then - the status is 2
  expect_equal "status" "2" "${LINT_STATUS}"

  test_case "exits 2 on --root with no directory"

  # When - passing --root alone
  run_lint --root

  # Then - the status is 2
  expect_equal "status" "2" "${LINT_STATUS}"

  return 0
}

# Tests that lint exits 2 on an empty root.
test_exit_codes_on_an_empty_root() {
  describe "lint.zsh, exit codes"
  test_case "exits 2 on an empty root"

  # Given - an empty folder
  if ! make_probe_root; then
    return 0
  fi

  # When - linting it
  run_lint --root "${PROBE_ROOT}"

  # Then - the status is 2
  expect_equal "status" "2" "${LINT_STATUS}"

  # Cleanup
  rm -rf -- "${PROBE_ROOT:?}"

  return 0
}

# Tests that lint exits 2 on an unreadable file.
test_exit_codes_on_an_unreadable_file() {
  describe "lint.zsh, exit codes"
  test_case "exits 2 on an unreadable file"

  # Given - a folder holding a file nobody can read
  if ! make_probe_root; then
    return 0
  fi

  mkdir -p -- "${PROBE_ROOT}/bin"
  print -r -- "print -r -- ok" > "${PROBE_ROOT}/bin/tool"
  chmod 000 "${PROBE_ROOT}/bin/tool"

  # When - linting it
  run_lint --root "${PROBE_ROOT}"

  # Then - the status is 2
  expect_equal "status" "2" "${LINT_STATUS}"

  # Cleanup
  chmod 644 "${PROBE_ROOT}/bin/tool"
  rm -rf -- "${PROBE_ROOT:?}"

  return 0
}

# Tests that a failed grep counts as an error, not as no findings.
test_grep_failure() {
  local error_count

  describe "scan.zsh, report_pattern"
  test_case "counts a failed grep as a tool error"

  # When - reporting a pattern against a views folder that doesn't exist
  error_count="$(
    source "${REPO_ROOT}/scripts/lint/scan.zsh"
    typeset -g VIEW_DIR=/nonexistent-lint-views
    report_pattern probe code 'a' 'message' 2> /dev/null
    print -r -- "${TOOL_ERROR_COUNT}"
  )"

  # Then - one tool error was counted
  expect_equal "tool errors" "1" "${error_count}"

  return 0
}

# Tests that the legacy list exempts style, but not syntax.
test_legacy_list() {
  describe "lint.zsh, with a legacy list"
  test_case "skips style rules for a listed file"

  # When - linting a listed file with style problems
  run_lint --root "${FIXTURE_DIR}/legacy/exempt"

  # Then - lint says nothing
  expect_equal "output" "" "${LINT_OUTPUT}"

  test_case "still runs zsh -n on a listed file"

  # When - linting a listed file with a syntax error
  run_lint --root "${FIXTURE_DIR}/legacy/syntax"

  # Then - lint reports the syntax error
  expect_contains "output" ": zsh_syntax: " "${LINT_OUTPUT}"

  test_case "still refuses a listed helper that sources"

  # When - linting a listed helper that sources a file
  run_lint --root "${FIXTURE_DIR}/legacy/helper"

  # Then - lint reports it
  expect_contains "output" ": helper_sources_nothing: " "${LINT_OUTPUT}"

  test_case "still checks a listed file's comment width"

  # When - linting a listed file with a comment over 80 columns
  run_lint --root "${FIXTURE_DIR}/legacy/comment-width"

  # Then - lint reports both comments, and not the plain code
  expect_contains "comment" "bin/old:2: line_width: " "${LINT_OUTPUT}"
  expect_contains "trailing comment" "bin/old:4: line_width: " \
    "${LINT_OUTPUT}"
  expect_missing "code" "bin/old:3:" "${LINT_OUTPUT}"
  expect_missing "long code, short comment" "bin/old:5:" "${LINT_OUTPUT}"

  return 0
}

# Tests that lint refuses to run with a rule file missing.
test_missing_rule_file() {
  local lint_status

  describe "lint.zsh, with a rule file missing"
  test_case "exits 2"

  # Given - a copy of scripts/ without rules_banned.zsh
  if ! make_probe_root; then
    return 0
  fi

  cp -R -- "${REPO_ROOT}/scripts" "${PROBE_ROOT}/scripts"
  rm -f -- "${PROBE_ROOT}/scripts/lint/rules_banned.zsh"

  # When - linting a tree with the copy
  "${PROBE_ROOT}/scripts/lint.zsh" --root "${FIXTURE_DIR}/lint/no_echo/bad" \
    > /dev/null 2>&1
  lint_status="$?"

  # Then - the status is 2
  expect_equal "status" "2" "${lint_status}"

  # Cleanup
  rm -rf -- "${PROBE_ROOT:?}"

  return 0
}

# Tests that the repo passes its own lint with no warnings.
test_repo_passes() {
  describe "lint.zsh, on this repo"
  test_case "finds nothing and exits 0"

  # When - linting the repo, or the untraced original under coverage
  run_lint --root "${COVERAGE_REPO_ROOT:-${REPO_ROOT}}"

  # Then - there is no output, and the status is 0
  expect_equal "output" "" "${LINT_OUTPUT}"
  expect_equal "status" "0" "${LINT_STATUS}"

  return 0
}

# Tests one rule's bad and good fixtures.
test_rule_fixture() {
  if ((${#} != 1)); then
    print -r -- "test_rule_fixture needs a rule name" >&2

    return 2
  fi

  local -a bad_trees good_trees
  local rule_root="${FIXTURE_DIR}/lint/${1}"

  describe "lint.zsh, rule ${1}"
  test_case "has a bad tree and a good tree"

  # When - listing the rule's fixture trees
  bad_trees=("${rule_root}"/bad*(/N))
  good_trees=("${rule_root}"/good*(/N))

  # Then - there is at least one of each
  if ((${#bad_trees} == 0 || ${#good_trees} == 0)); then
    fail_check "trees" "${rule_root}"

    return 0
  fi

  test_bad_trees "${1}" "${bad_trees[@]}"
  test_good_trees "${1}" "${good_trees[@]}"

  return 0
}

# Tests that the rules and fixtures match, so no rule goes untested.
test_rules_have_fixtures() {
  local -a fixture_names rule_names

  describe "lint.zsh, rule list"
  test_case "has a fixture for every rule, and a rule for every fixture"

  # When - listing the rules and the fixture folders
  rule_names=("${(@f)$("${LINT_COMMAND}" --list-rules)}")
  fixture_names=("${FIXTURE_DIR}"/lint/*(/N:t))

  # Sort first, because (o) and (j) together in quotes join without sorting.
  rule_names=("${(@o)rule_names}")
  fixture_names=("${(@o)fixture_names}")

  # Then - the two lists are the same
  expect_equal "names" "${(j: :)rule_names}" "${(j: :)fixture_names}"

  return 0
}

# Runs every test and reports the totals.
main() {
  local fixture_path

  test_rules_have_fixtures

  for fixture_path in "${FIXTURE_DIR}"/lint/*(/N); do
    test_rule_fixture "${fixture_path:t}"
  done

  test_exit_codes
  test_exit_codes_on_an_empty_root
  test_exit_codes_on_an_unreadable_file
  test_grep_failure
  test_legacy_list
  test_missing_rule_file
  test_repo_passes
  finish_checks "lint"

  return "$?"
}

main "$@"
exit "$?"
