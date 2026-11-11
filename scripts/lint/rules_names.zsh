# Rules that read what a line declares or names.

# Lists the names a function must not declare, read from zsh itself.
typeset -ga SPECIAL_NAMES

# Bans names that say nothing about the value.
typeset -gra VAGUE_NAMES=(data obj res tmp val)

# Fills SPECIAL_NAMES from the type zsh gives each of its parameters.
#
# - Reading a parameter's type can load a zsh module, whose globals would
#   otherwise trigger warn_create_global.
collect_special_names() {
  setopt local_options no_warn_create_global

  local parameter_name

  for parameter_name in "${(@k)parameters}"; do
    if [[ ${parameters[${parameter_name}]} == *special* ]]; then
      typeset -ga SPECIAL_NAMES=("${SPECIAL_NAMES[@]}" "${parameter_name}")
    fi
  done

  return 0
}

# Reports whether a word starts a declaration, given the word before it.
is_declaring_keyword() {
  if ((${#} != 2)); then
    print -r -- "is_declaring_keyword needs two words" >&2

    return 2
  fi

  # A word ending in `=` is an assignment for the command, as in `IFS= read`.
  case "${2}" in
    "!" | *= | ";" | do | elif | else) ;;

    if | then | until | while | "{" | "|") ;;
    *)
      return 1
      ;;
  esac

  case "${1}" in
    declare | export | float | for | integer)
      return 0
      ;;
    local | private | "read" | readonly | typeset)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Reports whether a setopt word names a real option, with or without `no`.
is_real_option() {
  if ((${#} != 1)); then
    print -r -- "is_real_option needs a word" >&2

    return 2
  fi

  local normalized="${(L)1//_/}"

  if [[ -n ${options[${normalized}]:-} ]]; then
    return 0
  fi

  if [[ -n ${options[${normalized#no}]:-} ]]; then
    return 0
  fi

  return 1
}

# Collects the names declared on a line of code into DECLARED_NAMES.
#
# - A keyword only counts as the first word of a command, so a test that
#   mentions `typeset` declares nothing.
read_declared_names() {
  if ((${#} != 1)); then
    print -r -- "read_declared_names needs a line" >&2

    return 2
  fi

  local -a words
  local previous_word=";" word
  local -i is_declaring=0

  typeset -ga DECLARED_NAMES=()

  # (z) splits the line the way the shell would.
  words=("${(@z)1}")

  for word in "${words[@]}"; do
    if is_declaring_keyword "${word}" "${previous_word}"; then
      is_declaring=1
    elif [[ ${word} == (in|\;|\&\&|\|\||\||\<*|\>*) ]]; then
      is_declaring=0
    elif [[ ${is_declaring} == 1 && ${word} != -* ]]; then
      typeset -ga DECLARED_NAMES=("${DECLARED_NAMES[@]}" "${word%%=*}")
    fi

    previous_word="${word}"
  done

  return 0
}

# Reports a name that says nothing about its value.
report_vague_name() {
  if ((${#} != 2)); then
    print -r -- "report_vague_name needs a line and a name" >&2

    return 2
  fi

  if ((${VAGUE_NAMES[(Ie)${2}]})); then
    report "${1}" no_vague_names "${2} says nothing about the value"
  fi

  return 0
}

# Rejects zsh's special parameters as variables, such as `local path`.
rule_no_special_names() {
  local declared_name
  local -i index

  for ((index = 1; index <= ${#STATEMENT_TEXTS}; index++)); do
    read_declared_names "${STATEMENT_TEXTS[index]}"

    for declared_name in "${DECLARED_NAMES[@]}"; do
      if ((${SPECIAL_NAMES[(Ie)${declared_name}]})); then
        report "${STATEMENT_LINES[index]}" no_special_names \
          "${declared_name} is special to zsh, so choose another name"
      fi
    done
  done

  return 0
}

collect_special_names

# Rejects names such as data and tmp, which say nothing about the value.
rule_no_vague_names() {
  local assigned_name declared_name statement_text word
  local -i index

  for ((index = 1; index <= ${#STATEMENT_TEXTS}; index++)); do
    statement_text="${STATEMENT_TEXTS[index]}"
    read_declared_names "${statement_text}"

    for declared_name in "${DECLARED_NAMES[@]}"; do
      report_vague_name "${STATEMENT_LINES[index]}" "${declared_name}"
    done

    # Assignments lead a statement, as in `name=1 data=2` or `data+=(a)`.
    for word in ${=statement_text}; do
      if [[ ${word} != [A-Za-z_]*=* ]]; then
        break
      fi

      assigned_name="${word%%=*}"
      report_vague_name "${STATEMENT_LINES[index]}" "${assigned_name%+}"
    done
  done

  return 0
}

# Checks each setopt name, because a bad one doesn't stop the script.
rule_setopt_names_exist() {
  local option_name statement_text
  local -i index

  for ((index = 1; index <= ${#STATEMENT_TEXTS}; index++)); do
    statement_text="${STATEMENT_TEXTS[index]}"
    trim_line "${statement_text}"

    if [[ ${TRIMMED_LINE} != (un|)setopt[[:space:]]* ]]; then
      continue
    fi

    for option_name in ${=TRIMMED_LINE}; do
      if [[ ${option_name} != (setopt|unsetopt|-*) ]]; then
        if ! is_real_option "${option_name}"; then
          report "${STATEMENT_LINES[index]}" setopt_names_exist \
            "${option_name} isn't an option"
        fi
      fi
    done
  done

  return 0
}
