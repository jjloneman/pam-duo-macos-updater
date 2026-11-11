# Tests a.
check_a() {
  describe "a"
  test_case "runs"

  # Given - a file to run
  make_file

  # When - running it
  run_it

  # Then - it passed
  expect_equal "status" "0" "${status_code}"

  # And - it said so
  expect_contains "output" "ok" "${output_text}"

  # Cleanup
  remove_file
  test_case "runs and checks at once"

  # When/Then - it passes
  expect_equal "status" "0" "$(run_it)"
  return 0
}

# Not a test case, so it needs no phases.
make_file() {
  return 0
}
