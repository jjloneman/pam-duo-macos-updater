# Rules about how a test file is shaped.
#
# - Test files name their unit with `describe` and each scenario with
#   `test_case`, as vitest does, so every failure says what it was about.
#
# - Each test case marks its phases with `# Given -`, `# When -`, `# Then -`,
#   `# And -` and `# Setup -` comments, or a bare `# Cleanup`.

# The open test case's line, and whether its When and Then were seen.
typeset -gi TEST_CASE_LINE=0
typeset -gi TEST_CASE_HAS_THEN=0
typeset -gi TEST_CASE_HAS_WHEN=0

# The open `test_*` function's line, and what it has shown so far.
typeset -gi TEST_FUNCTION_LINE=0
typeset -gi TEST_FUNCTION_HAS_CASE=0
typeset -gi TEST_FUNCTION_HAS_DESCRIBE=0
typeset -gi TEST_FUNCTION_TAKES_ARGUMENTS=0

# Whether the file being checked called describe anywhere.
typeset -gi TEST_FILE_HAS_DESCRIBE=0

# Reports the open test case if it had no When or no Then, then closes it.
close_test_case() {
  if ((TEST_CASE_LINE > 0)); then
    if ((!TEST_CASE_HAS_WHEN || !TEST_CASE_HAS_THEN)); then
      report "${TEST_CASE_LINE}" test_shape \
        "a test_case needs a # When - and a # Then - comment"
    fi
  fi

  typeset -gi TEST_CASE_LINE=0 TEST_CASE_HAS_THEN=0 TEST_CASE_HAS_WHEN=0

  return 0
}

# Reports the open `test_*` function if it ran test cases with no describe.
#
# - A function that takes arguments is a shared test case, run under its
#   caller's describe, so it's left alone.
close_test_function() {
  if ((TEST_FUNCTION_LINE > 0 && TEST_FUNCTION_HAS_CASE && !\
    TEST_FUNCTION_HAS_DESCRIBE)); then
    if ((!TEST_FUNCTION_TAKES_ARGUMENTS)); then
      report "${TEST_FUNCTION_LINE}" test_shape \
        "a test function with test cases names its unit with describe"
    fi
  fi

  typeset -gi TEST_FUNCTION_LINE=0 TEST_FUNCTION_HAS_CASE=0
  typeset -gi TEST_FUNCTION_HAS_DESCRIBE=0 TEST_FUNCTION_TAKES_ARGUMENTS=0

  return 0
}

# Checks one comment line, if it names a phase, and notes When and Then.
#
# - `When/Then` covers both, as a check that acts and asserts in one line.
#
# - A near miss only counts inside a test case, so prose elsewhere that starts
#   with a phase word passes.
#
# - The catch-all deliberately accepts any other comment.
read_phase_comment() {
  if ((${#} != 2)); then
    print -r -- "read_phase_comment needs a line number and a comment" >&2

    return 2
  fi

  case "${2}" in
    "# Cleanup" | "# Cleanup - "?* | "# And - "?* | "# Given - "?*)
      return 0
      ;;
    "# Setup - "?*)
      return 0
      ;;
    "# Then - "?*)
      typeset -gi TEST_CASE_HAS_THEN=1
      ;;
    "# When - "?*)
      typeset -gi TEST_CASE_HAS_WHEN=1
      ;;
    "# When/Then - "?*)
      typeset -gi TEST_CASE_HAS_THEN=1 TEST_CASE_HAS_WHEN=1
      ;;

    # Order: a near miss of the forms above, so it has to follow them.
    "# "(And|Cleanup|Given|Setup|Then|When)*)
      if ((TEST_CASE_LINE > 0)); then
        report "${1}" test_shape "a phase comment reads '# <Phase> - <what>'"
      fi
      ;;
    *) ;;
  esac

  return 0
}

# Notes what one code line opens, closes or shows in a test file.
#
# - Only a `}` in column 0 ends a function, so a `{ ... }` group inside a test
#   case doesn't close it early.
read_test_line() {
  if ((${#} != 1)); then
    print -r -- "read_test_line needs a line number" >&2

    return 2
  fi

  local code_line="${CODE_LINES[${1}]}"

  trim_line "${code_line}"

  if [[ ${code_line} == "}" || ${TRIMMED_LINE} == "test_case "* ]]; then
    close_test_case
  fi

  if [[ ${code_line} == "}" || ${code_line} == [A-Za-z_]*"() {"* ]]; then
    close_test_function
  fi

  if [[ ${code_line} == test_*"() {"* ]]; then
    typeset -gi TEST_FUNCTION_LINE="${1}"
  fi

  if [[ ${TRIMMED_LINE} == "describe "* ]]; then
    typeset -gi TEST_FUNCTION_HAS_DESCRIBE=1 TEST_FILE_HAS_DESCRIBE=1
  fi

  if [[ ${TRIMMED_LINE} == "test_case "* ]]; then
    typeset -gi TEST_CASE_LINE="${1}" TEST_FUNCTION_HAS_CASE=1
  fi

  if [[ ${TRIMMED_LINE} == *'((${#} '* ]]; then
    typeset -gi TEST_FUNCTION_TAKES_ARGUMENTS=1
  fi

  return 0
}

# Checks a test file names its unit, and marks each test case's phases.
#
# - Test helper files can hold test cases too, so their phases are checked,
#   but only a test file must call describe.
rule_test_shape() {
  local -i index=0

  if [[ ${CURRENT_FILE} != test/*(.test.zsh|_helpers.zsh) ]]; then
    return 0
  fi

  typeset -gi TEST_FILE_HAS_DESCRIBE=0

  for ((index = 1; index <= ${#CODE_LINES}; index++)); do
    read_test_line "${index}"
    trim_line "${COMMENT_LINES[index]:-}"
    read_phase_comment "${index}" "${TRIMMED_LINE}"
  done

  close_test_case
  close_test_function

  if [[ ${TEST_FILE_HAS_DESCRIBE} -eq 0 &&
    ${CURRENT_FILE} == *.test.zsh ]]; then
    report 1 test_shape "a test file names its unit with describe"
  fi

  return 0
}
