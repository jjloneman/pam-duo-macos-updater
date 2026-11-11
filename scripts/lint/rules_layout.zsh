# Rules about how a file is laid out.

typeset -gri FILE_LINE_LIMIT=300
typeset -gri FUNCTION_LINE_LIMIT=40
typeset -gri LINE_WIDTH_LIMIT=80

# Reports a comment that runs past 80 columns, for files exempt from
# line_width, including one after code.
#
# - A comment that starts past column 80 is left alone, as the code before it
#   is what's long, and legacy code is exempt.
check_comment_width() {
  local comment_text
  local -i comment_start index

  for ((index = 1; index <= ${#SOURCE_LINES}; index++)); do
    comment_text="${COMMENT_LINES[index]:-}"

    # The comment view holds only the comment, which ends the line.
    comment_start=$((${#SOURCE_LINES[index]} - ${#comment_text}))

    if [[ -z ${comment_text// /} ]]; then
      continue
    fi

    if ((comment_start >= LINE_WIDTH_LIMIT)); then
      continue
    fi

    if ((${#SOURCE_LINES[index]} > LINE_WIDTH_LIMIT)); then
      report "${index}" line_width "${#SOURCE_LINES[index]} columns, over 80"
    fi
  done

  return 0
}

# Reports whether the line before a statement lets it skip a blank line.
#
# - A comment belongs to what follows it, and the first statement in a block
#   needs no blank line.
is_clear_above() {
  if ((${#} != 1)); then
    print -r -- "is_clear_above needs a line number" >&2

    return 2
  fi

  local -i above=$((${1} - 1))

  if [[ -z ${SOURCE_LINES[above]} || -n ${COMMENT_LINES[above]:-} ]]; then
    return 0
  fi

  trim_line "${CODE_LINES[above]:-}"

  case "${TRIMMED_LINE}" in
    ")" | ")"\" | *"))")
      return 1
      ;;
    *"(" | *" do" | *" in" | *" then" | *"{" | do | else | then)
      return 0
      ;;
    *")")
      if [[ ${TRIMMED_LINE} != *([=]|'$(')* ]]; then
        return 0
      fi

      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# Reports whether the line after a statement lets it skip a blank line.
is_clear_below() {
  if ((${#} != 1)); then
    print -r -- "is_clear_below needs a line" >&2

    return 2
  fi

  # The first word only, so `file=1` doesn't read as `fi`.
  case "${1%% *}" in
    "" | ")"* | ";;" | done | elif | else | esac | fi | "}")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Requires a blank line around each multi-line statement.
rule_blank_around_multiline() {
  local code_line below
  local -i index

  for ((index = 2; index <= ${#CODE_LINES}; index++)); do
    code_line="${CODE_LINES[index]}"
    below="${SOURCE_LINES[index + 1]:-}"
    trim_line "${code_line}"

    if [[ ${TRIMMED_LINE} == (if|for|while|until|case)[[:space:]]* ]]; then
      if ! is_clear_above "${index}"; then
        report "${index}" blank_around_multiline "add a blank line above this"
      fi
    elif [[ ${TRIMMED_LINE} == (fi|done|esac|\}) ]]; then
      trim_line "${below}"

      if ! is_clear_below "${TRIMMED_LINE}"; then
        report "${index}" blank_around_multiline "add a blank line below this"
      fi
    fi
  done

  return 0
}

# Requires a blank line before a comment, unless it's first in its block.
rule_blank_before_comment() {
  local code_line
  local -i index

  for ((index = 2; index <= ${#SOURCE_LINES}; index++)); do
    code_line="${CODE_LINES[index]:-}"

    if [[ -n ${COMMENT_LINES[index]:-} && -z ${code_line// /} ]]; then
      if ! is_clear_above "${index}"; then
        report "${index}" blank_before_comment "add a blank line above this"
      fi
    fi
  done

  return 0
}

# Requires a blank line before `return`, unless it's first in its block.
#
# - The same padding ESLint's padding-line-between-statements gives `return`
#   in the owner's TypeScript repos.
rule_blank_before_return() {
  local -i index

  for ((index = 2; index <= ${#CODE_LINES}; index++)); do
    trim_line "${CODE_LINES[index]}"

    if [[ ${TRIMMED_LINE} == return || ${TRIMMED_LINE} == "return "* ]]; then
      if ! is_clear_above "${index}"; then
        report "${index}" blank_before_return "add a blank line above this"
      fi
    fi
  done

  return 0
}

# Requires a comment directly above every function.
rule_doc_comment() {
  local -i index

  for ((index = 1; index <= ${#FUNCTION_STARTS}; index++)); do
    if [[ -z ${COMMENT_LINES[FUNCTION_STARTS[index] - 1]:-} ]]; then
      report "${FUNCTION_STARTS[index]}" doc_comment \
        "${FUNCTION_NAMES[index]} needs a doc comment"
    fi
  done

  return 0
}

# Limits a file to 300 lines.
rule_file_limit() {
  if ((${#SOURCE_LINES} > FILE_LINE_LIMIT)); then
    report 1 file_limit "${#SOURCE_LINES} lines, over ${FILE_LINE_LIMIT}"
  fi

  return 0
}

# Limits a function to 40 lines.
rule_function_limit() {
  local -i index line_count

  for ((index = 1; index <= ${#FUNCTION_STARTS}; index++)); do
    line_count=$((FUNCTION_ENDS[index] - FUNCTION_STARTS[index] + 1))

    if ((line_count > FUNCTION_LINE_LIMIT)); then
      report "${FUNCTION_STARTS[index]}" function_limit \
        "${FUNCTION_NAMES[index]} is ${line_count} lines, over 40"
    fi
  done

  return 0
}

# Limits a file to 80 columns.
rule_line_width() {
  local source_line
  local -i index=0

  for source_line in "${SOURCE_LINES[@]}"; do
    index=$((index + 1))

    if ((${#source_line} > LINE_WIDTH_LIMIT)); then
      report "${index}" line_width "${#source_line} columns, over 80"
    fi
  done

  return 0
}

# Rejects `$0` in a function, where it's the function's name, not the script's.
#
# - A test runner once looked for its tests beside `${0:A:h}`, found none, and
#   reported success. Capture the path at the top level instead.
rule_no_argzero_in_function() {
  local -i index last_row row

  for ((index = 1; index <= ${#FUNCTION_STARTS}; index++)); do
    last_row="${FUNCTION_ENDS[index]:-0}"

    for ((row = FUNCTION_STARTS[index]; row <= last_row; row++)); do
      if [[ ${EXPAND_LINES[row]:-} == *'${0'* ]]; then
        report "${row}" no_argzero_in_function "capture it at the top level"
      fi
    done
  done

  return 0
}
