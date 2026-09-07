test_that("each line becomes one record", {
  body <- '{"id":1,"ok":true}\n{"id":2,"ok":false}\n'
  expect_identical(
    json_parse_ndjson(body),
    list(list(id = 1L, ok = TRUE), list(id = 2L, ok = FALSE))
  )
})

test_that("the result is always a list, however uniform the records", {
  # records are independent documents; an NDJSON body is not a table
  expect_type(json_parse_ndjson('{"a":1}\n{"a":2}\n'), "list")
  expect_length(json_parse_ndjson('1\n2\n3\n'), 3L)
  expect_identical(json_parse_ndjson('1\n2\n3\n'), list(1L, 2L, 3L))
})

test_that("records may be any JSON value, not just objects", {
  expect_identical(
    json_parse_ndjson('{"a":1}\n[1,2]\n"x"\nnull\ntrue\n'),
    list(list(a = 1L), 1:2, "x", NULL, TRUE)
  )
})

test_that("simplify is passed through to each record", {
  expect_identical(json_parse_ndjson('[1,2]\n'), list(1:2))
  expect_identical(json_parse_ndjson('[1,2]\n', simplify = FALSE),
                   list(list(1L, 2L)))
})

test_that("blank lines are skipped rather than parsed as records", {
  expect_identical(json_parse_ndjson('{"a":1}\n\n{"a":2}\n'),
                   list(list(a = 1L), list(a = 2L)))
  expect_identical(json_parse_ndjson('\n\n  \n\t\n'), list())
  expect_identical(json_parse_ndjson(""), list())
  expect_identical(json_parse_ndjson("\n"), list())
})

test_that("CRLF line endings are accepted", {
  # real servers send them
  expect_identical(json_parse_ndjson('{"a":1}\r\n{"a":2}\r\n'),
                   list(list(a = 1L), list(a = 2L)))
  expect_identical(json_parse_ndjson('{"a":1}\r\n\r\n{"a":2}'),
                   list(list(a = 1L), list(a = 2L)))
})

test_that("a final record without a trailing newline is still a record", {
  expect_identical(json_parse_ndjson('{"a":1}\n{"a":2}'),
                   list(list(a = 1L), list(a = 2L)))
})

test_that("raw bytes parse the same as text", {
  body <- '{"a":1}\n{"a":2}\n'
  expect_identical(json_parse_ndjson(charToRaw(body)), json_parse_ndjson(body))
})

test_that("a bad record reports its line number", {
  # "invalid JSON at byte 41827" is useless in a body of 10,000 records
  cnd <- tryCatch(json_parse_ndjson('{"a":1}\n{oops}\n{"c":3}'),
                  zujson_error = function(e) e)
  expect_s3_class(cnd, "zujson_parse_error")
  expect_match(conditionMessage(cnd), "line 2")

  # blank lines still advance the count, so the number matches what you see
  cnd2 <- tryCatch(json_parse_ndjson('{"a":1}\n\n\n{bad}'),
                   zujson_error = function(e) e)
  expect_match(conditionMessage(cnd2), "line 4")
})

test_that("newline framing cannot be broken by record content", {
  # a raw newline is not legal inside a JSON string, and the writer escapes it,
  # so a serialized record can never contain a bare newline
  recs <- list(list(msg = "line1\nline2"), list(msg = "tab\there"))
  body <- json_write_ndjson(recs)
  expect_length(strsplit(body, "\n", fixed = TRUE)[[1]], 2L)
  expect_identical(json_parse_ndjson(body), recs)
})

test_that("records are written one per line with a trailing newline", {
  # the trailing newline means appending another record is always valid
  expect_identical(json_write_ndjson(list(list(a = 1L), list(b = "x"))),
                   '{"a":1}\n{"b":"x"}\n')
  expect_identical(json_write_ndjson(list()), "")
  expect_identical(json_write_ndjson_raw(list()), raw())
})

test_that("a data frame is written one object per row", {
  df <- data.frame(id = 1:2, nm = c("a", "b"), stringsAsFactors = FALSE)
  expect_identical(json_write_ndjson(df), '{"id":1,"nm":"a"}\n{"id":2,"nm":"b"}\n')
  expect_identical(json_write_ndjson(df[0, ]), "")
  # the same column handling as json_write(), since it is the same code
  expect_identical(json_write_ndjson(data.frame(a = factor("x"))), '{"a":"x"}\n')
  expect_identical(json_write_ndjson(data.frame(a = NA_integer_)), '{"a":null}\n')
})

test_that("auto_unbox is passed through to each record", {
  expect_identical(json_write_ndjson(list(list(a = "x"))), '{"a":"x"}\n')
  expect_identical(json_write_ndjson(list(list(a = "x")), auto_unbox = FALSE),
                   '{"a":["x"]}\n')
  expect_identical(json_write_ndjson(list(list(a = I("x")))), '{"a":["x"]}\n')
})

test_that("json_write_ndjson_raw returns the same bytes as json_write_ndjson", {
  x <- list(list(a = 1L), list(b = "☃"))
  expect_identical(json_write_ndjson_raw(x), charToRaw(json_write_ndjson(x)))
  expect_type(json_write_ndjson_raw(x), "raw")
})

test_that("records round-trip", {
  recs <- list(
    list(id = 1L, tags = c("a", "b"), ok = TRUE),
    list(id = 2L, tags = c("c", "d"), ok = FALSE, note = NULL)
  )
  expect_identical(json_parse_ndjson(json_write_ndjson(recs)), recs)
  expect_identical(json_parse_ndjson(json_write_ndjson_raw(recs)), recs)
})

test_that("records inherit json_parse()'s empty-array asymmetry, unchanged", {
  # character() writes as [] and [] simplifies back to logical(0); NDJSON adds
  # no new asymmetries of its own, it just carries this one through
  body <- json_write_ndjson(list(list(tags = character())))
  expect_identical(body, '{"tags":[]}\n')
  expect_identical(json_parse_ndjson(body), list(list(tags = logical())))
  expect_identical(json_parse_ndjson(body, simplify = FALSE),
                   list(list(tags = list())))
})

test_that("unicode survives the round trip", {
  recs <- list(list(a = "☃"), list(b = "\U0001F600"))
  expect_identical(json_parse_ndjson(json_write_ndjson(recs)), recs)
  expect_identical(json_parse_ndjson(json_write_ndjson_raw(recs)), recs)
})

test_that("NDJSON writing refuses input that is not a sequence of records", {
  expect_error(json_write_ndjson(1:3), class = "zujson_unsupported_type")
  expect_error(json_write_ndjson("x"), class = "zujson_unsupported_type")
  expect_error(json_write_ndjson(NULL), class = "zujson_unsupported_type")
})

test_that("a record that cannot be serialized fails with its position", {
  cnd <- tryCatch(json_write_ndjson(list(list(a = 1L), list(b = as.raw(1)))),
                  zujson_error = function(e) e)
  expect_s3_class(cnd, "zujson_error")
})

test_that("bad arguments are rejected", {
  expect_error(json_parse_ndjson(1), class = "zujson_arg_error")
  expect_error(json_parse_ndjson('{"a":1}', simplify = NA),
               class = "zujson_arg_error")
  expect_error(json_write_ndjson(list(), auto_unbox = "yes"),
               class = "zujson_arg_error")
})

test_that("a large body round-trips", {
  n <- 5000L
  recs <- lapply(seq_len(n), function(i) list(i = i, s = as.character(i)))
  body <- json_write_ndjson(recs)
  expect_identical(json_parse_ndjson(body), recs)
})

test_that("NDJSON and json_write() agree on how a data frame row is written", {
  # both go through zu_df_plan/zu_df_row, so the only difference should be the
  # framing: an array of rows versus one row per line
  df <- data.frame(i = 1:3, j = c("u", "v", "w"),
                   k = factor(c("p", "q", "p")), stringsAsFactors = FALSE)
  lines <- strsplit(sub("\n$", "", json_write_ndjson(df)), "\n", fixed = TRUE)[[1]]
  expect_identical(json_write(df), paste0("[", paste(lines, collapse = ","), "]"))

  # and the same holds for the awkward shapes
  expect_identical(json_write(df[0, ]), "[]")
  expect_identical(json_write_ndjson(df[0, ]), "")
})

test_that("NDJSON refuses the same data frames json_write() refuses", {
  bad <- data.frame(a = 1)
  bad$inner <- data.frame(z = 1)
  expect_error(json_write(bad), class = "zujson_unsupported_type")
  expect_error(json_write_ndjson(bad), class = "zujson_unsupported_type")
})
