# Reads a file into the views the rules check, and reports what they find.

# The lines of the file being checked, one array per view.
typeset -ga CODE_LINES COMMENT_LINES SOURCE_LINES

# The file's statements, with continued lines joined.
typeset -ga STATEMENT_LINES STATEMENT_TEXTS

# The top-level functions of the file being checked.
typeset -ga FUNCTION_ENDS FUNCTION_NAMES FUNCTION_STARTS

# Lists what the last call to read_declared_names found on its line.
typeset -ga DECLARED_NAMES

# Lists the files `scripts/lint-legacy.txt` exempts from style rules.
typeset -ga LEGACY_FILES

typeset -g CURRENT_FILE=""
typeset -gi FINDING_COUNT=0
typeset -gi TOOL_ERROR_COUNT=0
typeset -g TRIMMED_LINE=""

# Finds each top-level function's name and the lines it spans.
collect_functions() {
  local -i index=0 is_open=0
  local code_line function_name

  typeset -ga FUNCTION_ENDS=() FUNCTION_NAMES=() FUNCTION_STARTS=()

  for code_line in "${CODE_LINES[@]}"; do
    index=$((index + 1))

    if [[ ${code_line} == [A-Za-z_]*"() {"* ]]; then
      function_name="${code_line%%\(*}"
      typeset -ga FUNCTION_NAMES=("${FUNCTION_NAMES[@]}" "${function_name}")
      typeset -ga FUNCTION_STARTS=("${FUNCTION_STARTS[@]}" "${index}")
      is_open=1
    fi

    # Only an open function can close, so a plain `{ ...; }` block can't shift
    # the spans, and a function may close on the line that opened it.
    if ((is_open)); then
      if [[ ${code_line} == "}"* || ${code_line} == *"() {"*"}"* ]]; then
        typeset -ga FUNCTION_ENDS=("${FUNCTION_ENDS[@]}" "${index}")
        is_open=0
      fi
    fi
  done

  return 0
}

# Joins continued lines and open parentheses into one statement each.
#
# - A multi-line array can hold a command, so it has to read as one statement.
#
# - A case branch's `)` has no opener, so the count never goes below zero.
collect_statements() {
  local closers code_line openers statement=""
  local -i index=0 open_count=0 start=0

  typeset -ga STATEMENT_LINES=() STATEMENT_TEXTS=()

  for code_line in "${CODE_LINES[@]}"; do
    index=$((index + 1))

    if [[ -z ${statement} ]]; then
      start="${index}"
    fi

    statement+=" ${code_line%\\}"
    openers="${code_line//[^\(]/}"
    closers="${code_line//[^\)]/}"
    open_count=$((open_count + ${#openers} - ${#closers}))

    if ((open_count < 0)); then
      open_count=0
    fi

    if [[ ${code_line} != *\\ ]]; then
      if ((open_count == 0)); then
        typeset -ga STATEMENT_LINES=("${STATEMENT_LINES[@]}" "${start}")
        typeset -ga STATEMENT_TEXTS=("${STATEMENT_TEXTS[@]}" "${statement}")
        statement=""
      fi
    fi
  done

  # One statement per line, which report_pattern maps back to its source line.
  print -rl -- "${STATEMENT_TEXTS[@]}" > "${VIEW_DIR:?}/statement"
  return 0
}

# Prints the zsh files under the current directory, one per line.
discover_targets() {
  local -a targets

  targets=(
    .githooks/*(N.)
    bin/*(N.)
    lib/*.zsh(N.)
    libexec/*(N.)
    scripts/*.zsh(N.)
    scripts/lint/*.zsh(N.)
    test/*.zsh(N.)
  )
  print -rl -- "${targets[@]}"
  return 0
}

# Reports whether the file is sourced, rather than run as a command.
is_sourced_file() {
  if ((${#} != 1)); then
    print -r -- "is_sourced_file needs a path" >&2
    return 2
  fi

  if [[ ${1} == (lib/*|scripts/lint/*|test/*helpers.zsh) ]]; then
    return 0
  fi

  return 1
}

# Loads the file's views into arrays and files for the rules to read.
load_views() {
  if ((${#} != 1)); then
    print -r -- "load_views needs a path" >&2
    return 2
  fi

  local view_name view_text

  typeset -g CURRENT_FILE="${1}"

  for view_name in code comment expand; do
    if ! LC_ALL=C /usr/bin/awk -v view="${view_name}" \
      -f "${LINT_DIR}/mask.awk" "${1}" > "${VIEW_DIR:?}/${view_name}"; then
      tool_error "could not read ${1}"
      return 2
    fi
  done

  # (f) splits on newlines, and @ with quotes keeps the blank lines.
  view_text="$(< "${1}")"
  typeset -ga SOURCE_LINES=("${(@f)view_text}")
  view_text="$(< "${VIEW_DIR}/code")"
  typeset -ga CODE_LINES=("${(@f)view_text}")
  view_text="$(< "${VIEW_DIR}/comment")"
  typeset -ga COMMENT_LINES=("${(@f)view_text}")
  collect_functions
  collect_statements
  return 0
}

# Reads the legacy list, ignoring blank lines and comments.
read_legacy_list() {
  local list_line

  typeset -ga LEGACY_FILES=()

  if [[ ! -f scripts/lint-legacy.txt ]]; then
    return 0
  fi

  for list_line in "${(@f)$(< scripts/lint-legacy.txt)}"; do
    if [[ -n ${list_line} && ${list_line} != \#* ]]; then
      typeset -ga LEGACY_FILES=("${LEGACY_FILES[@]}" "${list_line}")
    fi
  done

  return 0
}

# Prints one finding and counts it.
report() {
  if ((${#} != 3)); then
    print -r -- "report needs a line, a rule and a message" >&2
    return 2
  fi

  print -r -- "${CURRENT_FILE}:${1}: ${2}: ${3}"
  typeset -gi FINDING_COUNT=$((FINDING_COUNT + 1))
  return 0
}

# Reports each `line:text` match, mapping a statement back to its first line.
report_matches() {
  if ((${#} != 4)); then
    print -r -- "report_matches needs a rule, view, message and matches" >&2
    return 2
  fi

  local line_number match

  for match in "${(@f)4}"; do
    if [[ -z ${match} ]]; then
      continue
    fi

    line_number="${match%%:*}"

    if [[ ${2} == statement ]]; then
      line_number="${STATEMENT_LINES[line_number]}"
    fi

    report "${line_number}" "${1}" "${3}"
  done

  return 0
}

# Reports every line of a view that matches a regex.
#
# - The optional fifth argument is a regex that clears a matching line.
report_pattern() {
  if ((${#} < 4 || ${#} > 5)); then
    print -r -- "report_pattern needs a rule, view, regex and message" >&2
    return 2
  fi

  local rule_name="${1}" view_name="${2}" regex="${3}" message="${4}"
  local exclude="${5:-^$}" matches
  local -i search_status

  # Two steps, as pipe_fail would let the second grep's 1 hide the first's 2.
  matches="$(/usr/bin/grep -nE -- "${regex}" "${VIEW_DIR}/${view_name}")"
  search_status="$?"

  if ((search_status > 1)); then
    tool_error "grep failed for ${rule_name}"
    return 2
  fi

  if [[ -z ${matches} ]]; then
    return 0
  fi

  matches="$(print -r -- "${matches}" | /usr/bin/grep -vE -- "${exclude}")"
  search_status="$?"

  if ((search_status > 1)); then
    tool_error "the exclude grep failed for ${rule_name}"
    return 2
  fi

  report_matches "${rule_name}" "${view_name}" "${message}" "${matches}"
  return 0
}

# Prints an error from the tool itself, which fails the run however clean.
tool_error() {
  print -r -- "lint error: ${1:-unknown}" >&2
  typeset -gi TOOL_ERROR_COUNT=$((TOOL_ERROR_COUNT + 1))
  return 0
}

# Puts a line with its outer whitespace removed into TRIMMED_LINE.
#
# - It avoids `[[:space:]]#`, which needs extended_glob, and sets a global
#   because this runs for every line, where `$(...)` would fork each time.
trim_line() {
  if ((${#} != 1)); then
    print -r -- "trim_line needs a line" >&2
    return 2
  fi

  local trimmed="${1}"

  trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  typeset -g TRIMMED_LINE="${trimmed}"
  return 0
}
