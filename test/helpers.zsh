# Assertions shared by the test files, named the way vitest names tests.
#
# - `describe "<unit>"` names what's under test, and `test_case "<scenario>"`
#   names one scenario of it. A failure prints both, then the check's own
#   name: `not ok: <unit> › <scenario> › <check>`.
#
# - Inside a test case, `# Given -`, `# When -`, `# Then -`, `# And -`,
#   `# Setup -` and `# Cleanup` comments mark its phases, each with a hyphen
#   and what that phase holds. Lint checks the shape.

typeset -gi CHECK_COUNT=0
typeset -g DESCRIBE_NAME=""
typeset -gi FAILURE_COUNT=0
typeset -g TEST_CASE_NAME=""

# Names the unit the test cases after it are about.
describe() {
  if ((${#} != 1)); then
    print -r -- "describe needs a unit" >&2

    return 2
  fi

  typeset -g DESCRIBE_NAME="${1}"
  typeset -g TEST_CASE_NAME=""

  return 0
}

# Checks that a value contains a piece of text.
expect_contains() {
  if ((${#} != 3)); then
    print -r -- "expect_contains needs a name, text and a value" >&2

    return 2
  fi

  typeset -gi CHECK_COUNT=$((CHECK_COUNT + 1))

  if [[ ${3} != *"${2}"* ]]; then
    fail_check "${1}" "expected to find: ${2}, in: ${3}"
  fi

  return 0
}

# Checks that two values are equal.
expect_equal() {
  if ((${#} != 3)); then
    print -r -- "expect_equal needs a name and two values" >&2

    return 2
  fi

  typeset -gi CHECK_COUNT=$((CHECK_COUNT + 1))

  if [[ ${2} != "${3}" ]]; then
    fail_check "${1}" "expected: ${2}, got: ${3}"
  fi

  return 0
}

# Checks that a value doesn't contain a piece of text.
expect_missing() {
  if ((${#} != 3)); then
    print -r -- "expect_missing needs a name, text and a value" >&2

    return 2
  fi

  typeset -gi CHECK_COUNT=$((CHECK_COUNT + 1))

  if [[ ${3} == *"${2}"* ]]; then
    fail_check "${1}" "expected no: ${2}, in: ${3}"
  fi

  return 0
}

# Checks that two files have the same contents.
expect_same_file() {
  if ((${#} != 3)); then
    print -r -- "expect_same_file needs a name and two files" >&2

    return 2
  fi

  typeset -gi CHECK_COUNT=$((CHECK_COUNT + 1))

  if ! cmp -s -- "${2}" "${3}"; then
    fail_check "${1}" "expected the same contents: ${2} and ${3}"
  fi

  return 0
}

# Records one failure, with what the check saw.
fail_check() {
  if ((${#} != 2)); then
    print -r -- "fail_check needs a name and details" >&2

    return 2
  fi

  local -a name_parts=("${DESCRIBE_NAME}" "${TEST_CASE_NAME}" "${1}")

  typeset -gi FAILURE_COUNT=$((FAILURE_COUNT + 1))
  print -r -- "not ok: ${(j: › :)${(@)name_parts:#}}" >&2
  print -r -- "${2}" >&2

  return 0
}

# Prints the totals, and returns failure if any check failed.
finish_checks() {
  print -r -- "${1:-checks}: ${CHECK_COUNT} checks, ${FAILURE_COUNT} failed"

  if ((FAILURE_COUNT > 0)); then
    return 1
  fi

  return 0
}

# Names the scenario the checks after it belong to.
test_case() {
  if ((${#} != 1)); then
    print -r -- "test_case needs a scenario" >&2

    return 2
  fi

  typeset -g TEST_CASE_NAME="${1}"

  return 0
}
