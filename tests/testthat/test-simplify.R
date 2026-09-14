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

test_that("simplify = \"none\" wins over data_frame", {
  # "none" is the mode that promises every array arrives as a list, and a data
  # frame is not one, so the two options are not combined
  js <- '[{"a":1},{"a":2}]'
  expect_false(is.data.frame(json_parse(js, simplify = "none", data_frame = TRUE)))
  expect_identical(json_parse(js, simplify = "none", data_frame = TRUE),
                   json_parse(js, simplify = "none"))
  expect_s3_class(json_parse(js, simplify = "preserve", data_frame = TRUE),
                  "data.frame")
})

test_that("a missing key is NULL in a list column, as an explicit null is", {
  # the atomic path collapses absent and null to NA; a list column collapses
  # them to NULL for the same reason -- one cell cannot say which it was
  d <- json_parse('[{"a":[1,2]},{"b":3}]', data_frame = TRUE)
  expect_type(d$a, "list")
  expect_null(d$a[[2]])
  expect_identical(d$a[[2]], json_parse('[{"a":[1,2]},{"a":null}]',
                                        data_frame = TRUE)$a[[2]])
})

test_that("one object with the same key twice is rejected, not half-kept", {
  # plain parsing keeps both, so the frame silently keeping one would be data
  # loss introduced by an option that is meant to change shape, not content
  expect_error(json_parse('[{"a":1,"a":2}]', data_frame = TRUE),
               class = "zujson_parse_error")
  expect_length(json_parse('[{"a":1,"a":2}]')[[1]], 2L)

  # the same key in *different* records is the ordinary case
  expect_identical(json_parse('[{"a":1},{"a":2}]', data_frame = TRUE)$a, 1:2)
  # and a duplicate outside the frame is untouched
  expect_length(json_parse('{"rows":[{"a":1}],"x":1,"x":2}',
                           data_frame = TRUE), 3L)
})

test_that("a frame larger than the cell budget is refused", {
  # records that share no keys ask for one column per record, so a small body
  # asks for a huge frame: the limit is on rows x columns, not on input size.
  # The budget is lowered rather than the input raised, so the test costs
  # nothing -- the refusal happens as the offending column appears.
  ragged <- function(n) {
    paste0("[", paste0(sprintf('{"k%d":%d}', seq_len(n), seq_len(n)),
                       collapse = ","), "]")
  }
  withr::local_options(zujson.max_df_cells = 100)

  expect_error(json_parse(ragged(11L), data_frame = TRUE),
               class = "zujson_limit_error")
  # exactly at the budget is still built, and is still the right shape
  expect_identical(dim(json_parse(ragged(10L), data_frame = TRUE)),
                   c(10L, 10L))
  # the limit is on the frame, not on the body: the same records parse as a
  # list, and a wide *shared* key set is only as big as it looks
  expect_length(json_parse(ragged(11L)), 11L)
  expect_identical(dim(json_parse('[{"a":1,"b":2},{"a":3,"b":4}]',
                                  data_frame = TRUE)), c(2L, 2L))
})

test_that("the cell budget is settable, and a bad setting is an argument error", {
  expect_type(zujson_info()$max_df_cells, "double")

  withr::local_options(zujson.max_df_cells = 4)
  # zujson_info() reports the limit in force, which is what the caller asking
  # "what will happen" wants, and what makes the test above honest
  expect_identical(zujson_info()$max_df_cells, 4)
  expect_error(json_parse('[{"a":1,"b":2},{"c":3}]', data_frame = TRUE),
               class = "zujson_limit_error")

  # Inf is not how the limit is switched off: a number bigger than any frame
  # is, and it says the same thing without asking C to convert something no
  # integer type has a value for. So Inf is refused with everything else
  # malformed.
  for (bad in list("x", 0, -1, NA_real_, Inf, c(1, 2), TRUE)) {
    withr::local_options(zujson.max_df_cells = bad)
    expect_error(json_parse('[{"a":1}]', data_frame = TRUE),
                 class = "zujson_arg_error")
  }
})

test_that("a budget larger than any frame switches the limit off", {
  ragged <- function(n) {
    paste0("[", paste0(sprintf('{"k%d":%d}', seq_len(n), seq_len(n)),
                       collapse = ","), "]")
  }
  default <- zujson_info()$max_df_cells

  withr::local_options(zujson.max_df_cells = 100)
  expect_error(json_parse(ragged(11L), data_frame = TRUE),
               class = "zujson_limit_error")

  # The documented way to switch the check off, so it is a value the clamp in
  # zu_df_cells() has to handle rather than one R rejects. Asserting on the
  # frame a budget of 100 just refused is what pins the *purpose*: on arm64 an
  # unclamped cast saturates, so a weaker assertion passes for the wrong
  # reason, and clamping to any small number satisfies "not negative" while
  # still imposing a limit nobody asked for.
  withr::local_options(zujson.max_df_cells = 1e300)
  expect_identical(dim(json_parse(ragged(11L), data_frame = TRUE)),
                   c(11L, 11L))

  # Clamped, and reported clamped: what zujson_info() names is what the parser
  # enforces, which is what makes it worth pre-flighting a body against. The
  # assertion is on the ceiling itself rather than on is.finite(), because
  # 1e300 is finite and is over the default -- weaker assertions pass with the
  # clamp in zu_df_cells() deleted, since the one in zu_df_arg() still keeps
  # the frame building.
  cap <- zujson_info()$max_df_cells
  expect_identical(cap, zu_build_info()$max_xlen)
  expect_gte(cap, default)

  # the ceiling is idempotent, and is a ceiling only -- anything under it is
  # reported exactly as it was asked for
  withr::local_options(zujson.max_df_cells = cap)
  expect_identical(zujson_info()$max_df_cells, cap)
  withr::local_options(zujson.max_df_cells = 12345)
  expect_identical(zujson_info()$max_df_cells, 12345)
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
