if [[ -n a &&
  -n b ]]; then
  print -r -- a
fi

if ((1 > 0 && \
  2 > 0)); then
  print -r -- a
fi
