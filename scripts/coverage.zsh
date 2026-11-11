#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent \
  warn_create_global warn_nested_var
unset CDPATH

# Keeps the caller's PATH, which the formatter test needs to find Node.
typeset -gx CALLER_PATH="${PATH}"
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r

# Measures which lines of the tool's code the tests run.
#
# - Run from the repo root, optionally naming test files relative to it. With
#   none, it runs every `test/*.test.zsh`.
#
# - It copies the tree to a scratch folder and inserts a DEBUG trap as line 2
#   of each file under `bin/`, `lib/` and `libexec/`, then counts every traced
#   line one lower. Line 1 stays, as a test may run the file by its shebang,
#   so it must be a shebang or a comment, which never runs.
#
# - The trap fires once per list, so in `false && print never` the line counts
#   as run. Lint requires every branch to be an `if`, which it can see.
#
# - Lines only a real run can reach are listed in `test/real-only.txt` as
#   `path:line: reason`, and left out of the totals.

# Inside a function, $0 is the function's name, so capture this here.
typeset -gr COVERAGE_LIB="${0:A:h}/coverage/lines.zsh"
typeset -gr COVERAGE_TARGETS_LIB="${0:A:h}/coverage/targets.zsh"
typeset -gr LINT_DIR="${0:A:h}/lint"
typeset -gr TEST_RUNNER="${0:A:h}/test.zsh"

# Lets lint's test of the repo check this tree rather than the traced copy,
# whose inserted trap lines run past 80 columns in every converted file.
typeset -gx COVERAGE_REPO_ROOT="${0:A:h:h}"

# The parts of the line inserted into each traced file, with @TRACE_FILE@
# standing for the trace.
#
# - It opens the trace once per process, then logs `file|definition|line` for
#   each command through a DEBUG trap.
#
# Order: the parts join into one line of code.
typeset -gra TRACE_LINE_PARTS=(
  'if ((!${+COVERAGE_TRACE_FD})); then typeset -gi COVERAGE_TRACE_FD;'
  'exec {COVERAGE_TRACE_FD}>>@TRACE_FILE@; fi;'
  "trap 'print -u \"\${COVERAGE_TRACE_FD}\" -r --"
  '"${(%):-%x}|${funcsourcetrace[1]:-}|${(%):-%I}"'"' DEBUG"
)

# One file's counts, which count_file_lines fills for report_file.
typeset -ga FILE_MISSED=() FILE_REAL_ONLY=()
typeset -gi FILE_HIT_COUNT=0 FILE_TOTAL=0

# Lines the tests ran, as `path:line` keys.
typeset -gA HIT_LINES=()

# Lines only a real run can reach, as `path:line` keys with their reasons.
typeset -gA REAL_ONLY=()

# Maps each traced file's name to its path, as tests run renamed copies.
typeset -gA TARGET_BY_NAME=()

# Real-only entries that named a statement, as `path:line` keys.
typeset -gA USED_REAL_ONLY=()

# How many case blocks the line being scanned is inside.
typeset -gi CASE_DEPTH=0

typeset -gi PROBLEM_COUNT=0

# Copies the tree to the scratch folder, linking node_modules rather than it.
#
# - In a git checkout, only the files git tracks or would add are copied, so
#   ignored folders aren't. A deleted file git still tracks is skipped.
copy_tree() {
  if ((${#} != 1)); then
    print -r -- "copy_tree needs a folder" >&2

    return 2
  fi

  local listing tree_file
  local -a tree_files=(.)

  # -z keeps names git would otherwise quote, such as non-ASCII ones.
  if listing="$(git ls-files -z -co --exclude-standard 2> /dev/null)"; then
    tree_files=()

    for tree_file in ${(0)listing}; do
      if [[ -e ${tree_file} ]]; then
        tree_files+=("./${tree_file}")
      fi
    done
  fi

  if ! /usr/bin/tar -c -f - --exclude ./.git --exclude ./node_modules \
    "${tree_files[@]}" | /usr/bin/tar -x -f - -C "${1}"; then
    print -r -- "could not copy the tree to ${1}" >&2

    return 1
  fi

  if [[ -d node_modules ]]; then
    if ! ln -s "${PWD}/node_modules" "${1}/node_modules"; then
      print -r -- "could not link node_modules" >&2

      return 1
    fi
  fi

  return 0
}

# Inserts the trace line after line 1 of the scratch copy.
instrument_file() {
  if ((${#} != 3)); then
    print -r -- "instrument_file needs a folder, a path and a trace" >&2

    return 2
  fi

  local first_line trace_line

  if ! IFS= read -r first_line < "${2}"; then
    print -r -- "could not read ${2}" >&2

    return 1
  fi

  if [[ ${first_line} != \#* ]]; then
    print -r -- "${2}: line 1 must be a shebang or a comment" >&2

    return 1
  fi

  trace_line="${(j: :)TRACE_LINE_PARTS}"
  trace_line="${trace_line//@TRACE_FILE@/${(q)3}}"

  if ! print -rl -- "${first_line}" "${trace_line}" > "${1}/${2}"; then
    print -r -- "could not instrument ${2}" >&2

    return 1
  fi

  if ! tail -n +2 "${2}" >> "${1}/${2}"; then
    print -r -- "could not instrument ${2}" >&2

    return 1
  fi

  return 0
}

# Runs the test files in the scratch copy through the repo's test runner.
#
# - The runner fails a test that prints a scope warning, so a run that fails
#   `pnpm test` fails here too.
run_tests() {
  if ((${#} < 2)); then
    print -r -- "run_tests needs a folder and test files" >&2

    return 2
  fi

  if ! /bin/zsh -f "${TEST_RUNNER}" "${(@)@[2,-1]/#/${1}/}" >&2; then
    return 1
  fi

  return 0
}

# Runs the tests in an instrumented scratch copy, and reads what they ran.
trace_tests() {
  local scratch_dir target

  if ! scratch_dir="$(mktemp -d "${${TMPDIR:-/tmp}%/}/coverage.XXXXXX")"; then
    print -r -- "could not make a scratch folder" >&2

    return 1
  fi

  typeset -g SCRATCH_DIR="${scratch_dir}"
  typeset -g VIEW_DIR="${scratch_dir}/views"

  if ! mkdir -- "${VIEW_DIR}"; then
    print -r -- "could not make ${VIEW_DIR}" >&2

    return 1
  fi

  if ! copy_tree "${scratch_dir}"; then
    return 1
  fi

  for target in "${(@v)TARGET_BY_NAME}"; do
    if ! instrument_file "${scratch_dir}" "${target}" \
      "${scratch_dir}/trace"; then
      return 1
    fi
  done

  : >> "${scratch_dir}/trace"

  if ! run_tests "${scratch_dir}" "$@"; then
    return 1
  fi

  read_trace "${scratch_dir}/trace"

  return 0
}

# Traces the tests, then reports each file's coverage.
main() {
  local target
  local -a test_files

  test_files=("$@")

  if ((${#test_files} == 0)); then
    test_files=(test/*.test.zsh(N))
  fi

  if ((${#test_files} == 0)); then
    print -r -- "found no test files to run" >&2

    return 1
  fi

  if ! map_targets; then
    return 1
  fi

  read_real_only

  if ! trace_tests "${test_files[@]}"; then
    return 1
  fi

  for target in "${(@ov)TARGET_BY_NAME}"; do
    report_file "${target}"
  done

  report_stale_real_only

  if ((PROBLEM_COUNT > 0)); then
    return 1
  fi

  return 0
}

typeset -g SCRATCH_DIR=""

# The folder lint's scanner writes its views to, under the scratch folder.
typeset -g VIEW_DIR=""

# A sourced file can stop partway and still return, so check each loaded.
#
# - Order: the coverage functions use lint's scanner, so it loads first.
if ! source "${LINT_DIR}/scan.zsh"; then
  print -r -- "could not load ${LINT_DIR}/scan.zsh" >&2
  exit 1
fi

if ! source "${COVERAGE_LIB}"; then
  print -r -- "could not load ${COVERAGE_LIB}" >&2
  exit 1
fi

if ! source "${COVERAGE_TARGETS_LIB}"; then
  print -r -- "could not load ${COVERAGE_TARGETS_LIB}" >&2
  exit 1
fi

# Removes the scratch copy however the run ends.
trap 'if [[ -n ${SCRATCH_DIR} ]]; then rm -rf -- "${SCRATCH_DIR:?}"; fi' EXIT

main "$@"
exit "$?"
