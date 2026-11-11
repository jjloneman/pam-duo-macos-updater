# Tests a.
#
# When this file runs, each test makes its own folder.
test_first() {
  describe "a"
  test_shared "runs once"
  test_case "runs in a group"

  # When - running it twice in a group
  {
    run_it
    run_it
  } > /dev/null

  # Then - it passed
  expect_equal "status" "0" "${status_code}"

  return 0
}

# Tests one shared scenario, under its caller's describe.
test_shared() {
  if ((${#} != 1)); then
    return 2
  fi

  test_case "${1}"

  # When/Then - it passes
  expect_equal "status" "0" "$(run_it)"

  return 0
}

# Setup steps shared by the tests above.
run_it() {
  return 0
}
