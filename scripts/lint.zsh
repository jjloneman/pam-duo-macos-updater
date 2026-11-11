#!/bin/zsh -f
emulate -R zsh
setopt no_short_loops no_unset pipe_fail typeset_silent \
  warn_create_global warn_nested_var
unset CDPATH
path=(/usr/bin /bin /usr/sbin /sbin)
hash -r

# Checks the repo's zsh and OKF records against the rules in AGENTS.md.
#
# - It prints one `path:line: rule: message` per finding, and exits 1 if any.
#
# - Grep-style checks can't fully parse zsh, so a rule too noisy to trust moves
#   to review rather than being weakened.

zmodload zsh/parameter

# Sets collation for sorted names, and character type for counting columns.
unset LC_ALL
LC_COLLATE=C
LC_CTYPE=en_US.UTF-8

typeset -gr LINT_DIR="${0:A:h}/lint"
typeset -gr REPO_ROOT="${0:A:h:h}"
typeset -g VIEW_DIR

if ! VIEW_DIR="$(mktemp -d "${${TMPDIR:-/tmp}%/}/lint.XXXXXX")"; then
  print -r -- "could not make a temporary folder" >&2
  exit 2
fi

typeset -gr VIEW_DIR

# Prints the rule functions whose names start with a prefix, sorted.
functions_with_prefix() {
  if ((${#} != 1)); then
    print -r -- "functions_with_prefix needs a prefix" >&2

    return 2
  fi

  local function_name

  for function_name in "${(@ok)functions}"; do
    if [[ ${function_name} == "${1}"* ]]; then
      print -r -- "${function_name}"
    fi
  done

  return 0
}

# Reports whether a root holds zsh files, records or a legacy list.
has_anything_to_check() {
  if ((${1:-0} > 0)); then
    return 0
  fi

  local -a other_targets

  other_targets=(docs/(decisions|playbooks|references)(N/))
  other_targets+=(scripts/lint-legacy.txt(N.))

  if ((${#other_targets} > 0)); then
    return 0
  fi

  return 1
}

# Checks one file, with only its syntax if the legacy list exempts it.
lint_file() {
  if ((${#} != 1)); then
    print -r -- "lint_file needs a path" >&2

    return 2
  fi

  local rule_function

  if ! load_views "${1}"; then
    return 2
  fi

  # The exemption is for style only, so security and syntax rules still run.
  #
  # - Comments are checked for width too, as renaming the imported code once
  #   pushed some past 80 columns with nothing to catch it.
  if ((${LEGACY_FILES[(Ie)${1}]})); then
    check_comment_width
    rule_helper_sources_nothing
    rule_zsh_syntax

    return 0
  fi

  for rule_function in "${(@f)$(functions_with_prefix rule_)}"; do
    "${rule_function}"
  done

  return 0
}

# Checks every file under a root, then the repo-wide rules.
lint_root() {
  if ((${#} != 1)); then
    print -r -- "lint_root needs a directory" >&2

    return 2
  fi

  local -a targets
  local rule_function target

  if ! cd -- "${1}"; then
    tool_error "could not enter ${1}"

    return 2
  fi

  read_legacy_list
  targets=("${(@f)$(discover_targets)}")
  targets=("${(@)targets:#}")

  if ! has_anything_to_check "${#targets}"; then
    tool_error "found nothing to check in ${1}"

    return 2
  fi

  for target in "${targets[@]}"; do
    lint_file "${target}"
  done

  for rule_function in "${(@f)$(functions_with_prefix repo_rule_)}"; do
    "${rule_function}"
  done

  return 0
}

# Lists the rule names, one per line.
list_rules() {
  local rule_function

  for rule_function in "${(@f)$(functions_with_prefix rule_)}" \
    "${(@f)$(functions_with_prefix repo_rule_)}"; do
    rule_function="${rule_function#repo_}"
    print -r -- "${rule_function#rule_}"
  done

  return 0
}

# Sources one rule file, and stops unless its last function arrived.
#
# - A `no_unset` stop in a sourced file only ends that file, so checking the
#   status alone would run with some of the rules silently missing.
load_rule_file() {
  if ((${#} != 2)); then
    print -r -- "load_rule_file needs a file and a function" >&2
    exit 2
  fi

  if ! source "${LINT_DIR}/${1}.zsh"; then
    print -r -- "could not load ${1}.zsh" >&2
    exit 2
  fi

  if ((${+functions[${2}]} == 0)); then
    print -r -- "${1}.zsh stopped before defining ${2}" >&2
    exit 2
  fi

  return 0
}

# Removes the temporary views.
remove_views() {
  rm -rf -- "${VIEW_DIR:?}"

  return 0
}

# Prints any errors or findings, and returns lint's exit status for them.
report_totals() {
  if ((TOOL_ERROR_COUNT > 0)); then
    print -r -- "${TOOL_ERROR_COUNT} errors stopped lint checking" >&2

    return 2
  fi

  if ((FINDING_COUNT > 0)); then
    print -r -- "${FINDING_COUNT} findings" >&2

    return 1
  fi

  return 0
}

# Parses the arguments, runs the checks, and returns the result.
main() {
  local lint_directory="${REPO_ROOT}"

  case "${1:-}" in
    "") ;;
    --list-rules)
      list_rules

      return 0
      ;;
    --root)
      if ((${#} != 2)); then
        print -r -- "usage: lint.zsh --root <directory>" >&2

        return 2
      fi

      lint_directory="${2:A}"
      ;;
    *)
      print -r -- "usage: lint.zsh [--list-rules | --root <directory>]" >&2

      return 2
      ;;
  esac

  lint_root "${lint_directory}"
  report_totals

  return "$?"
}

# zsh skips EXIT on a signal unless the signal's own trap exits.
trap remove_views EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

load_rule_file scan trim_line
load_rule_file rules_banned rule_read_uses_r
load_rule_file rules_layout rule_line_width
load_rule_file rules_names rule_setopt_names_exist
load_rule_file rules_tests rule_test_shape
load_rule_file rules_order rule_sorted_source_lines
load_rule_file rules_repo rule_zsh_syntax

main "$@"
exit "$?"
