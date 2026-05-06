test_that("classify_migration_risk handles NULL", {
  res <- classify_migration_risk(NULL, NULL)
  expect_equal(res$risk, "unknown")
})