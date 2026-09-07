test_that("structures survive a write/parse round trip unchanged", {
  expect_roundtrip(list(a = 1L, b = "x", c = TRUE))
  expect_roundtrip(list(a = 1:3, b = c("x", "y")))
  expect_roundtrip(list(a = list(b = list(c = 1L))))
  expect_roundtrip(list(1L, "x", TRUE), auto_unbox = FALSE)
  expect_roundtrip(NULL)
  expect_roundtrip(structure(list(), names = character()))
  # [] simplifies to logical(0), so an empty list only returns as one when
  # simplification is off
  expect_roundtrip(list(), simplify = FALSE)
})

test_that("the two documented asymmetries are the only ones", {
  # a JSON object is always a named list coming back, whatever went in
  expect_identical(json_parse(json_write(c(a = 1.5, b = 2.5))),
                   list(a = 1.5, b = 2.5))
  # an empty array simplifies to logical(0), not to list()
  expect_identical(json_parse(json_write(list())), logical())
})

test_that("the response-body shape an HTTP client actually sees round-trips", {
  body <- list(
    ok = TRUE,
    count = 2L,
    items = list(
      list(id = 1L, name = "first", tags = c("a", "b")),
      list(id = 2L, name = "second", tags = c("c"))
    ),
    next_page = NULL
  )
  # tags = c("c") is length 1, so it needs I() to stay an array
  body$items[[2]]$tags <- I("c")
  parsed <- json_parse(json_write(body))
  expect_identical(parsed$ok, TRUE)
  expect_identical(parsed$count, 2L)
  expect_identical(parsed$items[[1]]$tags, c("a", "b"))
  expect_identical(parsed$items[[2]]$tags, "c")
  expect_identical(parsed$next_page, NULL)
})

test_that("a raw body round-trips through bytes without going via a string", {
  x <- list(query = "search", page = 1L)
  expect_identical(json_parse(json_write_raw(x)), x)
})

test_that("parse/write is stable a second time round", {
  # write(parse(write(parse(s)))) == write(parse(s)) for anything zujson emits
  for (s in c('{"a":1,"b":[1,2]}', "[]", "{}", "null", '["a",null]', "[1,2.5]")) {
    once <- json_write(json_parse(s))
    twice <- json_write(json_parse(once))
    expect_identical(twice, once)
  }
})

test_that("unicode survives the round trip byte for byte", {
  x <- list(a = "☃", b = "é", c = "\U0001F600")
  expect_identical(json_parse(json_write(x)), x)
  expect_identical(json_parse(json_write_raw(x)), x)
})

test_that("a data frame round-trips to a list of row objects", {
  df <- data.frame(id = 1:2, nm = c("a", "b"), stringsAsFactors = FALSE)
  # asymmetric by design: parsing does not rebuild data frames
  expect_identical(json_parse(json_write(df)),
                   list(list(id = 1L, nm = "a"), list(id = 2L, nm = "b")))
})

test_that("deep but legal nesting survives both directions", {
  limit <- zujson_info()$max_depth
  deep <- nested_list(limit - 1L)
  expect_identical(json_parse(json_write(deep), simplify = FALSE), deep)
})

test_that("a large payload round-trips", {
  n <- 10000L
  x <- list(ints = seq_len(n), strs = as.character(seq_len(n)))
  expect_identical(json_parse(json_write(x)), x)
})
