#!/bin/zsh -f
# Runs the script by its shebang, as a test of the tool might.
out="$(env -i "${0:A:h:h}/bin/demo" bob)"
[[ ${out} == "hi bob" ]] || exit 1
