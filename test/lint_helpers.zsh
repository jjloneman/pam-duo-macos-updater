# Lint runs and scratch folders for the lint tests.
#
# - Sourced by `test/lint.test.zsh`, which sets LINT_COMMAND first.

typeset -g LINT_OUTPUT=""
typeset -gi LINT_STATUS=0
typeset -g PROBE_ROOT=""

# Makes a scratch folder, or fails the check that needed it.
make_probe_root() {
  local probe_root

  if ! probe_root="$(mktemp -d "${${TMPDIR:-/tmp}%/}/lint-test.XXXXXX")"; then
    fail_check "scratch folder" "mktemp failed"

    return 1
  fi

  typeset -g PROBE_ROOT="${probe_root}"

  return 0
}

# Runs lint with the arguments given, and records its output and status.
run_lint() {
  local lint_output
  local -i lint_status

  lint_output="$("${LINT_COMMAND}" "$@" 2>&1)"
  lint_status="$?"
  typeset -g LINT_OUTPUT="${lint_output}"
  typeset -gi LINT_STATUS="${lint_status}"

  return 0
}

# Tests that every bad tree of a rule is scanned and caught.
#
# - Every tree stands alone, so an easy form can't hide a missed hard one.
test_bad_trees() {
  if ((${#} < 2)); then
    print -r -- "test_bad_trees needs a rule name and trees" >&2

    return 2
  fi

  local rule_name="${1}" tree_path

  shift

  for tree_path in "$@"; do
    test_case "catches ${tree_path:t}"

    # When - linting the tree on its own
    run_lint --root "${tree_path}"

    # Then - lint finds the rule's problem
    expect_equal "status" "1" "${LINT_STATUS}"
    expect_contains "finding" ": ${rule_name}: " "${LINT_OUTPUT}"
  done

  return 0
}

# Tests that every good tree of a rule is scanned, and passes the rule.
#
# - A good tree can hold other findings, but must have been checked.
test_good_trees() {
  if ((${#} < 2)); then
    print -r -- "test_good_trees needs a rule name and trees" >&2

    return 2
  fi

  local rule_name="${1}" tree_path

  shift

  for tree_path in "$@"; do
    test_case "passes ${tree_path:t}"

    # When - linting the tree on its own
    run_lint --root "${tree_path}"

    # Then - lint ran, and found nothing from the rule
    expect_missing "ran" "lint error" "${LINT_OUTPUT}"
    expect_equal "status is 0 or 1" "1" "$((LINT_STATUS <= 1))"
    expect_missing "finding" ": ${rule_name}: " "${LINT_OUTPUT}"
  done

  return 0
}
