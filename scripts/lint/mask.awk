# Blanks what a lint rule must not read, keeping every line and column.
#
# - view=code keeps only code, so quoted text can't look like a command.
#
# - view=expand also keeps double-quoted text and unquoted heredocs, where a
#   variable can still expand.
#
# - view=comment keeps only comments, so a rule can tell one from a heredoc.
#
# - Grep-style checks can't fully parse zsh, so this tracks quotes, heredocs,
#   arithmetic, command substitutions and comments, and nothing else.
#
# - Awk has no local keyword, so extra parameters are a function's locals. The
#   extra spaces before them are awk's convention for showing where they start.

# Returns spaces as wide as the text.
function blank_text(text,    spaces, position) {
  spaces = ""
  for (position = 1; position <= length(text); position++) {
    spaces = spaces " "
  }

  return spaces
}

# Copies a piece of the line to the output, and moves past it.
function copy_text(text) {
  out = out text
  cursor += length(text)
  return
}

# Leaves the innermost quote or command substitution.
function pop_state() {
  if (depth > 0) {
    depth--
  }

  return
}

# Prints a heredoc line in the views that keep it, and spots its end.
function print_heredoc_line(    candidate) {
  candidate = $0
  if (active_dash) {
    sub(/^\t+/, "", candidate)
  }

  if (candidate == active_end) {
    active_end = ""
    print ""
    return
  }

  if (view == "expand" && !active_quoted) {
    print $0
    return
  }

  print ""
  return
}

# Enters a quote or command substitution.
function push_state(state) {
  depth++
  stack[depth] = state
  parens[depth] = 0
  return
}

# Records a heredoc opening here, to start on the next line.
#
# - A quoted or backslashed delimiter turns off expansion in the body.
function read_heredoc_opening(rest,    opening) {
  opening = substr(rest, 1, RLENGTH)
  pending_dash = opening ~ /^<<-/
  sub(/^<<-?[ \t]*/, "", opening)
  pending_quoted = opening ~ /^['"\\]/
  gsub(/['"\\]/, "", opening)
  pending_end = opening
  return
}

# Handles one character of code.
function scan_code(character,    is_word_start, next_character, rest) {
  rest = substr($0, cursor)
  next_character = substr($0, cursor + 1, 1)
  is_word_start = cursor == 1 || previous ~ /[[:space:];&|(]/
  if (character == "#" && is_word_start && arithmetic == 0) {
    comment = rest
    out = out blank_text(rest)
    cursor = line_length + 1
  } else if (rest ~ /^<<</) {
    copy_text("<<<")
  } else if (rest ~ /^\$\(\(/) {
    arithmetic++
    copy_text("$((")
  } else if (rest ~ /^\(\(/) {
    arithmetic++
    copy_text("((")
  } else if (arithmetic > 0 && rest ~ /^\)\)/) {
    arithmetic--
    copy_text("))")
  } else if (character == "\\" && next_character != "" && rest !~ /^\\[A-Za-z_]/) {
    out = out "  "
    cursor += 2
  } else if (character == "$" && next_character == "'") {
    push_state("ansi")
    copy_text("$'")
  } else if (character == "$" && next_character == "(") {
    push_state("subst")
    copy_text("$(")
  } else if (character == "'") {
    push_state("single")
    copy_text(character)
  } else if (character == "\"") {
    push_state("double")
    copy_text(character)
  } else {
    scan_plain_code(character, rest)
  }

  return
}

# Handles a double-quoted character.
#
# - Inside "$((...))", the markers stay so later tools see it close, and the
#   text is treated as quoted, so it can't open a heredoc.
function scan_double(character) {
  if (character == "\\") {
    out = out "  "
    cursor += 2
  } else if (character == "\"") {
    pop_state()
    copy_text(character)
  } else if (substr($0, cursor, 3) == "$((") {
    quoted_arithmetic++
    copy_text("$((")
  } else if (quoted_arithmetic > 0 && substr($0, cursor, 2) == "))") {
    quoted_arithmetic--
    copy_text("))")
  } else if (substr($0, cursor, 2) == "$(") {
    push_state("subst")
    copy_text("$(")
  } else {
    out = out (view == "expand" ? character : " ")
    cursor++
  }

  return
}

# Handles code that opens nothing, apart from a heredoc for the next line.
function scan_plain_code(character, rest,    delimiter) {
  delimiter = "('[^']+'|\"[^\"]+\"|\\\\?[^[:space:];&|<>()'\"]+)"
  if (arithmetic == 0 && character == "<" &&
      match(rest, "^<<-?[ \t]*" delimiter)) {
    read_heredoc_opening(rest)
  }

  if (stack[depth] == "subst" && character == "(") {
    parens[depth]++
  }

  if (stack[depth] == "subst" && character == ")") {
    if (parens[depth] == 0) {
      pop_state()
    } else {
      parens[depth]--
    }
  }

  copy_text(character)
  return
}

# Handles a character inside single quotes or $'...'.
function scan_single(character) {
  if (character == "\\" && stack[depth] == "ansi") {
    out = out "  "
    cursor += 2
  } else if (character == "'") {
    pop_state()
    copy_text(character)
  } else {
    out = out " "
    cursor++
  }

  return
}

BEGIN {
  active_end = ""
  arithmetic = 0
  depth = 0
  parens[0] = 0
  pending_end = ""
  quoted_arithmetic = 0
  stack[0] = "code"
}

{
  if (active_end != "") {
    print_heredoc_line()
    next
  }

  line_length = length($0)
  cursor = 1
  out = ""
  comment = ""
  previous = ""
  while (cursor <= line_length) {
    character = substr($0, cursor, 1)
    if (stack[depth] == "double") {
      scan_double(character)
    } else if (stack[depth] == "single" || stack[depth] == "ansi") {
      scan_single(character)
    } else {
      scan_code(character)
    }

    previous = character
  }

  # A subshell inside a subshell also opens with "((", and never closes as "))",
  # so arithmetic only carries over a line when it's explicitly continued.
  if ($0 !~ /\\$/) {
    arithmetic = 0
    quoted_arithmetic = 0
  }

  print (view == "comment" ? comment : out)
  if (pending_end != "") {
    active_end = pending_end
    active_quoted = pending_quoted
    active_dash = pending_dash
    pending_end = ""
  }
}
