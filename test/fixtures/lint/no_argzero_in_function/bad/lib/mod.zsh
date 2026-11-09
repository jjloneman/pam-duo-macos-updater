# Does it.
f() {
  print -r -- "${0:A:h}"
  return 0
}
