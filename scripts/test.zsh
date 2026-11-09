#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent \
  warn_create_global warn_nested_var
unset CDPATH

# Keeps the caller's PATH, which the formatter test needs to find Node.
typeset -gx CALLER_PATH="${PATH}"
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r

# Inside a function, $0 is the function's name, so capture this here.
typeset -gr TEST_DIR="${0:A:h:h}/test"

# Runs one test file, failing it if it prints a scope warning.
#
# - warn_create_global and warn_nested_var only warn, so a test could pass
#   while printing them, as one did.
#
# - This sees only the test file's own stderr. The hook tests record warnings
#   from the hooks they run themselves, through test/hook_helpers.zsh.
run_test_file() {
  local warnings_file warnings_text
  local -i test_status

  if ! warnings_file="$(mktemp "${${TMPDIR:-/tmp}%/}/warnings.XXXXXX")"; then
    print -r -- "could not make a temporary file" >&2
    return 1
  fi

  /bin/zsh -f "${1}" 2> "${warnings_file}"
  test_status="$?"
  warnings_text="$(< "${warnings_file}")"
  rm -f -- "${warnings_file}"

  if [[ -n ${warnings_text} ]]; then
    print -r -- "${warnings_text}" >&2
  fi

  if [[ ${warnings_text} == *(created globally|set in enclosing scope)* ]]; then
    print -r -- "${1:t} printed a zsh warning" >&2
    return 1
  fi

  return "${test_status}"
}

# Runs every test file, and fails if any of them does.
main() {
  local -a test_files
  local test_file
  local -i failed_files=0

  test_files=("${TEST_DIR}"/*.test.zsh(N))

  if ((${#test_files} == 0)); then
    print -r -- "no test files found in ${TEST_DIR}" >&2
    return 1
  fi

  for test_file in "${test_files[@]}"; do
    if ! run_test_file "${test_file}"; then
      failed_files=$((failed_files + 1))
    fi
  done

  if ((failed_files > 0)); then
    print -r -- "${failed_files} test files failed" >&2
    return 1
  fi

  return 0
}

main "$@"
exit "$?"
