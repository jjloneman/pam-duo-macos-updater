if [[ "$(false && print -r -- a)" == a ]]; then
  print -r -- b
fi
