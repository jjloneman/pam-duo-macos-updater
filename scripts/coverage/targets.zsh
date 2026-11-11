# Finds the files to trace, and reads and checks the real-only list.
#
# - Sourced by `scripts/coverage.zsh`, which declares the tables these
#   functions fill.

# Reports whether a file is zsh: a `lib/*.zsh` file, or one with a zsh shebang.
#
# - The trace line is zsh, so any other script would break with it inserted.
is_zsh_file() {
  if ((${#} != 1)); then
    print -r -- "is_zsh_file needs a path" >&2

    return 2
  fi

  local first_line=""

  if [[ ${1} == lib/*.zsh ]]; then
    return 0
  fi

  if ! IFS= read -r first_line < "${1}"; then
    return 1
  fi

  if [[ ${first_line} == "#!"*zsh* ]]; then
    return 0
  fi

  return 1
}

# Maps each zsh file under bin/, lib/ and libexec/ by name, failing on a clash.
map_targets() {
  local target
  local -a targets

  targets=(bin/*(N.) lib/*.zsh(N.) libexec/*(N.))

  if ((${#targets} == 0)); then
    print -r -- "found nothing to trace under bin/, lib/ or libexec/" >&2

    return 1
  fi

  for target in "${targets[@]}"; do
    if ! is_zsh_file "${target}"; then
      print -r -- "skipping ${target}: not a zsh file" >&2
      continue
    fi

    if [[ -n ${TARGET_BY_NAME[${target:t}]:-} ]]; then
      print -r -- "two traced files are named ${target:t}" >&2

      return 1
    fi

    TARGET_BY_NAME[${target:t}]="${target}"
  done

  if ((${#TARGET_BY_NAME} == 0)); then
    print -r -- "found no zsh files to trace" >&2

    return 1
  fi

  return 0
}

# Reads `test/real-only.txt`, if there is one, into REAL_ONLY.
read_real_only() {
  local entry list_text

  if [[ ! -f test/real-only.txt ]]; then
    return 0
  fi

  list_text="$(< test/real-only.txt)"

  for entry in "${(@f)list_text}"; do
    if [[ -z ${entry} || ${entry} == \#* ]]; then
      continue
    fi

    if [[ ${entry} != *:*': '?* || ${${entry%%: *}##*:} != <-> ]]; then
      print -r -- "test/real-only.txt: not path:line: reason: ${entry}" >&2
      typeset -gi PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
      continue
    fi

    if [[ -n ${REAL_ONLY[${entry%%: *}]:-} ]]; then
      print -r -- "test/real-only.txt: ${entry%%: *} is listed twice" >&2
      typeset -gi PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
      continue
    fi

    REAL_ONLY[${entry%%: *}]="${entry#*: }"
  done

  return 0
}

# Fails on a real-only entry that's stale.
#
# - An entry is stale if the tests ran its line, its path isn't a traced file,
#   or its line isn't a statement, such as after code moved. Each would hide
#   or misplace a line in the totals.
report_stale_real_only() {
  local line_key stale_reason
  local -a target_paths
  local -i stale_count=0

  target_paths=("${(@v)TARGET_BY_NAME}")

  for line_key in "${(@k)REAL_ONLY}"; do
    stale_reason=""

    if [[ -n ${HIT_LINES[${line_key}]:-} ]]; then
      stale_reason="the tests ran it"
    elif ((${target_paths[(Ie)${line_key%:*}]} == 0)); then
      stale_reason="isn't a traced file"
    elif [[ -z ${USED_REAL_ONLY[${line_key}]:-} ]]; then
      stale_reason="isn't a statement"
    fi

    if [[ -n ${stale_reason} ]]; then
      print -r -- "${line_key}: listed as real-only, but ${stale_reason}" >&2
      stale_count=$((stale_count + 1))
    fi
  done

  typeset -gi PROBLEM_COUNT=$((PROBLEM_COUNT + stale_count))

  return 0
}
