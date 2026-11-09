# Rules that keep declarations in lexicographic order, ignoring case.
#
# - A `# Order:` comment directly above an item says why it's out of order,
#   and lint accepts it.

# Reports a `case` branch that's out of order, or follows the catch-all.
check_branch_order() {
  if ((${#} != 3)); then
    print -r -- "check_branch_order needs a line and two patterns" >&2
    return 2
  fi

  local -i index="${1}"
  local branch="${2}" previous="${3}"

  if [[ ${previous} == "*" ]]; then
    report "${index}" sorted_case_branches "the catch-all must be last"
    return 0
  fi

  if [[ ${branch} == "*" || -z ${previous} || ${branch} > ${previous} ]]; then
    return 0
  fi

  if ! has_order_comment "${index}"; then
    report "${index}" sorted_case_branches \
      "${branch} belongs before ${previous}"
  fi

  return 0
}

# Reports whether the line above carries an `# Order:` comment.
has_order_comment() {
  if ((${#} != 1)); then
    print -r -- "has_order_comment needs a line number" >&2
    return 2
  fi

  if [[ ${COMMENT_LINES[${1} - 1]:-} == *"# Order:"* ]]; then
    return 0
  fi

  return 1
}

# Checks that `case` branches are sorted, with the catch-all last.
rule_sorted_case_branches() {
  local -a previous_patterns=()
  local branch_pattern code_line
  local -i index=0 expects_branch=0

  for code_line in "${CODE_LINES[@]}"; do
    index=$((index + 1))
    trim_line "${code_line}"

    if [[ ${TRIMMED_LINE} == case[[:space:]]* ]]; then
      previous_patterns+=("")

      # A first branch on the `case` line is fine, and just isn't compared.
      expects_branch=0

      if [[ ${TRIMMED_LINE} == *[[:space:]]in ]]; then
        expects_branch=1
      fi
    elif [[ ${TRIMMED_LINE} == esac* ]]; then
      previous_patterns=("${(@)previous_patterns[1,-2]}")
      expects_branch=0
    elif [[ ${expects_branch} == 1 && -n ${TRIMMED_LINE} ]]; then
      trim_line "${SOURCE_LINES[index]}"
      branch_pattern="${(L)TRIMMED_LINE%\)*}"
      check_branch_order "${index}" "${branch_pattern}" \
        "${previous_patterns[-1]}"
      previous_patterns[-1]="${branch_pattern}"
      expects_branch=0
    fi

    trim_line "${code_line}"

    if [[ ${TRIMMED_LINE} == *\;\; && ${#previous_patterns} -gt 0 ]]; then
      expects_branch=1
    fi
  done

  return 0
}

# Checks that consecutive `typeset -g...r` constants are sorted.
rule_sorted_constants() {
  local -a words
  local code_line constant_name previous_name=""
  local -i index=0

  for code_line in "${CODE_LINES[@]}"; do
    index=$((index + 1))
    words=(${=code_line})

    if [[ ${words[1]:-} != typeset || ${words[2]:-} != -g*r* ]]; then
      if ((${#words} > 0)); then
        previous_name=""
      fi

      continue
    fi

    constant_name="${words[3]%%=*}"

    if [[ -n ${previous_name} ]]; then
      if [[ ${(L)constant_name} < ${(L)previous_name} ]]; then
        if ! has_order_comment "${index}"; then
          report "${index}" sorted_constants \
            "${constant_name} belongs before ${previous_name}"
        fi
      fi
    fi

    previous_name="${constant_name}"
  done

  return 0
}

# Checks that functions are sorted, with `main` last.
rule_sorted_functions() {
  local function_name lower_name previous_name=""
  local -i index

  for ((index = 1; index <= ${#FUNCTION_NAMES}; index++)); do
    function_name="${FUNCTION_NAMES[index]}"
    lower_name="${(L)function_name}"

    if [[ ${previous_name} == main ]]; then
      report "${FUNCTION_STARTS[index]}" sorted_functions "main must be last"
    elif [[ ${function_name} != main && -n ${previous_name} ]]; then
      if [[ ${lower_name} < ${(L)previous_name} ]]; then
        if ! has_order_comment "${FUNCTION_STARTS[index]}"; then
          report "${FUNCTION_STARTS[index]}" sorted_functions \
            "${function_name} belongs before ${previous_name}"
        fi
      fi
    fi

    previous_name="${function_name}"
  done

  return 0
}
