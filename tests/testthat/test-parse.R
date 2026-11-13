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

test_that("a number too large for a double becomes Inf, not an error", {
  # RFC 8259 puts no limit on the magnitude of a number, so 1e309 is valid
  # JSON. Rejecting the document would let one absurd value anywhere in a
  # response body make the whole body unreadable.
  expect_identical(json_parse("1e309"), Inf)
  expect_identical(json_parse("-1e309"), -Inf)
  expect_identical(json_parse("[1.5e400]"), Inf)
  expect_identical(json_parse('{"a": 1e309}'), list(a = Inf))
  # the value is the one R's own reader gives the same token
  expect_identical(json_parse("1e309"), as.numeric("1e309"))

  # Still finite either side of the boundary. 1e308 is spelled as its exact
  # bits rather than as the literal 1e308: R's own reader accumulates through
  # LDOUBLE, which is plain double on aarch64, so there the literal is a few
  # ULPs off the double yyjson correctly rounds the token to.
  expect_identical(json_parse("[1e308]"), 0x1.1ccf385ebc8ap+1023)
  expect_identical(json_parse("[1e-400]"), 0)          # underflow, not overflow

  # An integer wider than int64 is the nearest double: the correctly rounded
  # value, written in hex so no decimal reader is in the oracle. This used to
  # assert as.numeric(), which is not correctly rounded -- on arm64, where long
  # double is double, it is many ulps off for this very token (#46).
  expect_identical(json_parse("[123456789012345678901234567890]"),
                   0x1.8ee90ff6c373ep+96)

  # and it is an ordinary double once there, so it simplifies with the rest
  expect_identical(json_parse("[1e309, 2]"), c(Inf, 2))
  expect_identical(json_parse("[1e309, null]"), c(Inf, NA))
  expect_identical(json_parse('[1e309, "a"]'), list(Inf, "a"))
  expect_identical(json_parse('[1e309, "a"]', simplify = "coerce"),
                   c("Inf", "a"))
  expect_identical(json_parse('[{"a":1e309},{"a":2}]', data_frame = TRUE),
                   data.frame(a = c(Inf, 2)))
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

test_that("data_frame = TRUE charges the record objects a level of their own", {
  # the array is one level and every record another, so the same document has
  # to be accepted or rejected the same way whichever option is passed --
  # otherwise json_write() can emit a frame json_parse() will not read back
  limit <- zujson_info()$max_depth
  cell <- function(k) {
    paste0('[{"a":', strrep("[", k), "1", strrep("]", k), "}]")
  }
  for (total in c(limit - 1L, limit, limit + 1L)) {
    k <- total - 2L                       # the array and the record object
    plain <- tryCatch(json_parse(cell(k)), zujson_depth_error = function(e) e)
    frame <- tryCatch(json_parse(cell(k), data_frame = TRUE),
                      zujson_depth_error = function(e) e)
    expect_identical(inherits(plain, "condition"), inherits(frame, "condition"),
                     info = paste("total depth", total))
    expect_identical(inherits(plain, "condition"), total > limit,
                     info = paste("total depth", total))
  }

  # the record object counts even when nothing is nested inside it
  deep <- paste0(strrep("[", limit), '{"a":1}', strrep("]", limit))
  expect_error(json_parse(deep, data_frame = TRUE), class = "zujson_depth_error")
  expect_error(json_parse(deep), class = "zujson_depth_error")
})

test_that("a string marked \"bytes\" is a structured error, not a bare one", {
  # Rf_translateCharUTF8() raises a bare simpleError on an unknown encoding,
  # which would escape the zujson_error contract every caller handles on
  bytes <- "\xe4\xf6"
  Encoding(bytes) <- "bytes"
  expect_error(json_parse(bytes), class = "zujson_arg_error")
  expect_error(json_validate(bytes), class = "zujson_arg_error")
  expect_error(json_parse_file(bytes), class = "zujson_arg_error")
  expect_error(json_parse_ndjson(bytes), class = "zujson_arg_error")
  # the raw path is what such bytes are for, and still works
  expect_true(json_validate(charToRaw('{"a":1}')))
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

test_that("an integer wider than uint64 parses to the nearest double", {
  # It went through R_strtod, which is not correctly rounded: 1 in about
  # 1000 such integers came back 1 ulp off, and differed from the same digits
  # spelled with ".0" (#46). The ".0" spelling is read by yyjson's correctly
  # rounded reader, so it is the oracle.
  d <- "7908650058519908757503158852011"
  expect_identical(json_parse(d), json_parse(paste0(d, ".0")))
  expect_identical(sprintf("%a", json_parse(d)), "0x1.8f48e7ffdefabp+102")
  withr::local_seed(46)
  digits <- vapply(sample(20:120, 300, TRUE), function(n) {
    paste0(sample(1:9, 1), paste(sample(0:9, n - 1, TRUE), collapse = ""))
  }, "")
  # all 300 through the atomic-array fill, and 20 of them as scalars
  expect_identical(
    json_parse(paste0("[", paste(digits, collapse = ","), "]")),
    json_parse(paste0("[", paste0(digits, ".0", collapse = ","), "]"))
  )
  for (d in digits[1:20]) {
    expect_identical(json_parse(d), json_parse(paste0(d, ".0")), info = d)
  }
})

test_that("the double range is straddled at DBL_MAX and the subnormal end", {
  # Two components decide this limit: yyjson chooses the RAW path and the
  # converter reads it. The window between 1e308 and 1e309 is where they
  # could disagree (#35).
  xmax <- .Machine$double.xmax
  expect_identical(json_parse("1.7976931348623157e308"), xmax)
  expect_identical(json_parse("1.797693134862315807e308"), xmax)
  expect_identical(json_parse("1.797693134862315808e308"), Inf)
  expect_identical(json_parse("-1.797693134862315807e308"), -xmax)
  expect_identical(json_parse("-1.797693134862315808e308"), -Inf)
  # the 309-digit integer one below the round-to-Inf midpoint is finite, and
  # the midpoint itself rounds to Inf
  below <- paste0(
    "17976931348623158079372897140530341507993413271003782693617377898044",
    "49682927647509466490179775872070963302864166928879109465555478519404",
    "02630657488671505820681908902000708383676273854845817711531764475730",
    "27006985557136695962284291481986083493647529271907416844436551070434",
    "2711559699508093042880177904174497791"
  )
  expect_identical(nchar(below), 309L)
  expect_identical(json_parse(below), xmax)
  expect_identical(json_parse(paste0("-", below)), -xmax)
  # the same edges inside an atomic array, which is a separate fill path
  expect_identical(json_parse(paste0("[", below, ",1e309]")), c(xmax, Inf))
  # the subnormal end: the smallest subnormal and what rounds to zero
  expect_identical(json_parse("4.9e-324"), 2^-1074)
  expect_identical(json_parse("2.5e-324"), 2^-1074)
  expect_identical(json_parse("2e-324"), 0)
  expect_identical(json_parse("[1e-400,4.9e-324]"), c(0, 2^-1074))
})

test_that("colliding keys do not make the data frame index quadratic", {
  # The key index hashed with unseeded FNV-1a, whose low bits can be made to
  # collide at will: 2^15 such keys took 5.7 s against 0.014 s (#44). The
  # pairs below are a Joux multicollision on the low 24 bits of that hash;
  # 14 of them give 2^14 keys that all landed in one probe chain.
  skip_on_cran()
  pairs <- list(
    c("b3k8", "cpqf"), c("a6q2", "c2ba"), c("a839", "cisb"), c("a1i8", "bpcv"),
    c("b7ez", "crna"), c("aw73", "bgfa"), c("a6p0", "c2aa"), c("anv8", "cc0a"),
    c("b7z8", "cpdf"), c("b7k8", "cpar"), c("b3f8", "ctdv"), c("b2i8", "cugv"),
    c("b7g8", "cper"), c("aqt6", "cb2a")
  )
  keys <- ""
  for (p in pairs) keys <- c(paste0(keys, p[1]), paste0(keys, p[2]))
  expect_length(unique(keys), 2^14)
  body <- function(k) {
    paste0("[{", paste0('"', k, '":1', collapse = ","), "}]")
  }
  control <- vapply(seq_along(keys), function(i) {
    paste(sample(c(letters, 0:9), 56, TRUE), collapse = "")
  }, "")
  t_ctl <- system.time(json_parse(body(control), data_frame = TRUE))[["elapsed"]]
  t_col <- system.time(json_parse(body(keys), data_frame = TRUE))[["elapsed"]]
  expect_lt(t_col, max(10 * t_ctl, 0.25))
})

test_that("a string that cannot be converted to UTF-8 is refused, not rewritten", {
  # R's conversion substitutes "<xx>" for a byte it cannot convert, so an
  # unmarked non-ASCII string under the C locale came back as the ASCII text
  # "caf<c3><a9>", and invalid UTF-8 validated as TRUE (#42).
  cafe <- rawToChar(as.raw(c(0x22, 0x63, 0x61, 0x66, 0xc3, 0xa9, 0x22)))
  bad <- rawToChar(as.raw(c(0x5b, 0x22, 0xe9, 0x22, 0x5d)))
  # The C locale is ASCII on Unix, which is the case this pins. Windows maps
  # it to a code page in which these bytes convert, so it is skipped there.
  skip_on_os("windows")
  withr::local_locale(c(LC_CTYPE = "C"))
  expect_error(json_parse(cafe), class = "zujson_parse_error")
  expect_error(json_parse_ndjson(cafe), class = "zujson_parse_error")
  expect_false(json_validate(cafe))
  expect_error(json_parse(bad), class = "zujson_parse_error")
  expect_false(json_validate(bad))
  # the raw route reads the bytes as the UTF-8 JSON is, in any locale
  expect_identical(json_parse(charToRaw(cafe)), "café")
  # a string marked UTF-8 is not converted at all
  marked <- cafe
  Encoding(marked) <- "UTF-8"
  expect_identical(json_parse(marked), "café")
})

test_that("json_parse_file() opens a non-ASCII path in any locale", {
  # The R check used the native path and the C open a translated one, so
  # under the C locale a readable file was "failed to read" (#50).
  dir <- withr::local_tempdir()
  path <- file.path(dir, "cé.json")
  skip_if_not(file.create(path), "the file system refuses the name")
  writeBin(charToRaw('{"a":[1,2]}'), path)
  expect_identical(json_parse_file(path), list(a = 1:2))
  # The C locale is ASCII on Unix, which is the case this pins. Windows maps
  # it to a code page in which these bytes convert, so it is skipped there.
  skip_on_os("windows")
  native <- rawToChar(charToRaw(enc2utf8(path)))   # unmarked bytes
  withr::local_locale(c(LC_CTYPE = "C"))
  expect_identical(json_parse_file(native), list(a = 1:2))
})

test_that("json_parse_file() reads through a connection, whatever the file is", {
  # The bytes are read in R and parsed by the raw route, so the file route is
  # the raw route: the same value and the same error classes (#50).
  dir <- withr::local_tempdir()
  path <- file.path(dir, "big.json")
  body <- paste0("[", paste(seq_len(200000), collapse = ","), "]")
  writeBin(charToRaw(body), path)
  expect_identical(json_parse_file(path), json_parse_raw(charToRaw(body)))
  empty <- file.path(dir, "empty.json")
  file.create(empty)
  expect_error(json_parse_file(empty), class = "zujson_parse_error")
  expect_error(json_parse_file(dir), class = "zujson_io_error")
  expect_error(json_parse_file(file.path(dir, "absent.json")),
               class = "zujson_arg_error")
})
