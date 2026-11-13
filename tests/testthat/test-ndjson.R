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

test_that("every NDJSON error names its line", {
  # Errors raised while building a record, not reading it, named no line
  # (#54). Each is on line 3.
  deep <- paste0(strrep("[", 1001), strrep("]", 1001))
  cases <- list(
    zujson_parse_error = '1\n2\n{oops}\n',
    zujson_parse_error = '1\n2\n"\\u0000"\n',
    zujson_depth_error = paste0("1\n2\n", deep, "\n"),
    zujson_parse_error = '1\n\n[{"k":1,"k":2}]\n'
  )
  for (i in seq_along(cases)) {
    cnd <- tryCatch(json_parse_ndjson(cases[[i]], data_frame = TRUE),
                    zujson_error = function(e) e)
    expect_s3_class(cnd, names(cases)[i])
    expect_match(conditionMessage(cnd), "line 3", info = cases[[i]])
  }
  withr::local_options(zujson.max_df_cells = 1)
  cnd <- tryCatch(json_parse_ndjson('1\n2\n[{"a":1,"b":2}]\n', data_frame = TRUE),
                  zujson_error = function(e) e)
  expect_s3_class(cnd, "zujson_limit_error")
  expect_match(conditionMessage(cnd), "line 3")
  # and the line context does not leak into the next, unrelated error
  cnd <- tryCatch(json_parse("[1,"), zujson_error = function(e) e)
  expect_no_match(conditionMessage(cnd), "line")
})

test_that("a BOM is accepted only at the start of an NDJSON body", {
  # Each line was read with ALLOW_BOM, so one was accepted on any line, while
  # a BOM-only first line was "empty" rather than blank (#56).
  bom <- "\ufeff"
  expect_identical(json_parse_ndjson(paste0(bom, "1\n2\n")), list(1L, 2L))
  expect_identical(json_parse_ndjson(charToRaw(paste0(bom, "1\n2\n"))),
                   list(1L, 2L))
  expect_identical(json_parse_ndjson(paste0(bom, "\n1\n")), list(1L))
  expect_identical(json_parse_ndjson(bom), list())
  expect_error(json_parse_ndjson(paste0("1\n", bom, "2\n")),
               class = "zujson_parse_error")
})

test_that("the depth limit holds per record, in both directions", {
  # NDJSON has its own read and write drivers, and the limit had only been
  # straddled through json_parse() and json_write() (#33).
  limit <- zujson_info()$max_depth
  for (d in c(limit - 1L, limit)) {
    expect_identical(json_parse_ndjson(paste0("1\n", nested_json(d), "\n"))[[2]],
                     json_parse(nested_json(d)))
    expect_no_error(json_write_ndjson(list(1L, nested_list(d))))
  }
  expect_error(json_parse_ndjson(paste0("1\n", nested_json(limit + 1L), "\n")),
               class = "zujson_depth_error")
  expect_error(json_write_ndjson(list(1L, nested_list(limit + 1L))),
               class = "zujson_depth_error")
  # a data frame record with a container in a cell: array, row, cell
  cell <- function(k) paste0('[{"c":', nested_json(k), "}]")
  expect_no_error(json_parse_ndjson(cell(limit - 2L), data_frame = TRUE))
  expect_error(json_parse_ndjson(cell(limit - 1L), data_frame = TRUE),
               class = "zujson_depth_error")
})
