test_that("rig functions work", {
  expect_type(rig_available(), "logical")
  if (rig_available()) {
    expect_s3_class(rig_list(), "data.frame")
  }
})