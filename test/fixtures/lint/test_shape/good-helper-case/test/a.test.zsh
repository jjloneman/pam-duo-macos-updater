# Tests a.
test_a() {
  describe "a"
  run_case

  return 0
}

# Runs one case, under the caller's describe.
run_case() {
  test_case "x"

  # When/Then - it passes
  expect_equal "s" "0" "0"

  return 0
}
