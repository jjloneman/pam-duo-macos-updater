# Tests nothing in particular.
check_a() {
  test_case "runs"

  # When - running it
  run_it

  # Then - it passed
  expect_equal "status" "0" "${status_code}"
  return 0
}
