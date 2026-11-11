# A scratch copy of the coverage fixture, and the tool run against it.
#
# - Sourced by `test/coverage.test.zsh`, which sets COVERAGE_COMMAND and
#   FIXTURE_DIR first.

typeset -g COVERAGE_OUTPUT=""
typeset -gi COVERAGE_STATUS=0
typeset -g PROBE_ROOT=""

# Replaces the scratch folder with a fresh copy of the fixture.
#
# - A test case can't run without it, so a failure stops the whole file.
copy_fixture() {
  local probe_root

  remove_probe_root

  if ! probe_root="$(mktemp -d "${${TMPDIR:-/tmp}%/}/coverage.XXXXXX")"; then
    print -r -- "the coverage tests need a scratch folder" >&2

    exit 1
  fi

  typeset -g PROBE_ROOT="${probe_root}"

  if ! cp -R -- "${FIXTURE_DIR}/" "${PROBE_ROOT}"; then
    print -r -- "the coverage tests need a copy of the fixture" >&2

    exit 1
  fi

  return 0
}

# Runs the tool and checks that it fails with the message given.
expect_run_fails() {
  if ((${#} != 1)); then
    print -r -- "expect_run_fails needs a message" >&2

    return 2
  fi

  run_coverage
  expect_equal "status" "1" "${COVERAGE_STATUS}"
  expect_contains "message" "${1}" "${COVERAGE_OUTPUT}"

  return 0
}

# Removes the scratch folder, if there is one.
remove_probe_root() {
  if [[ -n ${PROBE_ROOT} ]]; then
    rm -rf -- "${PROBE_ROOT:?}"
  fi

  typeset -g PROBE_ROOT=""

  return 0
}

# Runs the tool from the scratch folder, keeping its output and status.
run_coverage() {
  local coverage_output
  local -i coverage_status

  coverage_output="$(
    if cd "${PROBE_ROOT:?}"; then
      /bin/zsh -f "${COVERAGE_COMMAND}" "$@" 2>&1
    else
      exit 9
    fi
  )"
  coverage_status="$?"
  typeset -g COVERAGE_OUTPUT="${coverage_output}"
  typeset -gi COVERAGE_STATUS="${coverage_status}"

  return 0
}
