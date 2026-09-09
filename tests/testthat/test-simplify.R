# The two simplification modes, and data frame reconstruction.
#
# `preserve` is v1's behaviour and is covered in test-parse.R; what is pinned
# here is the boundary between the modes, which is narrower than it looks:
# every case where they agree is as much a part of the contract as the one
# case where they differ.

test_that("the modes agree everywhere except strings mixed with numbers", {
  agree <- list(
    "[1,2,3]"      = 1:3,
    "[1,2.5]"      = c(1, 2.5),
    "[true,false]" = c(TRUE, FALSE),
    '["a","b"]'    = c("a", "b"),
    "[]"           = logical(0),
    "[null,null]"  = c(NA, NA),
    "[1,null,3]"   = c(1L, NA, 3L),
    "[true,1]"     = c(1L, 1L)
  )
  for (js in names(agree)) {
    expect_identical(json_parse(js), agree[[js]], info = js)
    expect_identical(json_parse(js, simplify = "coerce"), agree[[js]], info = js)
  }
})

test_that("TRUE and FALSE stay exact synonyms for the named modes", {
  js <- '[1,"a",true]'
  expect_identical(json_parse(js, simplify = TRUE),
                   json_parse(js, simplify = "preserve"))
  expect_identical(json_parse(js, simplify = FALSE),
                   json_parse(js, simplify = "none"))
})

test_that("coerce promotes to character the way R does", {
  # The strings must be R's own, not a C format of the number: as.character()
  # gives 15 significant digits, and getting this by hand would drift.
  expect_identical(json_parse('[1,"a"]', simplify = "coerce"), c("1", "a"))
  expect_identical(json_parse('[true,"x"]', simplify = "coerce"), c("TRUE", "x"))
  expect_identical(json_parse('[1.5,"a"]', simplify = "coerce"), c("1.5", "a"))
  expect_identical(json_parse('[0.3333333333333333,"a"]', simplify = "coerce"),
                   c(as.character(1 / 3), "a"))
  expect_identical(json_parse('[1e30,"a"]', simplify = "coerce"),
                   c(as.character(1e30), "a"))

  # null becomes NA, never the string "NA" -- which is what coercing a list
  # element would have produced.
  expect_identical(json_parse('[1,null,"a"]', simplify = "coerce"),
                   c("1", NA, "a"))
})

test_that("a nested container is never coerced away", {
  expect_type(json_parse('[1,{}]', simplify = "coerce"), "list")
  expect_type(json_parse('[1,[2]]', simplify = "coerce"), "list")
  expect_type(json_parse('["a",{}]', simplify = "coerce"), "list")
})

test_that("simplify rejects anything else", {
  for (bad in list("nope", NA, NULL, 1L, c(TRUE, TRUE), character(0))) {
    expect_error(json_parse("[]", simplify = bad), class = "zujson_arg_error")
  }
})

# ---- data frames -----------------------------------------------------------

test_that("an array of objects becomes a data frame, opt-in only", {
  js <- '[{"id":1,"nm":"a"},{"id":2,"nm":"b"}]'

  expect_false(is.data.frame(json_parse(js)))          # off by default

  d <- json_parse(js, data_frame = TRUE)
  expect_s3_class(d, "data.frame")
  expect_identical(nrow(d), 2L)
  expect_identical(names(d), c("id", "nm"))
  expect_identical(d$id, 1:2)
  expect_identical(d$nm, c("a", "b"))
  expect_identical(attr(d, "row.names"), 1:2)
})

test_that("columns are the union of the keys, in first-seen order", {
  d <- json_parse('[{"a":1},{"b":2},{"a":3,"c":4}]', data_frame = TRUE)
  expect_identical(names(d), c("a", "b", "c"))
  expect_identical(d$a, c(1L, NA, 3L))
  expect_identical(d$b, c(NA, 2L, NA))
  expect_identical(d$c, c(NA, NA, 4L))
})

test_that("a missing key and an explicit null both read as NA", {
  d <- json_parse('[{"a":null},{"b":1}]', data_frame = TRUE)
  expect_identical(d$a, c(NA, NA))
})

test_that("columns simplify with the active mode", {
  js <- '[{"v":1},{"v":"x"}]'
  expect_type(json_parse(js, data_frame = TRUE)$v, "list")
  expect_identical(json_parse(js, data_frame = TRUE, simplify = "coerce")$v,
                   c("1", "x"))
})

test_that("a column of containers stays a list column", {
  d <- json_parse('[{"v":[1,2]},{"v":[3]}]', data_frame = TRUE)
  expect_type(d$v, "list")
  expect_identical(d$v[[1]], 1:2)
})

test_that("anything that is not a non-empty array of objects is left alone", {
  expect_false(is.data.frame(json_parse('[{"a":1},2]', data_frame = TRUE)))
  expect_identical(json_parse("[]", data_frame = TRUE), logical(0))
  expect_false(is.data.frame(json_parse('{"a":1}', data_frame = TRUE)))
  expect_false(is.data.frame(json_parse("[[1,2]]", data_frame = TRUE)))
})

test_that("data frames nest wherever an array of objects appears", {
  x <- json_parse('{"rows":[{"a":1},{"a":2}]}', data_frame = TRUE)
  expect_s3_class(x$rows, "data.frame")
  expect_identical(x$rows$a, 1:2)
})

test_that("all input paths take both arguments", {
  js <- '[{"a":1},{"a":"x"}]'
  want <- json_parse(js, data_frame = TRUE, simplify = "coerce")

  expect_identical(
    json_parse_raw(charToRaw(js), data_frame = TRUE, simplify = "coerce"),
    want
  )
  path <- withr::local_tempfile(fileext = ".json")
  writeLines(js, path)
  expect_identical(
    json_parse_file(path, data_frame = TRUE, simplify = "coerce"),
    want
  )
})

test_that("data_frame rejects anything but TRUE or FALSE", {
  for (bad in list("yes", NA, NULL, 1L)) {
    expect_error(json_parse("[]", data_frame = bad), class = "zujson_arg_error")
  }
})

test_that("empty objects give a frame with rows and no columns", {
  d <- json_parse("[{},{}]", data_frame = TRUE)
  expect_s3_class(d, "data.frame")
  expect_identical(dim(d), c(2L, 0L))
})
