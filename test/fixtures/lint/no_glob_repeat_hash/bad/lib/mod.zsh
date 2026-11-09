x="${y##[[:space:]]#}"
if [[ ${x} == [[:space:]]#a ]]; then
  print -r -- a
fi
