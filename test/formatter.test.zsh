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

# Formats the fixture and compares the result with what's expected.
main() {
  local expected formatted input_file
  local -i format_status

  input_file="${REPO_ROOT}/test/fixtures/formatter/input.zsh"
  expected="$(< "${REPO_ROOT}/test/fixtures/formatter/expected.zsh")"

  # --ignore-path stops .prettierignore, which covers fixtures, skipping it.
  formatted="$(/usr/bin/env PATH="${CALLER_PATH:-${PATH}}" \
    "${REPO_ROOT}/node_modules/.bin/prettier" --ignore-path /dev/null \
    --stdin-filepath "${REPO_ROOT}/test/formatter-fixture.zsh" \
    < "${input_file}" 2>&1)"
  format_status="$?"
  expect_equal "the formatter runs" "0" "${format_status}"
  expect_equal "the formatter keeps the safe forms" "${expected}" "${formatted}"
  finish_checks "formatter"
  return "$?"
}

main "$@"
exit "$?"
