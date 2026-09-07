test_that("zujson_info reports the build", {
  info <- zujson_info()
  expect_named(info, c("zujson", "yyjson", "max_depth"))
  expect_identical(info$zujson, as.character(utils::packageVersion("zujson")))
  expect_type(info$max_depth, "integer")
})

test_that("the vendored yyjson version is the one recorded in tools/", {
  # tools/ is not installed, so the version is asserted literally here; a
  # vendor bump must update both this line and tools/vendor-yyjson.R.
  expect_identical(zujson_info()$yyjson, "0.12.0")
})
