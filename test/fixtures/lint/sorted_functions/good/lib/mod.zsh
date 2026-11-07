# Does it.
alpha() {
  print -r -- a
  return 0
}

# Order: this must be defined after alpha.
Beta() {
  print -r -- a
  return 0
}

# Does it.
main() {
  print -r -- a
  return 0
}
