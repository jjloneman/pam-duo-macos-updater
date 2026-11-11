#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent \
  warn_create_global warn_nested_var
unset CDPATH

# Keeps the caller's PATH, which the formatter test needs to find Node.
#
# - A caller that already pinned its own PATH, such as the coverage tool,
#   passes the original on.
typeset -gx CALLER_PATH="${CALLER_PATH:-${PATH}}"
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r

# Runs the named test files, or every `test/*.test.zsh`, side by side.
#
# - Test files share only read-only fixtures, and each makes its own scratch
#   folders, so they can run at once. Each one's output is printed in order
#   once it ends.

# Inside a function, $0 is the function's name, so capture this here.
typeset -gr TEST_DIR="${0:A:h:h}/test"

# The folder holding each test file's output until it's printed.
typeset -g TEST_LOG_DIR=""

# The background job running each test file, in the order they started.
typeset -ga TEST_PIDS=()

# Prints each test file's output in order, and counts the ones that failed.
collect_test_files() {
  local test_file
  local -i failed_files=0 index=0 test_status

  for test_file in "$@"; do
    index=$((index + 1))
    wait "${TEST_PIDS[index]}"
    test_status="$?"
    cat -- "${TEST_LOG_DIR}/${index}.log"

    if ((test_status != 0)); then
      print -r -- "${test_file:t} failed" >&2
      failed_files=$((failed_files + 1))
    fi
  done

  if ((failed_files > 0)); then
    print -r -- "${failed_files} test files failed" >&2

    return 1
  fi

  return 0
}

# Prints a process's ID, then its descendants', one per line.
list_process_tree() {
  if ((${#} != 1)); then
    print -r -- "list_process_tree needs a process ID" >&2

    return 2
  fi

  local child_pid child_text

  print -r -- "${1}"
  child_text="$(pgrep -P "${1}")"

  for child_pid in ${(f)child_text}; do
    list_process_tree "${child_pid}"
  done

  return 0
}

# Runs one test file, failing it if it prints a scope warning.
#
# - warn_create_global and warn_nested_var only warn, so a test could pass
#   while printing them, as one did.
#
# - This sees only the test file's own stderr. The hook tests record warnings
#   from the hooks they run themselves, through test/hook_helpers.zsh.
#
# - multios sends stderr both to the warnings file and to stdout, the file's
#   one log. The copy runs through a pipe, so stdout and stderr lines can land
#   slightly out of order.
run_test_file() {
  local warnings_file warnings_text
  local -i test_status

  if ! warnings_file="$(mktemp "${${TMPDIR:-/tmp}%/}/warnings.XXXXXX")"; then
    print -r -- "could not make a temporary file" >&2

    return 1
  fi

  /bin/zsh -f "${1}" 2> "${warnings_file}" 2>&1
  test_status="$?"
  warnings_text="$(< "${warnings_file}")"
  rm -f -- "${warnings_file}"

  if [[ ${warnings_text} == *(created globally|set in enclosing scope)* ]]; then
    print -r -- "${1:t} printed a zsh warning" >&2

    return 1
  fi

  return "${test_status}"
}

# Starts each test file in the background, keeping its output in a log.
#
# - A background job in a script starts with INT and QUIT ignored, which every
#   process it runs would inherit, so a test's signals would act differently
#   here than when run alone. Each job restores them first.
start_test_files() {
  local log_dir test_file
  local -i index=0

  if ! log_dir="$(mktemp -d "${${TMPDIR:-/tmp}%/}/test-logs.XXXXXX")"; then
    print -r -- "could not make a folder for the test output" >&2

    return 1
  fi

  typeset -g TEST_LOG_DIR="${log_dir}"

  for test_file in "$@"; do
    index=$((index + 1))
    {
      trap - INT QUIT
      run_test_file "${test_file}"
    } > "${log_dir}/${index}.log" 2>&1 &
    typeset -ga TEST_PIDS=("${TEST_PIDS[@]}" "$!")
  done

  return 0
}

# Stops every test file still running, and whatever each one started.
#
# - Background jobs in a script ignore SIGINT, so without this an interrupted
#   run would leave its test files running.
#
# - The whole tree is listed before anything is stopped, as a stopped parent's
#   children are moved to another parent and can't be found from it.
stop_test_files() {
  local test_pid
  local -a tree_pids=()

  for test_pid in "${TEST_PIDS[@]}"; do
    tree_pids+=("${(@f)$(list_process_tree "${test_pid}")}")
  done

  tree_pids=("${(@)tree_pids:#}")

  if ((${#tree_pids} > 0)); then
    kill -TERM -- "${tree_pids[@]}" 2> /dev/null
  fi

  return 0
}

# Runs the test files, and fails if any of them does.
main() {
  local -a test_files

  test_files=("$@")

  if ((${#test_files} == 0)); then
    test_files=("${TEST_DIR}"/*.test.zsh(N))
  fi

  if ((${#test_files} == 0)); then
    print -r -- "no test files found in ${TEST_DIR}" >&2

    return 1
  fi

  if ! start_test_files "${test_files[@]}"; then
    return 1
  fi

  collect_test_files "${test_files[@]}"

  return "$?"
}

# Removes the output folder however the run ends.
trap 'if [[ -n ${TEST_LOG_DIR} ]]; then rm -rf -- "${TEST_LOG_DIR:?}"; fi' EXIT
trap 'stop_test_files; exit 130' INT
trap 'stop_test_files; exit 143' TERM

main "$@"
exit "$?"
