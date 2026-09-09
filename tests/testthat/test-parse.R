test_that("objects become named lists", {
  expect_identical(json_parse('{"a": 1, "b": "x"}'), list(a = 1L, b = "x"))
  expect_identical(json_parse("{}"), structure(list(), names = character()))
})

test_that("an object keeps key order and duplicate keys", {
  expect_identical(names(json_parse('{"b": 1, "a": 2}')), c("b", "a"))
  expect_identical(json_parse('{"a": 1, "a": 2}'), list(a = 1L, a = 2L))
})

test_that("arrays of one numeric kind simplify to that kind", {
  expect_identical(json_parse("[1, 2, 3]"), 1:3)
  expect_identical(json_parse("[1, 2.5]"), c(1, 2.5))
  expect_identical(json_parse("[true, false]"), c(TRUE, FALSE))
  expect_identical(json_parse('["a", "b"]'), c("a", "b"))
})

test_that("logicals promote into the numeric family but strings do not", {
  # TRUE -> 1 is lossless, so [true, 1] is an integer vector ...
  expect_identical(json_parse("[true, 1]"), c(1L, 1L))
  # ... while "1" -> 1 is not, so a mixed array stays a list.
  expect_identical(json_parse('[1, "a"]'), list(1L, "a"))
  expect_identical(json_parse('[true, "a"]'), list(TRUE, "a"))
})

test_that("a nested container forces a list", {
  expect_identical(json_parse("[1, {}]"),
                   list(1L, structure(list(), names = character())))
  expect_identical(json_parse("[[1], [2]]"), list(1L, 2L))
})

test_that("empty and all-null arrays are logical", {
  expect_identical(json_parse("[]"), logical())
  expect_identical(json_parse("[null, null]"), c(NA, NA))
})

test_that("null becomes NA inside a simplified array and NULL elsewhere", {
  expect_identical(json_parse("[1, null]"), c(1L, NA))
  expect_identical(json_parse('["a", null]'), c("a", NA))
  expect_identical(json_parse("null"), NULL)
  expect_identical(json_parse('{"a": null}'), list(a = NULL))
  expect_identical(json_parse("[1, null]", simplify = FALSE), list(1L, NULL))
})

test_that("simplify = FALSE makes every array a list", {
  expect_identical(json_parse("[1, 2, 3]", simplify = FALSE), list(1L, 2L, 3L))
  expect_identical(json_parse("[]", simplify = FALSE), list())
  # objects are unaffected: they are always named lists
  expect_identical(json_parse('{"a": [1]}', simplify = FALSE), list(a = list(1L)))
})

test_that("integers that do not fit R's int32 become doubles", {
  expect_identical(json_parse("2147483647"), 2147483647L)
  expect_identical(json_parse("2147483648"), 2147483648)
  expect_identical(json_parse("-2147483647"), -2147483647L)
  # -2147483648 is NA_INTEGER's bit pattern, so it must promote
  expect_identical(json_parse("-2147483648"), -2147483648)
  expect_identical(json_parse("[1, 9999999999]"), c(1, 9999999999))
})

test_that("scalars at the root parse as length-1 vectors", {
  expect_identical(json_parse("1"), 1L)
  expect_identical(json_parse("1.5"), 1.5)
  expect_identical(json_parse("true"), TRUE)
  expect_identical(json_parse('"x"'), "x")
})

test_that("strings arrive as UTF-8", {
  # spelled by code point so the test does not depend on this file's encoding
  snowman <- json_parse('["\\u2603"]')
  expect_identical(Encoding(snowman), "UTF-8")
  expect_identical(snowman, "☃")
  expect_identical(json_parse('{"\\u2603": 1}'), stats::setNames(list(1L), "☃"))
})

test_that("escapes are decoded", {
  expect_identical(json_parse('"a\\nb"'), "a\nb")
  expect_identical(json_parse('"a\\"b"'), 'a"b')
  expect_identical(json_parse('"a\\\\b"'), "a\\b")
})

test_that("raw input parses the same as text", {
  expect_identical(json_parse(charToRaw('{"a": 1}')), list(a = 1L))
  expect_identical(json_parse_raw(charToRaw("[1, 2]")), 1:2)
  expect_identical(json_parse_raw(charToRaw("[]"), simplify = FALSE), list())
})

test_that("json_parse_file reads a file", {
  path <- withr::local_tempfile(fileext = ".json")
  writeLines('{"a": [1, 2]}', path)
  expect_identical(json_parse_file(path), list(a = 1:2))
  expect_identical(json_parse_file(path, simplify = FALSE), list(a = list(1L, 2L)))
})

test_that("malformed JSON is a zujson_parse_error", {
  expect_error(json_parse("{"), class = "zujson_parse_error")
  expect_error(json_parse("{'a': 1}"), class = "zujson_parse_error")
  expect_error(json_parse(""), class = "zujson_parse_error")
  expect_error(json_parse("[1,]"), class = "zujson_parse_error")
  expect_error(json_parse_raw(charToRaw("{")), class = "zujson_parse_error")
})

test_that("trailing content is rejected", {
  expect_error(json_parse("{} {}"), class = "zujson_parse_error")
  expect_error(json_parse("1 2"), class = "zujson_parse_error")
})

test_that("invalid UTF-8 in the input is rejected", {
  expect_error(json_parse_raw(as.raw(c(0x22, 0xff, 0x22))),
               class = "zujson_parse_error")
})

test_that("nesting past the depth limit is rejected rather than crashing", {
  limit <- zujson_info()$max_depth
  expect_no_error(json_parse(nested_json(limit)))
  expect_error(json_parse(nested_json(limit + 1L)), class = "zujson_depth_error")
  # simplify = FALSE walks the same recursion
  expect_error(json_parse(nested_json(limit + 1L), simplify = FALSE),
               class = "zujson_depth_error")
})

test_that("bad arguments are rejected before reaching C", {
  expect_error(json_parse(1), class = "zujson_arg_error")
  expect_error(json_parse(NA_character_), class = "zujson_arg_error")
  expect_error(json_parse(c("[]", "[]")), class = "zujson_arg_error")
  expect_error(json_parse("[]", simplify = NA), class = "zujson_arg_error")
  expect_error(json_parse_raw("[]"), class = "zujson_arg_error")
  expect_error(json_parse_file(tempfile()), class = "zujson_arg_error")
})

test_that("a NUL an R string cannot hold is a structured error, not a bare one", {
  # The six-character escape is legal JSON but decodes to a byte no R string
  # can contain. Left to the R internals this raises a bare simpleError, which
  # would escape the zujson_error contract every caller handles on.
  esc <- paste0("\\", "u0000")
  expect_error(json_parse(paste0('["a', esc, 'b"]')),
               class = "zujson_parse_error")
  expect_error(json_parse(paste0('{"a', esc, 'b": 1}')),
               class = "zujson_parse_error")
  expect_error(json_parse(paste0('{"k": "a', esc, 'b"}')),
               class = "zujson_error")
})

test_that("a leading UTF-8 BOM is ignored rather than rejected", {
  # RFC 8259 forbids emitting one but allows ignoring it, and real APIs emit
  # them; failing a response body over three bytes would help nobody.
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  expect_identical(json_parse(c(bom, charToRaw("[1, 2]"))), 1:2)
  expect_identical(json_parse(c(bom, charToRaw('{"a": 1}'))), list(a = 1L))
  expect_true(json_validate(c(bom, charToRaw("[]"))))
})

test_that("an unreadable file is an io error, not a parse error", {
  # "could not open it" and "it is not JSON" have different fixes
  dir <- withr::local_tempdir()
  expect_error(json_parse_file(dir), class = "zujson_io_error")
})

test_that("a file that cannot be opened is an io error too", {
  # The directory case above is classified in R, because C cannot do it
  # portably. This one reaches yyjson's own file-open failure, so it is what
  # keeps the C-side io/parse split honest.
  skip_on_os("windows")  # permission bits do not deny the owner there
  if (identical(unname(Sys.info()[["user"]]), "root")) {
    skip("root ignores the permission bits")
  }
  path <- withr::local_tempfile(fileext = ".json")
  writeLines('{"a": 1}', path)
  Sys.chmod(path, "000")
  skip_if(file.access(path, mode = 4L) == 0L, "file is still readable")
  expect_error(json_parse_file(path), class = "zujson_io_error")
})

test_that("json_parse_file expands a tilde path", {
  # file.exists() expands ~ and fopen() does not, so without expansion a
  # perfectly readable file reports itself as unreadable
  name <- paste0("zujson-test-", Sys.getpid(), ".json")
  path <- file.path(path.expand("~"), name)
  withr::defer(unlink(path))
  writeLines('{"a": 1}', path)
  expect_identical(json_parse_file(file.path("~", name)), list(a = 1L))
})
