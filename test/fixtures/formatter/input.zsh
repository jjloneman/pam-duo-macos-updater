print -r -- "${#}"
print -r -- "a ${#} b"
print -r -- "count ${#} and ${#}"
x="${#}"
if (( ${#} == 3 )); then
    print -r -- "$?" "$@" "$$"
fi
