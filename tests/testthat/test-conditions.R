# Everything the package throws is catchable as one class, so a caller wrapping
# a whole request/response cycle does not have to enumerate the failure modes.

test_that("every zujson condition inherits from zujson_error", {
  throwers <- list(
    parse = function() json_parse("{"),
    depth = function() json_parse(nested_json(zujson_info()$max_depth + 1L)),
    unsupported = function() json_write(as.raw(1)),
    arg = function() json_parse(1)
  )
  for (nm in names(throwers)) {
    expect_error(throwers[[nm]](), class = "zujson_error",
                 info = paste("thrower:", nm))
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
