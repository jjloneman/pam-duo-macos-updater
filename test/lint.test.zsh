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

# Checks lint's exit codes, which the hooks and CI rely on.
check_exit_codes() {
  local probe_root
  local -i lint_status

  "${LINT_COMMAND}" --root "${FIXTURE_DIR}/lint/no_echo/bad" > /dev/null 2>&1
  lint_status="$?"
  expect_equal "findings exit 1" "1" "${lint_status}"
  "${LINT_COMMAND}" --root /nonexistent-lint-root > /dev/null 2>&1
  lint_status="$?"
  expect_equal "a missing root exits 2" "2" "${lint_status}"
  "${LINT_COMMAND}" --root > /dev/null 2>&1
  lint_status="$?"
  expect_equal "--root with no directory exits 2" "2" "${lint_status}"

  if ! probe_root="$(mktemp -d)"; then
    fail_check "the exit code checks need a folder" "mktemp failed"
    return 0
  fi

  "${LINT_COMMAND}" --root "${probe_root}" > /dev/null 2>&1
  lint_status="$?"
  expect_equal "an empty root exits 2" "2" "${lint_status}"
  mkdir -p -- "${probe_root}/bin"
  print -r -- "print -r -- ok" > "${probe_root}/bin/tool"
  chmod 000 "${probe_root}/bin/tool"
  "${LINT_COMMAND}" --root "${probe_root}" > /dev/null 2>&1
  lint_status="$?"
  expect_equal "an unreadable file exits 2" "2" "${lint_status}"
  chmod 644 "${probe_root}/bin/tool"
  rm -rf -- "${probe_root:?}"
  return 0
}

# Checks that a failed grep counts as an error, not as no findings.
check_grep_failure() {
  local error_count

  error_count="$(
    source "${REPO_ROOT}/scripts/lint/scan.zsh"
    typeset -g VIEW_DIR=/nonexistent-lint-views
    report_pattern probe code 'a' 'message' 2> /dev/null
    print -r -- "${TOOL_ERROR_COUNT}"
  )"
  expect_equal "a failed grep is a tool error" "1" "${error_count}"
  return 0
}

# Checks that the legacy list exempts style, but not syntax.
check_legacy_list() {
  local helper_output exempt_output syntax_output
  local legacy_root="${FIXTURE_DIR}/legacy"

  exempt_output="$("${LINT_COMMAND}" --root "${legacy_root}/exempt" 2>&1)"
  expect_equal "a listed file skips style rules" "" "${exempt_output}"
  syntax_output="$("${LINT_COMMAND}" --root "${legacy_root}/syntax" 2>&1)"
  expect_contains "a listed file still gets zsh -n" ": zsh_syntax: " \
    "${syntax_output}"
  helper_output="$("${LINT_COMMAND}" --root "${legacy_root}/helper" 2>&1)"
  expect_contains "a listed helper still can't source" \
    ": helper_sources_nothing: " "${helper_output}"
  return 0
}

# Checks that lint refuses to run with a rule file missing.
check_missing_rule_file() {
  local probe_root
  local -i lint_status

  if ! probe_root="$(mktemp -d)"; then
    fail_check "the rule file check needs a folder" "mktemp failed"
    return 0
  fi

  cp -R -- "${REPO_ROOT}/scripts" "${probe_root}/scripts"
  rm -f -- "${probe_root}/scripts/lint/rules_banned.zsh"
  "${probe_root}/scripts/lint.zsh" --root "${FIXTURE_DIR}/lint/no_echo/bad" \
    > /dev/null 2>&1
  lint_status="$?"
  expect_equal "a missing rule file exits 2" "2" "${lint_status}"
  rm -rf -- "${probe_root:?}"
  return 0
}

# Checks that the repo passes its own lint with no warnings.
check_repo_passes() {
  local repo_output

  local -i repo_status

  repo_output="$("${LINT_COMMAND}" 2>&1)"
  repo_status="$?"
  expect_equal "the repo passes its own lint" "" "${repo_output}"
  expect_equal "the repo's lint exits 0" "0" "${repo_status}"
  return 0
}

# Checks one rule's bad and good fixtures.
check_rule_fixture() {
  if ((${#} != 1)); then
    print -r -- "check_rule_fixture needs a rule name" >&2
    return 2
  fi

  local -a bad_trees good_trees
  local rule_name="${1}" tree_output tree_path
  local -i tree_status
  local rule_root="${FIXTURE_DIR}/lint/${1}"

  bad_trees=("${rule_root}"/bad*(/N))
  good_trees=("${rule_root}"/good*(/N))

  if ((${#bad_trees} == 0 || ${#good_trees} == 0)); then
    fail_check "${1} needs a bad and a good tree" "${rule_root}"
    return 0
  fi

  # Every tree stands alone, so an easy form can't hide a missed hard one.
  for tree_path in "${bad_trees[@]}"; do
    tree_output="$("${LINT_COMMAND}" --root "${tree_path}" 2>&1)"
    tree_status="$?"
    expect_equal "${1} scans ${tree_path:t}" "1" "${tree_status}"
    expect_contains "${1} catches ${tree_path:t}" ": ${rule_name}: " \
      "${tree_output}"
  done

  # A good tree can hold other findings, but must have been checked.
  for tree_path in "${good_trees[@]}"; do
    tree_output="$("${LINT_COMMAND}" --root "${tree_path}" 2>&1)"
    tree_status="$?"
    expect_missing "${1} checks ${tree_path:t}" "lint error" "${tree_output}"
    expect_equal "${1} scans ${tree_path:t}" "1" "$((tree_status <= 1))"
    expect_missing "${1} passes ${tree_path:t}" ": ${rule_name}: " \
      "${tree_output}"
  done

  return 0
}

# Checks that the rules and fixtures match, so no rule goes untested.
check_rules_have_fixtures() {
  local -a fixture_names rule_names

  rule_names=("${(@f)$("${LINT_COMMAND}" --list-rules)}")
  fixture_names=("${FIXTURE_DIR}"/lint/*(/N:t))

  # Sort first, because (o) and (j) together in quotes join without sorting.
  rule_names=("${(@o)rule_names}")
  fixture_names=("${(@o)fixture_names}")
  expect_equal "every rule has a fixture, and every fixture a rule" \
    "${(j: :)rule_names}" "${(j: :)fixture_names}"
  return 0
}

# Runs every check and reports the totals.
main() {
  local fixture_path

  check_rules_have_fixtures

  for fixture_path in "${FIXTURE_DIR}"/lint/*(/N); do
    check_rule_fixture "${fixture_path:t}"
  done

  check_exit_codes
  check_grep_failure
  check_legacy_list
  check_missing_rule_file
  check_repo_passes
  finish_checks "lint"
  return "$?"
}

main "$@"
exit "$?"
