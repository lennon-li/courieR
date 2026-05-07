test_that("rate_shipment handles NULL arg", {
  res <- rate_shipment(NULL, NULL)
  expect_equal(res$risk, "unknown")
  expect_equal(res$reason, "missing results")
  expect_equal(res$new_errors, 0L)
  expect_equal(res$new_warnings, 0L)
  expect_equal(res$new_notes, 0L)
})

test_that("rate_shipment returns none when no new issues", {
  base <- data.table::data.table(
    severity = c("NOTE", "WARNING"),
    message  = c("some note", "some warning"),
    file     = c("foo.R", "bar.R"),
    line     = c("10", "20"),
    raw_block = c("NOTE\nsome note", "WARNING\nsome warning")
  )
  post <- data.table::copy(base)

  res <- rate_shipment(base, post)
  expect_equal(res$risk, "none")
  expect_equal(res$new_errors, 0L)
  expect_equal(res$new_warnings, 0L)
  expect_equal(res$new_notes, 0L)
  expect_equal(res$reason, "no new issues")
})

test_that("rate_shipment returns low for new notes only", {
  base <- data.table::data.table(
    severity  = character(),
    message   = character(),
    file      = character(),
    line      = character(),
    raw_block = character()
  )
  post <- data.table::data.table(
    severity  = c("NOTE", "NOTE"),
    message   = c("note A", "note B"),
    file      = c("a.R", "b.R"),
    line      = c("1", "2"),
    raw_block = c("NOTE\nnote A", "NOTE\nnote B")
  )

  res <- rate_shipment(base, post)
  expect_equal(res$risk, "low")
  expect_equal(res$new_errors, 0L)
  expect_equal(res$new_warnings, 0L)
  expect_equal(res$new_notes, 2L)
})

test_that("rate_shipment returns medium for new warnings only", {
  base <- data.table::data.table(
    severity  = character(),
    message   = character(),
    file      = character(),
    line      = character(),
    raw_block = character()
  )
  post <- data.table::data.table(
    severity  = c("WARNING", "NOTE"),
    message   = c("warn A", "note A"),
    file      = c("a.R", "b.R"),
    line      = c("1", "2"),
    raw_block = c("WARNING\nwarn A", "NOTE\nnote A")
  )

  res <- rate_shipment(base, post)
  expect_equal(res$risk, "medium")
  expect_equal(res$new_errors, 0L)
  expect_equal(res$new_warnings, 1L)
  expect_equal(res$new_notes, 1L)
})

test_that("rate_shipment returns high when new errors present", {
  base <- data.table::data.table(
    severity  = character(),
    message   = character(),
    file      = character(),
    line      = character(),
    raw_block = character()
  )
  post <- data.table::data.table(
    severity  = c("ERROR", "WARNING", "NOTE"),
    message   = c("err A", "warn A", "note A"),
    file      = c("a.R", "b.R", "c.R"),
    line      = c("1", "2", "3"),
    raw_block = c("ERROR\nerr A", "WARNING\nwarn A", "NOTE\nnote A")
  )

  res <- rate_shipment(base, post)
  expect_equal(res$risk, "high")
  expect_equal(res$new_errors, 1L)
  expect_equal(res$new_warnings, 1L)
  expect_equal(res$new_notes, 1L)
})

test_that("rate_shipment only counts truly new items", {
  base <- data.table::data.table(
    severity  = c("ERROR", "WARNING"),
    message   = c("existing error", "existing warning"),
    file      = c("e.R", "w.R"),
    line      = c("1", "2"),
    raw_block = c("ERROR\nexisting error", "WARNING\nexisting warning")
  )
  post <- data.table::rbindlist(list(
    base,
    data.table::data.table(
      severity  = c("ERROR", "NOTE"),
      message   = c("new error", "new note"),
      file      = c("n.R", "nn.R"),
      line      = c("3", "4"),
      raw_block = c("ERROR\nnew error", "NOTE\nnew note")
    )
  ))

  res <- rate_shipment(base, post)
  expect_equal(res$risk, "high")
  expect_equal(res$new_errors, 1L)
  expect_equal(res$new_warnings, 0L)
  expect_equal(res$new_notes, 1L)
})
