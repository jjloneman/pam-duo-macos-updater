# Tests a.
test_first() {
  describe "a"
  test_case "runs"

  # When/Then - it passes
  expect_equal "status" "0" "$(run_it)"

  return 0
}

# Tests a again, but forgets to say what it's about.
test_second() {
  test_case "runs again"

  # When/Then - it passes
  expect_equal "status" "0" "$(run_it)"

  return 0
}
