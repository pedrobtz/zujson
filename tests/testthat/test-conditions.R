# Everything the package throws is catchable as one class, so a caller wrapping
# a whole request/response cycle does not have to enumerate the failure modes.

test_that("every zujson condition inherits from zujson_error", {
  bad_utf8 <- rawToChar(as.raw(c(0x61, 0xff, 0x62)))
  Encoding(bad_utf8) <- "UTF-8"
  # one entry per class the package can raise; the names are the classes, so a
  # class that stops being reachable fails here rather than rotting silently
  throwers <- list(
    zujson_parse_error       = function() json_parse("{"),
    zujson_depth_error       = function() json_parse(nested_json(zujson_info()$max_depth + 1L)),
    zujson_unsupported_type  = function() json_write(as.raw(1)),
    zujson_write_error       = function() json_write(bad_utf8),
    zujson_io_error          = function() json_parse_file(withr::local_tempdir()),
    zujson_arg_error         = function() json_parse(1)
  )
  for (nm in names(throwers)) {
    expect_error(throwers[[nm]](), class = nm, info = nm)
    expect_error(throwers[[nm]](), class = "zujson_error", info = nm)
  }
})

test_that("conditions carry a message and no misleading call", {
  cnd <- tryCatch(json_parse("{"), zujson_error = function(e) e)
  expect_s3_class(cnd, "zujson_parse_error")
  expect_true(nzchar(conditionMessage(cnd)))
  expect_null(conditionCall(cnd))
})

test_that("a parse error names the byte position", {
  cnd <- tryCatch(json_parse('{"a": }'), zujson_error = function(e) e)
  expect_match(conditionMessage(cnd), "byte [0-9]+")
})

test_that("an error leaves nothing behind that breaks the next call", {
  # the C side hands its document to R before it can signal, so a failure
  # mid-parse must not affect what follows
  for (i in 1:50) {
    expect_error(json_parse("{"), class = "zujson_parse_error")
    expect_identical(json_parse('{"a": 1}'), list(a = 1L))
    expect_error(json_write(as.raw(1)), class = "zujson_unsupported_type")
    expect_identical(json_write(list(a = 1L)), '{"a":1}')
  }
  gc()
  expect_identical(json_parse('{"a": 1}'), list(a = 1L))
})

test_that("condition messages are valid UTF-8 however they are cut", {
  # A key cut at 64 bytes, or a message at 512, could end mid-character, and
  # the message was not marked UTF-8 (#53).
  key <- paste0("a", strrep("\u00e9", 40))
  cnd <- tryCatch(
    json_parse(sprintf('[{"%s":1,"%s":2}]', key, key), data_frame = TRUE),
    zujson_error = function(e) e
  )
  expect_s3_class(cnd, "zujson_parse_error")
  expect_true(validUTF8(conditionMessage(cnd)))
  expect_no_error(nchar(conditionMessage(cnd)))

  long <- strrep("\u00e9", 300)
  d <- structure(list(1:2, 1:3), names = c("a", long), class = "data.frame",
                 row.names = 1:2)
  cnd <- tryCatch(json_write(d), zujson_error = function(e) e)
  expect_s3_class(cnd, "zujson_unsupported_type")
  expect_true(validUTF8(conditionMessage(cnd)))
  expect_identical(Encoding(conditionMessage(cnd)), "UTF-8")
})

test_that("a message stays valid UTF-8 when the name it quotes is not", {
  # #53 marked every message UTF-8, but a quoted name went through unchecked,
  # so a name with invalid bytes made a message marked UTF-8 that was not
  # (#76). The bad byte is shown as <ff>.
  bad <- "c\xffd"
  marked <- bad
  Encoding(marked) <- "UTF-8"
  for (nm in list(bad, marked)) {
    d <- structure(list(a = quote(x)), class = "data.frame", row.names = 1L)
    names(d) <- nm
    cnd <- tryCatch(json_write(d), zujson_error = function(e) e)
    expect_s3_class(cnd, "zujson_unsupported_type")
    expect_true(validUTF8(conditionMessage(cnd)))
    expect_match(conditionMessage(cnd), "<ff>", fixed = TRUE)
    d2 <- structure(list(1:2, 1:3), names = c("a", nm), class = "data.frame",
                    row.names = 1:2)
    cnd <- tryCatch(json_write(d2), zujson_error = function(e) e)
    expect_true(validUTF8(conditionMessage(cnd)))
  }
})
