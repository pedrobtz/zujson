test_that("a fully named vector or list becomes an object", {
  expect_json(list(a = 1L, b = "x"), '{"a":1,"b":"x"}')
  expect_json(c(a = 1L, b = 2L), '{"a":1,"b":2}')
  expect_json(c(a = TRUE), '{"a":true}')
})

test_that("an unnamed vector or list becomes an array", {
  expect_json(list(1L, "x"), '[1,"x"]')
  expect_json(1:3, "[1,2,3]")
  expect_json(c(TRUE, FALSE), "[true,false]")
})

test_that("partial names are dropped rather than written as empty keys", {
  expect_json(c(a = 1L, 2L), "[1,2]")
  expect_json(list(a = 1L, 2L), "[1,2]")
  expect_json(stats::setNames(1:2, c("a", NA)), "[1,2]")
  expect_json(stats::setNames(1:2, c("a", "")), "[1,2]")
})

test_that("empty containers write as [] unless the list carries names", {
  expect_json(list(), "[]")
  expect_json(integer(), "[]")
  expect_json(character(), "[]")
  expect_json(structure(list(), names = character()), "{}")
})

test_that("NULL is null wherever it appears", {
  expect_json(NULL, "null")
  expect_json(list(a = NULL), '{"a":null}')
  expect_json(list(NULL, 1L), "[null,1]")
})

test_that("every kind of missing and non-finite value becomes null", {
  expect_json(list(a = NA, b = NA_integer_, c = NA_real_, d = NA_character_),
              '{"a":null,"b":null,"c":null,"d":null}')
  expect_json(list(a = NaN, b = Inf, c = -Inf), '{"a":null,"b":null,"c":null}')
})

test_that("auto_unbox unboxes length-1 atomic vectors only", {
  expect_json(list(a = "x"), '{"a":"x"}')
  expect_json(list(a = "x"), '{"a":["x"]}', auto_unbox = FALSE)
  expect_json("x", '"x"')
  expect_json(1L, "1")
  # a length-1 list is still a container, so it never unboxes
  expect_json(list(list(1L)), "[[1]]")
  expect_json(list(a = list(1L)), '{"a":[1]}')
})

test_that("I() keeps a length-1 vector an array", {
  expect_json(list(a = I("x")), '{"a":["x"]}')
  expect_json(list(a = I(1L)), '{"a":[1]}')
  # and is a no-op when auto_unbox is already off
  expect_json(list(a = I("x")), '{"a":["x"]}', auto_unbox = FALSE)
})

test_that("whole doubles are written without a decimal point", {
  # R has no integer literal, so `1` is a double; `1.0` would be rejected by a
  # schema expecting an integer.
  expect_json(1, "1")
  expect_json(c(a = 1, b = 2), '{"a":1,"b":2}')
  expect_json(2.5, "2.5")
  expect_json(-0.0, "0")
})

test_that("doubles round-trip through their shortest representation", {
  expect_json(0.1, "0.1")
  expect_json(1 / 3, "0.3333333333333333")
  expect_identical(json_parse(json_write(pi)), pi)
})

test_that("strings are escaped and written as UTF-8", {
  expect_json("a\nb", '"a\\nb"')
  expect_json('a"b', '"a\\"b"')
  expect_json("a\\b", '"a\\\\b"')
  snowman <- "☃"
  expect_identical(json_write(snowman), paste0('"', snowman, '"'))
  expect_identical(json_write_raw(snowman),
                   as.raw(c(0x22, 0xe2, 0x98, 0x83, 0x22)))
})

test_that("a latin1 string is converted rather than emitted as-is", {
  x <- "caf\ue9"
  Encoding(x) <- "UTF-8"
  latin1 <- iconv(x, "UTF-8", "latin1")
  skip_if(is.na(latin1), "no latin1 conversion available")
  expect_identical(json_write_raw(latin1), json_write_raw(x))
})

test_that("factors are written as their levels", {
  expect_json(factor(c("lo", "hi")), '["lo","hi"]')
  expect_json(factor("lo", levels = c("lo", "hi")), '"lo"')
  expect_json(factor(c("a", NA)), '["a",null]')
})

test_that("Date and POSIXct are written as ISO 8601 strings", {
  expect_json(as.Date("2026-09-07"), '"2026-09-07"')
  expect_json(as.Date("1969-12-31"), '"1969-12-31"')
  expect_json(as.Date("2024-02-29"), '"2024-02-29"')
  expect_json(as.Date(NA), "null")
  expect_json(as.POSIXct("2026-09-07 13:45:07", tz = "UTC"),
              '"2026-09-07T13:45:07Z"')
  expect_json(as.POSIXct(0, origin = "1970-01-01", tz = "UTC"),
              '"1970-01-01T00:00:00Z"')
})

test_that("POSIXct is written in UTC whatever its tzone says", {
  t <- as.POSIXct("2026-09-07 13:45:07", tz = "UTC")
  other <- t
  attr(other, "tzone") <- "America/New_York"
  # the same instant, so the same JSON
  expect_identical(json_write(other), json_write(t))
})

test_that("data frames are written one object per row", {
  df <- data.frame(id = 1:2, nm = c("a", "b"), stringsAsFactors = FALSE)
  expect_json(df, '[{"id":1,"nm":"a"},{"id":2,"nm":"b"}]')
  expect_json(df[0, ], "[]")
  expect_json(data.frame(a = factor("x")), '[{"a":"x"}]')
  expect_json(data.frame(a = NA_integer_), '[{"a":null}]')
  # dropping the class gives the column-oriented form instead
  expect_json(as.list(df), '{"id":[1,2],"nm":["a","b"]}')
})

test_that("a data frame with a list column keeps the nesting", {
  df <- data.frame(id = 1:2)
  df$tags <- list(c("a", "b"), character())
  expect_json(df, '[{"id":1,"tags":["a","b"]},{"id":2,"tags":[]}]')
})

test_that("nested data frame columns are refused rather than mangled", {
  df <- data.frame(id = 1:2)
  df$inner <- data.frame(x = 1:2)
  expect_error(json_write(df), class = "zujson_unsupported_type")
})

test_that("pretty printing indents with two spaces", {
  expect_json(list(a = 1L, b = list(c = 2L)), pretty = TRUE,
              expected = "{\n  \"a\": 1,\n  \"b\": {\n    \"c\": 2\n  }\n}")
})

test_that("json_write_raw returns the same bytes as json_write", {
  x <- list(a = 1L, b = "x")
  expect_identical(json_write_raw(x), charToRaw(json_write(x)))
  expect_identical(json_write_raw(x, pretty = TRUE),
                   charToRaw(json_write(x, pretty = TRUE)))
  expect_type(json_write_raw(x), "raw")
})

test_that("types with no JSON form are refused rather than guessed at", {
  expect_error(json_write(as.raw(1)), class = "zujson_unsupported_type")
  expect_error(json_write(1+2i), class = "zujson_unsupported_type")
  expect_error(json_write(sum), class = "zujson_unsupported_type")
  expect_error(json_write(globalenv()), class = "zujson_unsupported_type")
  expect_error(json_write(list(a = as.raw(1))), class = "zujson_unsupported_type")
})

test_that("an unrecognised class is written as its underlying type", {
  x <- structure(1:3, class = "totally_unknown")
  expect_json(x, "[1,2,3]")
})

test_that("nesting past the depth limit is rejected rather than crashing", {
  limit <- zujson_info()$max_depth
  expect_no_error(json_write(nested_list(limit)))
  expect_error(json_write(nested_list(limit + 1L)), class = "zujson_depth_error")
})

test_that("bad arguments are rejected before reaching C", {
  expect_error(json_write(1L, pretty = NA), class = "zujson_arg_error")
  expect_error(json_write(1L, auto_unbox = "yes"), class = "zujson_arg_error")
  expect_error(json_write_raw(1L, pretty = c(TRUE, TRUE)),
               class = "zujson_arg_error")
})
