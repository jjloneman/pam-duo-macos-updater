#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent \
  warn_create_global warn_nested_var
unset CDPATH
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r

# Proves the formatter leaves the repo's safe argument forms intact.
#
# - prettier-plugin-sh has turned "$#" into "$", which still passes `zsh -n`.
#
# - A formatter upgrade that corrupts a form the repo relies on fails here, so
#   it can't arrive unnoticed.
#
# - The input is unformatted on purpose, so a run that changes nothing, such as
#   one that skipped the file, fails too.

typeset -gr REPO_ROOT="${0:A:h:h}"

source "${0:A:h}/helpers.zsh"

# Tests that the formatter keeps the safe forms in the fixture.
test_safe_forms() {
  local expected formatted input_file
  local -i format_status

  describe "formatter, on the safe argument forms"
  test_case "keeps them intact"

  # Given - an unformatted input, and the output expected from it
  input_file="${REPO_ROOT}/test/fixtures/formatter/input.zsh"
  expected="$(< "${REPO_ROOT}/test/fixtures/formatter/expected.zsh")"

  # When - formatting the input
  # --ignore-path stops .prettierignore, which covers fixtures, skipping it.
  formatted="$(/usr/bin/env PATH="${CALLER_PATH:-${PATH}}" \
    "${REPO_ROOT}/node_modules/.bin/prettier" --ignore-path /dev/null \
    --stdin-filepath "${REPO_ROOT}/test/formatter-fixture.zsh" \
    < "${input_file}" 2>&1)"
  format_status="$?"

  # Then - the formatter runs, and the output is the expected one
  expect_equal "status" "0" "${format_status}"
  expect_equal "output" "${expected}" "${formatted}"

  return 0
}

# Runs the test and reports the totals.
main() {
  test_safe_forms
  finish_checks "formatter"

  return "$?"
}

main "$@"
exit "$?"
