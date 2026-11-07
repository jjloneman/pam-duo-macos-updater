# Assertions shared by the test files.

typeset -gi CHECK_COUNT=0
typeset -gi FAILURE_COUNT=0

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

# Records one failure, with what the check saw.
fail_check() {
  if ((${#} != 2)); then
    print -r -- "fail_check needs a name and details" >&2
    return 2
  fi

  typeset -gi FAILURE_COUNT=$((FAILURE_COUNT + 1))
  print -r -- "not ok: ${1}" >&2
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
