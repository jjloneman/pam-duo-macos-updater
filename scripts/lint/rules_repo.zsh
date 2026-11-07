# Rules about the file as a whole, and about the repo.

typeset -gr NEWLINE=$'\n'
typeset -gra OKF_FIELDS=(description generated status title type)

# Reports an entry-point file missing part of the standard header.
check_header_part() {
  if ((${#} != 2)); then
    print -r -- "check_header_part needs a header and a part" >&2
    return 2
  fi

  if [[ ${1} != *"${2}"* ]]; then
    report 1 entry_header "the header needs: ${2}"
  fi

  return 0
}

# Checks one record's frontmatter block and required fields.
check_record_frontmatter() {
  if ((${#} != 1)); then
    print -r -- "check_record_frontmatter needs a path" >&2
    return 2
  fi

  local field record_text

  record_text="$(< "${1}")"
  typeset -g CURRENT_FILE="${1}"

  if [[ ${record_text} != "---${NEWLINE}"*"${NEWLINE}---"* ]]; then
    report 1 okf_frontmatter "a record needs a frontmatter block"
    return 0
  fi

  record_text="${record_text#---${NEWLINE}}"
  record_text="${NEWLINE}${record_text%%${NEWLINE}---*}"

  for field in "${OKF_FIELDS[@]}"; do
    if [[ ${record_text} != *"${NEWLINE}${field}:"* ]]; then
      report 1 okf_frontmatter "the frontmatter needs ${field}"
    fi
  done

  return 0
}

# Fails on a legacy entry for a file that no longer exists.
repo_rule_legacy_entry_exists() {
  local legacy_file

  typeset -g CURRENT_FILE="scripts/lint-legacy.txt"

  for legacy_file in "${LEGACY_FILES[@]}"; do
    if [[ ! -f ${legacy_file} ]]; then
      report 1 legacy_entry_exists "${legacy_file} doesn't exist"
    fi
  done

  return 0
}

# Requires a frontmatter block with the fields every record carries.
repo_rule_okf_frontmatter() {
  local record

  for record in docs/(decisions|playbooks|references)/*.md(N.); do
    if [[ ${record:t} != index.md ]]; then
      check_record_frontmatter "${record}"
    fi
  done

  return 0
}

# Requires an index.md in each bundle that lists every record in it.
repo_rule_okf_index() {
  local bundle index_text record

  for bundle in docs/(decisions|playbooks|references)(N/); do
    typeset -g CURRENT_FILE="${bundle}/index.md"

    if [[ ! -f ${bundle}/index.md ]]; then
      report 1 okf_index "a bundle needs an index.md"
      continue
    fi

    index_text="$(< "${bundle}/index.md")"

    for record in "${bundle}"/*.md(N.); do
      if [[ ${record:t} == index.md ]]; then
        continue
      fi

      if [[ ${index_text} != *"](${record:t})"* ]]; then
        report 1 okf_index "${record:t} isn't listed"
      fi
    done
  done

  return 0
}

# Requires the standard header in every entry point.
rule_entry_header() {
  if is_sourced_file "${CURRENT_FILE}"; then
    return 0
  fi

  local continuation="\\${NEWLINE}  "
  local header="${(F)SOURCE_LINES[1,15]}"
  local options_line="setopt no_short_loops no_unset pipe_fail typeset_silent"

  # A long setopt is continued on the next line, so join it before comparing.
  header="${header//${continuation}/}"
  check_header_part "${header}" "emulate -R zsh"
  check_header_part "${header}" \
    "${options_line} warn_create_global warn_nested_var"
  check_header_part "${header}" "unset CDPATH"
  check_header_part "${header}" "path=("
  check_header_part "${header}" "hash -r"
  return 0
}

# Requires the shebang and execute bit to match how the file is used.
rule_shebang() {
  local first_line="${SOURCE_LINES[1]:-}"

  if is_sourced_file "${CURRENT_FILE}"; then
    if [[ ${first_line} == \#!* ]]; then
      report 1 shebang "a sourced file has no shebang"
    fi

    if [[ -x ${CURRENT_FILE} ]]; then
      report 1 shebang "a sourced file isn't executable"
    fi

    return 0
  fi

  if [[ ${first_line} != '#!/bin/zsh -f' ]]; then
    report 1 shebang "the first line must be #!/bin/zsh -f"
  fi

  if [[ ! -x ${CURRENT_FILE} ]]; then
    report 1 shebang "an entry point must be executable"
  fi

  return 0
}

# Checks grammar by exit status, as `zsh -n` can print and still exit 0.
rule_zsh_syntax() {
  if ! /bin/zsh -d -f -n +o shortloops "${CURRENT_FILE}" 2> /dev/null; then
    report 1 zsh_syntax "zsh -n rejects this file"
  fi

  return 0
}
