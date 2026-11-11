# Reads which lines of a file can run, which ran, and reports the difference.
#
# - Sourced by `scripts/coverage.zsh`, after `scripts/lint/scan.zsh`, whose
#   collect_statements and trim_line it uses. The entry point declares the
#   tables these functions fill.

# Counts one file's lines into the FILE_ globals, leaving real-only ones out.
count_file_lines() {
  if ((${#} != 1)); then
    print -r -- "count_file_lines needs a path" >&2

    return 2
  fi

  local file_lines line_key line_number

  typeset -ga FILE_MISSED=() FILE_REAL_ONLY=()
  typeset -gi FILE_HIT_COUNT=0 FILE_TOTAL=0

  if ! file_lines="$(list_statement_lines "${1}")"; then
    return 1
  fi

  for line_number in ${(f)file_lines}; do
    line_key="${1}:${line_number}"

    if [[ -n ${REAL_ONLY[${line_key}]:-} ]]; then
      USED_REAL_ONLY[${line_key}]=1
      typeset -ga FILE_REAL_ONLY=("${FILE_REAL_ONLY[@]}"
        "  real-only ${line_key}: ${REAL_ONLY[${line_key}]}")
      continue
    fi

    typeset -gi FILE_TOTAL=$((FILE_TOTAL + 1))

    if [[ -n ${HIT_LINES[${line_key}]:-} ]]; then
      typeset -gi FILE_HIT_COUNT=$((FILE_HIT_COUNT + 1))
    else
      typeset -ga FILE_MISSED=("${FILE_MISSED[@]}" "${line_number}")
    fi
  done

  return 0
}

# Reports whether a line of the code view is structure the trap never sees.
#
# - A case pattern ends in `)`, and so can an empty branch's `) ;;`. Arrays,
#   command substitutions and lines starting with `(` also end in `)`, but are
#   statements, so they're ruled out first.
#
# - Zsh also allows `(pattern)`. Inside a case block, a `(word)` line with
#   nothing after it but `;;` is one, and elsewhere it's a subshell.
#
# - The catch-all deliberately accepts anything else as a statement.
is_structure_line() {
  if ((${#} != 2)); then
    print -r -- "is_structure_line needs a line and whether it's in a case" >&2

    return 2
  fi

  trim_line "${1}"

  local after_paren="${TRIMMED_LINE#*\)}"
  local pattern_text="${TRIMMED_LINE%%\)*}"

  if [[ ${2} == 1 && ${TRIMMED_LINE} == "("[^"("]* &&
    ${pattern_text} != *" "* ]]; then
    if [[ -z ${after_paren} || ${after_paren} == (" ;;"|";;") ]]; then
      return 0
    fi
  fi

  if [[ ${TRIMMED_LINE} == "("* || ${TRIMMED_LINE} == *'=('* ||
    ${TRIMMED_LINE} == *'$('* ]]; then
    return 1
  fi

  case "${TRIMMED_LINE}" in
    "" | "{" | "}"* | ";;" | do | "done"* | else | esac | fi | then)
      return 0
      ;;
    *")" | *") ;;" | *");;")
      return 0
      ;;
    [A-Za-z_]*"() {")
      return 0
      ;;
    *) ;;
  esac

  return 1
}

# Prints the lines of a file where a statement starts, one per line.
#
# - It reads statements with lint's own scanner, so both agree on where each
#   one starts, and tracks case blocks for is_structure_line.
#
# - Line 1 is skipped, as it's always a shebang or a comment.
#
# - Only these lines count. The trace also sees function definitions, which
#   would count a function as run before anything called it.
list_statement_lines() {
  if ((${#} != 1)); then
    print -r -- "list_statement_lines needs a path" >&2

    return 2
  fi

  local -i line_number

  if ! load_code_view "${1}"; then
    return 1
  fi

  typeset -gi CASE_DEPTH=0

  for line_number in "${STATEMENT_LINES[@]}"; do
    track_case_depth "${CODE_LINES[line_number]}"

    if ((line_number == 1)); then
      continue
    fi

    # A line ending in `|`, `||` or `&&` continues onto this one, as the
    # formatter breaks after the operator inside `[[ ]]`.
    #
    # - Lint keeps them apart, so its findings stay on the line they're about.
    trim_line "${CODE_LINES[line_number - 1]}"

    if [[ ${TRIMMED_LINE} == *"|" || ${TRIMMED_LINE} == *"&&" ]]; then
      continue
    fi

    if ! is_structure_line "${CODE_LINES[line_number]}" \
      "$((CASE_DEPTH > 0))"; then
      print -r -- "${line_number}"
    fi
  done

  return 0
}

# Loads a file's code view and statements, the parts of lint's views it uses.
#
# - Lint's load_views also builds the comment and expand views and function
#   spans, which coverage never reads.
load_code_view() {
  if ((${#} != 1)); then
    print -r -- "load_code_view needs a path" >&2

    return 2
  fi

  local code_view

  if ! code_view="$(LC_ALL=C /usr/bin/awk -v view=code \
    -f "${LINT_DIR}/mask.awk" "${1}")"; then
    print -r -- "could not read ${1}" >&2

    return 1
  fi

  typeset -ga CODE_LINES=("${(@f)code_view}")
  collect_statements

  return 0
}

# Reads the trace into HIT_LINES, keeping only the traced files.
#
# - Each entry is `file|definition|line`. Inside a function, the line counts
#   from where the function was defined, which the definition names.
#
# - The trap is the copy's line 2, so each line is one lower in the source.
read_trace() {
  if ((${#} != 1)); then
    print -r -- "read_trace needs a path" >&2

    return 2
  fi

  local file_name hit_key line_number trace_entry trace_text
  local -a fields

  trace_text="$(< "${1}")"

  for trace_entry in "${(@f)trace_text}"; do
    fields=("${(@s:|:)trace_entry}")

    if [[ ${#fields} -ne 3 || ${fields[-1]} != <-> ]]; then
      continue
    fi

    file_name="${fields[1]}"
    line_number=0

    if [[ -n ${fields[2]} ]]; then
      file_name="${fields[2]%:*}"
      line_number="${fields[2]##*:}"
    fi

    if [[ ${line_number} != <-> || ${#line_number} -gt 9 ]]; then
      continue
    fi

    if [[ ${#fields[3]} -le 9 && -n ${TARGET_BY_NAME[${file_name:t}]:-} ]]; then
      line_number=$((line_number + fields[3] - 1))
      hit_key="${TARGET_BY_NAME[${file_name:t}]}:${line_number}"
      HIT_LINES[${hit_key}]=1
    fi
  done

  return 0
}

# Prints one file's total, the lines it missed and its real-only lines.
report_file() {
  if ((${#} != 1)); then
    print -r -- "report_file needs a path" >&2

    return 2
  fi

  local -i share=100

  if ! count_file_lines "${1}"; then
    return 1
  fi

  if ((FILE_TOTAL > 0)); then
    share=$((FILE_HIT_COUNT * 100 / FILE_TOTAL))
  fi

  print -r -- "${1}: ${FILE_HIT_COUNT} of ${FILE_TOTAL} lines (${share}%)"

  if ((${#FILE_MISSED} > 0)); then
    print -r -- "  missed: ${(j:, :)FILE_MISSED}"
  fi

  if ((${#FILE_REAL_ONLY} > 0)); then
    print -rl -- "${FILE_REAL_ONLY[@]}"
  fi

  return 0
}

# Counts the case blocks a statement line opens or closes into CASE_DEPTH.
track_case_depth() {
  if ((${#} != 1)); then
    print -r -- "track_case_depth needs a line" >&2

    return 2
  fi

  trim_line "${1}"

  if [[ ${TRIMMED_LINE} == "case "* ]]; then
    typeset -gi CASE_DEPTH=$((CASE_DEPTH + 1))
  fi

  if [[ ${TRIMMED_LINE} == *esac && ${CASE_DEPTH} -gt 0 ]]; then
    typeset -gi CASE_DEPTH=$((CASE_DEPTH - 1))
  fi

  return 0
}
