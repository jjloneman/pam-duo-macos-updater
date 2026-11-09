# Rules that ban a form outright, each a regex over a masked view.

# Rejects Bash-only commands, variables and expansions by name.
rule_bash_only_forms() {
  local command_start='(^|[[:space:];&|(])'

  report_pattern bash_only_forms code \
    "${command_start}(mapfile|readarray|shopt|compgen)([[:space:]]|$)" \
    "this command doesn't exist in zsh"
  report_pattern bash_only_forms code \
    "${command_start}(declare[[:space:]]+-n|read[[:space:]]+-[ap])" \
    "this option means something else in zsh, or doesn't exist"
  report_pattern bash_only_forms expand \
    '\$\{?(BASH_SOURCE|FUNCNAME|PIPESTATUS)|\$\{[A-Za-z_]+(\^\^|,,)|\$\{!' \
    "this is empty or an error in zsh"
  return 0
}

# Moves branches into `if` bodies, which the coverage tracer can see.
rule_every_branch_is_if() {
  if ! LC_ALL=C /usr/bin/awk -f "${LINT_DIR}/strip_tests.awk" \
    "${VIEW_DIR}/code" > "${VIEW_DIR}/branch"; then
    tool_error "could not build the branch view"
    return 2
  fi

  report_pattern every_branch_is_if branch '&&|\|\|' \
    "use an if, as a tracer can't see inside && or ||"
  return 0
}

# Keeps `source` out of the root-owned helper, which must be self-contained.
rule_helper_sources_nothing() {
  if [[ ${CURRENT_FILE} == libexec/* ]]; then
    report_pattern helper_sources_nothing code \
      '(^|[[:space:];&|(])(source|\.)[[:space:]]' \
      "root must never run a file this user can write"
  fi

  return 0
}

# Requires a template, because macOS `mktemp` ignores TMPDIR without one.
rule_mktemp_has_template() {
  report_pattern mktemp_has_template statement \
    '(^|[[:space:];(])mktemp([[:space:]]+-[a-zA-Z]+)*[[:space:]]*(\)|$)' \
    'give mktemp a template, built from ${TMPDIR:-/tmp}'
  return 0
}

# Rejects `$(...)` in a declaration, whose status is always 0.
rule_no_assign_on_declare() {
  local keyword='(local|typeset|declare|float|integer|readonly|export|private)'

  # Stopping at `;` allows `local name; name="$(cmd)"`, and $(( )) is arithmetic
  # rather than a command. The statement view joins continued lines.
  report_pattern no_assign_on_declare statement \
    "(^|[[:space:];])${keyword}[[:space:]][^;]*\\\$\\(([^(]|\$)" \
    "declare first, then assign, or the command's failure is hidden"
  return 0
}

# Rejects backticks.
rule_no_backticks() {
  report_pattern no_backticks code '`' 'use $(...)'
  return 0
}

# Rejects `emulate -L` with no options, which turns off no_unset.
rule_no_bare_emulate_l() {
  report_pattern no_bare_emulate_l code \
    'emulate[[:space:]]+-L([[:space:]]+zsh)?[[:space:]]*($|[;&|])' \
    "this turns off no_unset inside the function"
  return 0
}

# Requires braces on variables, because zsh reads what follows a bare name.
rule_no_bare_variable() {
  report_pattern no_bare_variable expand '\$[A-Za-z_0-9]' 'use ${name}'
  return 0
}

# Rejects `$#`, because the formatter turns "$#" into "$".
rule_no_dollar_hash() {
  report_pattern no_dollar_hash expand '\$#' 'use ${#}'
  return 0
}

# Rejects echo, which rewrites backslashes and swallows `-n`.
rule_no_echo() {
  report_pattern no_echo code '(^|[[:space:];&|(])echo([[:space:]]|$)' \
    'use print -r --'
  return 0
}

# Rejects the `function` keyword.
rule_no_function_keyword() {
  report_pattern no_function_keyword code \
    '(^|[[:space:];])function[[:space:]]' 'use name() {'
  return 0
}

# Rejects `#` after a bracket class, which needs extended_glob, kept off.
#
# - Without it, `[[:space:]]#` matches a literal `#`, so the pattern silently
#   fails. Subscripts such as `${a[1]#x}` are fine, so only classes count.
rule_no_glob_repeat_hash() {
  report_pattern no_glob_repeat_hash code \
    '(:\]|[[:alnum:]]-[[:alnum:]])\]#' \
    "this needs extended_glob; use a helper such as trim_line"
  return 0
}

# Rejects `grep -q` in a pipeline, which pipe_fail turns into a false failure.
rule_no_grep_q_in_pipeline() {
  local gap='[[:space:]]'
  local grep_command='(command[[:space:]]+)?([^[:space:]|]*/)?[ef]?grep'
  local quiet_flag='(-[a-zA-Z]*q|--quiet|--silent)'

  report_pattern no_grep_q_in_pipeline statement \
    "\\|&?${gap}*${grep_command}${gap}+([^|]*${gap})?${quiet_flag}" \
    "grep stops reading early, and pipe_fail reports that as a failure"
  return 0
}

# Rejects `=~`.
rule_no_regex_match() {
  report_pattern no_regex_match code '=~' 'use a zsh pattern with =='
  return 0
}

# Rejects zsh's short forms of `if`, `for` and `while`.
rule_no_short_forms() {
  local gap='[[:space:]]'
  local loop_message="use for name in ...; do"

  report_pattern no_short_forms code \
    "^${gap}*(if|elif|while|until)${gap}.*[^;[:space:]]${gap}*\\{${gap}*\$" \
    "use the long form, with then or do"
  report_pattern no_short_forms code \
    "^${gap}*for${gap}+[A-Za-z_]+${gap}*\\(" "${loop_message}"
  report_pattern no_short_forms code \
    "^${gap}*for${gap}.*;${gap}*[^[:space:]]" "${loop_message}" \
    ";${gap}*do(${gap}|\$)|\\(\\("
  return 0
}

# Rejects `[ ]`.
rule_no_single_bracket() {
  report_pattern no_single_bracket code '(^|[[:space:];&|(])\[[[:space:]]' \
    'use [[ ]] or (( ))'
  return 0
}

# Requires `read -r`, as plain read removes backslashes.
rule_read_uses_r() {
  report_pattern read_uses_r code '(^|[[:space:];&|(])read([[:space:]]|$)' \
    'use read -r' 'read[[:space:]]+(.*[[:space:]])?-[a-zA-Z]*r'
  return 0
}

# Requires `cd` to be checked, as a failed one carries on in the wrong folder.
#
# - `cd -- ""` even succeeds and stays put, so a script needs to test the
#   result. Only a statement that starts with `cd` is unchecked.
rule_unchecked_cd() {
  report_pattern unchecked_cd statement \
    '(^|;|[[:space:]](then|do|else))[[:space:]]*cd([[:space:]]|$)' \
    'use if ! cd -- "${path}"; then'
  return 0
}
