# Scratch repos and a stub pnpm for the hook tests.
#
# - Every helper stops the run rather than act outside SCRATCH_ROOT, as a
#   failed step could otherwise leave a test working in the real repo.

# Stops the run, because a scratch step failed.
abort_setup() {
  print -r -- "hook test setup failed: ${1:-unknown}" >&2
  exit 2
}

# Fails a check if any hook printed a zsh scope warning during the run.
check_no_hook_warnings() {
  local warnings_text=""

  if [[ -f ${SCRATCH_ROOT}/warnings ]]; then
    warnings_text="$(< "${SCRATCH_ROOT}/warnings")"
  fi

  expect_equal "the hooks print no zsh warnings" "" "${warnings_text}"
  return 0
}

# Runs git with an identity, and without this repo's hooks, for test setup.
git_setup() {
  if ! is_in_scratch; then
    abort_setup "git ran outside the scratch folder"
  fi

  git -c user.name=test -c user.email=test@example.com \
    -c commit.gpgsign=false "$@"
  return "$?"
}

# Reports whether the working folder is inside SCRATCH_ROOT.
is_in_scratch() {
  if [[ -n ${SCRATCH_ROOT:-} && ${PWD:A} == "${SCRATCH_ROOT:A}"/* ]]; then
    return 0
  fi

  return 1
}

# Makes a repo with no tooling, and enters it.
new_plain_repo() {
  local repo_path

  if ! repo_path="$(mktemp -d "${SCRATCH_ROOT}/repo.XXXXXX")"; then
    abort_setup "mktemp failed"
  fi

  if ! cd -- "${repo_path}"; then
    abort_setup "could not enter ${repo_path}"
  fi

  if ! is_in_scratch; then
    abort_setup "${PWD} is outside the scratch folder"
  fi

  if ! git init --quiet; then
    abort_setup "git init failed"
  fi

  return 0
}

# Makes a repo with this repo's lint committed, and enters it.
new_scratch_repo() {
  new_plain_repo

  if ! cp -R -- "${REPO_ROOT}/scripts" scripts; then
    abort_setup "could not copy scripts"
  fi

  if ! git_setup add -- scripts; then
    abort_setup "could not stage scripts"
  fi

  if ! git_setup commit --quiet --no-verify -m tooling; then
    abort_setup "could not commit scripts"
  fi

  return 0
}

# Removes the scratch repos.
remove_scratch() {
  rm -rf -- "${SCRATCH_ROOT:?}"
  return 0
}

# Runs pre-commit with the stub pnpm first on PATH.
run_pre_commit() {
  if ! is_in_scratch; then
    abort_setup "pre-commit ran outside the scratch folder"
  fi

  run_watching_warnings /usr/bin/env PATH="${SCRATCH_ROOT}/stub:${PATH}" \
    "${REPO_ROOT}/.githooks/pre-commit"
  return "$?"
}

# Runs a command, passing its stderr on, and records any zsh scope warning.
#
# - Tests often hide a hook's output, so warnings go to a file that
#   check_no_hook_warnings reads, which also works from inside `$(...)`.
run_watching_warnings() {
  local stderr_file="${SCRATCH_ROOT}/stderr.$$" stderr_text
  local -i run_status

  "$@" 2> "${stderr_file}"
  run_status="$?"
  stderr_text="$(< "${stderr_file}")"
  rm -f -- "${stderr_file}"

  if [[ -n ${stderr_text} ]]; then
    print -r -- "${stderr_text}" >&2
  fi

  if [[ ${stderr_text} == *(created globally|set in enclosing scope)* ]]; then
    print -r -- "${stderr_text}" >> "${SCRATCH_ROOT}/warnings"
  fi

  return "${run_status}"
}

# Isolates git from this machine and the calling hook, and makes the scratch
# folder and stub.
#
# - A hook exports GIT_DIR and others, which would aim git at the real repo.
#
# - Global and system config, such as an excludesFile, would make results
#   depend on the machine.
start_scratch() {
  local -a git_variables
  local scratch_path

  git_variables=(${(f)"$(git rev-parse --local-env-vars)"})
  unset "${git_variables[@]}"
  typeset -gx GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

  if ! scratch_path="$(mktemp -d "${${TMPDIR:-/tmp}%/}/hook-test.XXXXXX")"; then
    abort_setup "mktemp failed"
  fi

  typeset -g SCRATCH_ROOT="${scratch_path}"
  write_stub_pnpm
  return 0
}

# Writes a stub pnpm that marks notes.md as reformatted, once.
#
# - STUB_FAIL makes it fail after rewriting, STUB_HOLD_INDEX makes the
#   re-stage fail, as a lock held by another git process would, and STUB_SLEEP
#   holds the hook mid-run so a test can signal it.
#
# - It logs its arguments to .git/stub-arguments, so a test can see what the
#   hook passed to the formatter.
write_stub_pnpm() {
  local stub_path="${SCRATCH_ROOT}/stub/pnpm"
  local -a stub_lines=(
    '#!/bin/sh'
    'printf "%s\\n" "$@" >>.git/stub-arguments'
    'if [ "${STUB_SLEEP:-}" = 1 ]; then'
    '  sleep 5'
    'fi'
    'if [ -f notes.md ] && ! grep -qx formatted notes.md; then'
    '  printf "formatted\n" >>notes.md'
    'fi'
    'if [ "${STUB_HOLD_INDEX:-}" = 1 ]; then'
    '  : >.git/index.lock'
    'fi'
    'if [ "${STUB_FAIL:-}" = 1 ]; then'
    '  exit 2'
    'fi'
  )

  if ! mkdir -p -- "${stub_path:h}"; then
    abort_setup "could not make the stub folder"
  fi

  if ! print -rl -- "${stub_lines[@]}" > "${stub_path}"; then
    abort_setup "could not write the stub pnpm"
  fi

  if ! chmod +x "${stub_path}"; then
    abort_setup "could not make the stub pnpm executable"
  fi

  return 0
}
