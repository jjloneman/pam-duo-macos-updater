# Blanks `[[ ]]` and `(( ))` tests, which may use && and || inside them.
#
# - It reads the code view, so quoted text is already gone.
#
# - `[[ ]]` can span lines. `(( ))` ends with its line unless continued, as a
#   subshell inside a subshell also opens with "((" and never closes as "))".
#
# - A command substitution inside a test stays visible, as its branches are
#   real ones.
#
# - Awk has no local keyword, so extra parameters are a function's locals. The
#   extra spaces before them are awk's convention for showing where they start.

# Reports whether a test can open at this position.
#
# - A `[[` mid-word is a bracket class in a pattern, such as `[[:space:]-]`.
function can_open_test(line, position, pair,    before) {
  before = position == 1 ? "" : substr(line, position - 1, 1)
  if (pair == "((") {
    return before == "" || before ~ /[[:space:];&|($!]/
  }

  return before == "" || before ~ /[[:space:];&|(!]/
}

# Copies a command substitution inside a test, tracking its parentheses.
function scan_substitution(character) {
  if (character == "(") {
    open_parens++
  } else if (character == ")") {
    open_parens--
  }

  return character
}

# Returns the line with each test blanked, tracking what's still open.
function strip_line(line,    output, position, pair) {
  output = ""
  position = 1
  while (position <= length(line)) {
    pair = substr(line, position, 2)
    if (open_parens > 0) {
      output = output scan_substitution(substr(line, position, 1))
      position++
    } else if (open_test != "" && pair == "$(" &&
        substr(line, position, 3) != "$((") {
      open_parens = 1
      output = output pair
      position += 2
    } else if (open_test == "" && (pair == "[[" || pair == "((") &&
        can_open_test(line, position, pair)) {
      open_test = pair
      position += 2
    } else if (open_test == "[[" && pair == "]]") {
      open_test = ""
      position += 2
    } else if (open_test == "((" && pair == "))") {
      open_test = ""
      position += 2
    } else {
      output = output (open_test == "" ? substr(line, position, 1) : " ")
      position++
    }
  }

  return output
}

BEGIN {
  open_parens = 0
  open_test = ""
}

{
  print strip_line($0)
  if (open_test == "((" && $0 !~ /\\$/) {
    open_test = ""
  }
}
