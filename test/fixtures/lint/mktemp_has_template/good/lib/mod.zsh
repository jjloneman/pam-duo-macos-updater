if ! folder="$(mktemp -d "${TMPDIR}/x.XXXXXX")"; then
  return 1
fi
