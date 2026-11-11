# Prints a greeting, unless asked not to.
greet() {
  if [[ ${1:-} == quiet ]]; then
    return 0
  fi

  case "${1:-}" in
    loud)
      return 0
      ;;
    *) ;;
  esac

  print -r -- hi

  # Done.
  return 0
}
