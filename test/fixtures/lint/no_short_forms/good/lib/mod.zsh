if [[ -n a ]]; then
  print -r -- a
fi

for x in 1 2; do
  print -r -- "${x}"
done
