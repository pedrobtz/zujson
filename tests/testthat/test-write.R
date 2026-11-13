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

test_that("whole doubles lose the decimal point across the whole int64 range", {
  # a double that is already a whole number IS that integer, whatever its
  # magnitude, so the conversion is lossless well past 2^53
  expect_json(1e15, "1000000000000000")
  expect_json(1e16, "10000000000000000")
  expect_json(1e18, "1000000000000000000")
  expect_json(2^53 + 2, "9007199254740994")
  expect_json(-1e16, "-10000000000000000")
  # past int64 there is no integer form, so the real writer takes over
  expect_match(json_write(1e300), "e", fixed = TRUE)
  # and every one of them still reads back as the same number
  for (v in c(1e15, 1e16, 1e18, 2^53 + 2, -1e16, 1e300)) {
    expect_identical(as.numeric(json_parse(json_write(v))), v)
  }
})

test_that("POSIXlt is refused rather than emitted as its internal fields", {
  # without this it serializes as {"sec":..,"min":..,"gmtoff":..}, which is
  # valid JSON and never what anyone meant by sending a timestamp
  expect_error(json_write(as.POSIXlt("2026-09-07", tz = "UTC")),
               class = "zujson_unsupported_type")
  expect_error(json_write(list(at = as.POSIXlt("2026-09-07", tz = "UTC"))),
               class = "zujson_unsupported_type")
  # the message says what to do about it
  cnd <- tryCatch(json_write(as.POSIXlt("2026-09-07", tz = "UTC")),
                  zujson_error = function(e) e)
  expect_match(conditionMessage(cnd), "as.POSIXct")
})

test_that("a matrix is flattened column-major and loses its dim", {
  # documented rather than supported: matrix simplification is out of scope for
  # v1, and this pins what actually happens so it cannot change unnoticed
  expect_json(matrix(1:6, nrow = 2), "[1,2,3,4,5,6]")
  expect_json(matrix(1:6, nrow = 2, byrow = TRUE), "[1,4,2,5,3,6]")
})

test_that("a data frame with no columns keeps its rows", {
  # df[, 0] is n rows of nothing, which is n empty objects -- not no rows
  expect_json(data.frame(a = 1:3)[, 0, drop = FALSE], "[{},{},{}]")
  expect_json(data.frame(a = integer())[, 0, drop = FALSE], "[]")
})

test_that("a data frame is charged for both container levels it emits", {
  # it writes an array of row objects, so json_write() must not emit JSON that
  # json_parse() would then reject as too deep
  limit <- zujson_info()$max_depth
  nest <- function(n) Reduce(function(acc, i) list(acc), seq_len(n),
                             data.frame(a = 1))
  ok <- json_write(nest(limit - 2L))
  expect_no_error(json_parse(ok))
  expect_error(json_write(nest(limit - 1L)), class = "zujson_depth_error")
})

test_that("a data frame cell is charged the level it actually occupies", {
  # the cell sits inside the row object, which sits inside the array: charging
  # it twice rejected a frame whose JSON was exactly at the limit
  limit <- zujson_info()$max_depth
  nest <- function(k) { x <- 1L; for (i in seq_len(k)) x <- list(x); x }
  cell <- function(k) {
    d <- data.frame(id = 1L)
    d$a <- I(list(nest(k)))
    d
  }
  # emitted depth is k + 2: the array, the row object, then the cell
  at_limit <- json_write(cell(limit - 2L))
  expect_no_error(json_parse(at_limit))
  expect_error(json_write(cell(limit - 1L)), class = "zujson_depth_error")
})

test_that("a timestamp outside four-digit years is a write error", {
  # Date and POSIXct are doubles, so they reach far past what ISO 8601 can
  # write -- and past what the conversion to int64 is even defined for
  expect_identical(json_write(structure(-719528, class = "Date")),
                   '"0000-01-01"')
  expect_identical(json_write(structure(2932896, class = "Date")),
                   '"9999-12-31"')
  expect_error(json_write(structure(-719529, class = "Date")),
               class = "zujson_write_error")
  expect_error(json_write(structure(2932897, class = "Date")),
               class = "zujson_write_error")
  expect_error(json_write(structure(1e300, class = "Date")),
               class = "zujson_write_error")

  expect_identical(json_write(.POSIXct(-62167219200, tz = "UTC")),
                   '"0000-01-01T00:00:00Z"')
  expect_identical(json_write(.POSIXct(253402300799, tz = "UTC")),
                   '"9999-12-31T23:59:59Z"')
  expect_error(json_write(.POSIXct(253402300800, tz = "UTC")),
               class = "zujson_write_error")
  expect_error(json_write(.POSIXct(-1e300, tz = "UTC")),
               class = "zujson_write_error")

  # NA is still null rather than an error, and one bad element is enough
  expect_identical(json_write(.POSIXct(NA_real_, tz = "UTC")), "null")
  expect_error(json_write(structure(c(0, 1e300), class = "Date")),
               class = "zujson_write_error")
})

test_that("a string marked \"bytes\" is a write error, not a bare one", {
  # "bytes" means R does not know the encoding, and JSON text is UTF-8 by
  # definition, so translateCharUTF8() would raise a bare simpleError
  bytes <- "\xe4\xf6"
  Encoding(bytes) <- "bytes"
  expect_error(json_write(bytes), class = "zujson_write_error")
  expect_error(json_write(list(a = bytes)), class = "zujson_write_error")
  expect_error(json_write(stats::setNames(list(1), bytes)),
               class = "zujson_write_error")
  expect_error(json_write(data.frame(x = bytes)), class = "zujson_write_error")
  expect_error(json_write_raw(bytes), class = "zujson_error")
})

test_that("a string that is not the UTF-8 it claims to be is a write error", {
  # reachable from ordinary input, so the class has to be part of the contract
  bad <- rawToChar(as.raw(c(0x61, 0xff, 0x62)))
  Encoding(bad) <- "UTF-8"
  expect_error(json_write(bad), class = "zujson_write_error")
  expect_error(json_write(list(a = bad)), class = "zujson_write_error")
  expect_error(json_write_raw(bad), class = "zujson_error")
})

test_that("POSIXlt is refused on every writer entry point", {
  # A data frame column and the NDJSON top level used to skip the guard and
  # emit the 11 broken-down fields as data -- one field per row (#40).
  lt <- function(n) {
    as.POSIXlt(as.POSIXct("2024-01-01", tz = "UTC") + seq_len(n), tz = "UTC")
  }
  d11 <- data.frame(id = 1:11)
  d11$t <- lt(11)
  d3 <- data.frame(id = 1:3)
  d3$t <- lt(3)
  for (d in list(d11, d3)) {
    expect_error(json_write(d), class = "zujson_unsupported_type")
    expect_error(json_write_ndjson(d), class = "zujson_unsupported_type")
    expect_error(json_write(list(d)), class = "zujson_unsupported_type")
  }
  expect_error(json_write_ndjson(lt(1)), class = "zujson_unsupported_type")
  expect_error(json_write_ndjson(lt(11)), class = "zujson_unsupported_type")
  # the paths that were already guarded stay guarded
  expect_error(json_write(lt(1)), class = "zujson_unsupported_type")
  expect_error(json_write(list(a = lt(1))), class = "zujson_unsupported_type")
  expect_error(
    json_write_ndjson(list(lt(1))),
    class = "zujson_unsupported_type"
  )
})

test_that("POSIXct just below a day boundary floors to 23:59:59, never 24:00", {
  # secs - floor(secs / 86400) * 86400 used to round to exactly 86400 for a
  # value a hair below midnight, printing hour 24 (#41)
  expect_json(.POSIXct(-1e-12, tz = "UTC"), '"1969-12-31T23:59:59Z"')
  expect_json(
    as.POSIXct("1970-01-01", tz = "UTC") + (0.3 - 0.1 - 0.2),
    '"1969-12-31T23:59:59Z"'
  )
  expect_json(.POSIXct(-5e-324, tz = "UTC"), '"1969-12-31T23:59:59Z"')
  # Near year 0 the expected text is written out: format() does not zero-pad
  # years before 1000 on every platform ("0-01-02" on Linux), so it is the
  # oracle only from year 1000 on.
  expect_json(.POSIXct(-719527 * 86400 - 1e-3, tz = "UTC"),
              '"0000-01-01T23:59:59Z"')
  expect_json(.POSIXct(-719527 * 86400 - 0.5, tz = "UTC"),
              '"0000-01-01T23:59:59Z"')
  for (k in c(-354284, -2, -1, 0, 1, 19675, 2932896)) {
    for (eps in c(1e-12, 1e-9, 1e-6, 0.5)) {
      x <- .POSIXct(k * 86400 - eps, tz = "UTC")
      want <- format(
        .POSIXct(floor(unclass(x)), tz = "UTC"),
        "%Y-%m-%dT%H:%M:%SZ",
        tz = "UTC"
      )
      expect_identical(
        json_write(x),
        paste0('"', want, '"'),
        info = paste("k =", k, "eps =", eps)
      )
    }
  }
})

test_that("Date and POSIXct agree with format() across four-digit years", {
  # The oracle is base R's formatter. It is restricted to years 1000-9999,
  # where every platform's format() zero-pads the same way (#31).
  withr::local_seed(20261113)
  lo <- as.numeric(as.Date("1000-01-01"))
  hi <- as.numeric(as.Date("9999-12-31"))
  days <- c(lo, hi, 0, -1, 59, 60, 11016, 10957, 47541, sample(lo:hi, 2000))
  d <- structure(as.double(days), class = "Date")
  expect_identical(json_parse(json_write(I(d))), format(d, "%Y-%m-%d"))

  secs <- c(
    lo * 86400,
    hi * 86400 + 86399,
    -1,
    0,
    stats::runif(2000, lo * 86400, hi * 86400 + 86399)
  )
  p <- .POSIXct(secs, tz = "UTC")
  want <- format(
    .POSIXct(floor(secs), tz = "UTC"),
    "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  )
  expect_identical(json_parse(json_write(I(p))), want)
})

test_that("whole doubles are integer text exactly on [-2^63, 2^63)", {
  # -2^63 is inclusive and 2^63 exclusive: the conversion to int64 is
  # undefined just past either end, so both edges are pinned (#36)
  expect_json(-2^63, "-9223372036854775808")
  expect_json(2^63 - 1024, "9223372036854774784")
  for (v in c(2^63, -2^63 - 2048)) {
    out <- json_write(v)
    expect_match(out, "[.eE]")
    expect_identical(as.numeric(json_parse(out)), v)
  }
})

test_that("POSIXct is straddled at the lower end of the range too", {
  expect_json(.POSIXct(-62167219200, tz = "UTC"), '"0000-01-01T00:00:00Z"')
  expect_json(.POSIXct(-62167219199.5, tz = "UTC"), '"0000-01-01T00:00:00Z"')
  # half a second earlier floors into the year -1
  expect_error(
    json_write(.POSIXct(-62167219200.5, tz = "UTC")),
    class = "zujson_write_error"
  )
  expect_error(
    json_write(.POSIXct(-62167219201, tz = "UTC")),
    class = "zujson_write_error"
  )
})

test_that("a classed vector with the wrong storage type is a classed error", {
  # The kind was chosen from the class alone, so these reached R's checked
  # accessors and raised a bare simpleError (#43).
  expect_json(structure(NA, class = "Date"), "null")
  expect_json(structure(c(NA, NA), class = "Date"), "[null,null]")
  expect_json(structure(NA, class = c("POSIXct", "POSIXt")), "null")
  expect_json(
    structure(1L, class = c("POSIXct", "POSIXt")),
    '"1970-01-01T00:00:01Z"'
  )

  bad <- list(
    structure("x", class = "Date"),
    structure(TRUE, class = "Date"),
    structure(1i, class = "Date"),
    structure(list(1), class = "Date"),
    structure("x", class = c("POSIXct", "POSIXt")),
    structure(c(TRUE, NA), class = c("POSIXct", "POSIXt")),
    structure(1:2, levels = 1:2, class = "factor"),
    structure(1L, levels = list("a"), class = "factor"),
    structure(1L, class = "integer64"),
    structure(list(a = NULL), class = "data.frame"),
    structure(list(a = sum), class = "data.frame", row.names = 1L),
    structure(1:3, names = c("a", "b", "c"), class = "data.frame")
  )
  for (i in seq_along(bad)) {
    x <- bad[[i]]
    expect_error(
      json_write(x),
      class = "zujson_unsupported_type",
      info = paste("case", i)
    )
    expect_error(
      json_write(list(x)),
      class = "zujson_unsupported_type",
      info = paste("case", i)
    )
    expect_error(
      json_write_ndjson(list(x)),
      class = "zujson_unsupported_type",
      info = paste("case", i)
    )
  }

  # the same values as data frame columns, through both writers
  cols <- list(
    structure(c(NA, "x"), class = "Date"),
    structure(c(1L, 2L), levels = 1:2, class = "factor")
  )
  for (col in cols) {
    d <- structure(
      list(id = 1:2, v = col),
      class = "data.frame",
      row.names = 1:2
    )
    expect_error(json_write(d), class = "zujson_unsupported_type")
    expect_error(json_write_ndjson(d), class = "zujson_unsupported_type")
  }

  # a frame with no columns and no row.names is zero rows, not an error
  expect_json(
    structure(list(), names = character(0), class = "data.frame"),
    "[]"
  )
})

test_that("integer64 is written as the integers it holds", {
  # bit64 keeps the int64 bits in a double, so falling through to the double
  # wrote 1 as 5e-324 (#48). Built without bit64 by as_int64().
  x <- as_int64(c(1L, 2L, -1L, 0L, 0L), c(0L, 0L, -1L, 256L, 0L))
  expect_json(I(x), "[1,2,-1,1099511627776,0]")
  expect_json(as_int64(1L), "1")
  expect_json(as_int64(-1L, 2147483647L), "9223372036854775807")
  expect_json(as_int64(1L, NA_integer_), "-9223372036854775807")
  # INT64_MIN is bit64's NA
  expect_json(as_int64(c(5L, 0L), c(0L, NA)), "[5,null]")
  # as a column, an object member and an NDJSON record
  d <- data.frame(id = 1:2)
  d$big <- as_int64(c(0L, 1L), c(256L, 0L))
  expect_json(d, '[{"id":1,"big":1099511627776},{"id":2,"big":1}]')
  expect_identical(
    json_write_ndjson(d),
    '{"id":1,"big":1099511627776}\n{"id":2,"big":1}\n'
  )
  expect_json(list(n = as_int64(7L)), '{"n":7}')
})

test_that("a zero-row data frame is charged the one level it writes", {
  # It emits only the array, so charging it a row level as well refused JSON
  # json_parse() reads at the limit (#57).
  limit <- zujson_info()$max_depth
  df0 <- data.frame(a = integer(0))
  at <- json_write(wrap_list(df0, limit - 1L))
  expect_no_error(json_parse(at))
  expect_error(json_write(wrap_list(df0, limit)), class = "zujson_depth_error")
  # with rows it is still charged two
  df1 <- data.frame(a = 1L)
  expect_no_error(json_parse(json_write(wrap_list(df1, limit - 2L))))
  expect_error(
    json_write(wrap_list(df1, limit - 1L)),
    class = "zujson_depth_error"
  )
})

test_that("a string that cannot be converted to UTF-8 is refused, not rewritten", {
  # Bytes R's latin1 (CP1252) mapping leaves undefined came out as the text
  # "<81><8d>" in any locale, and an unmarked non-ASCII string under the C
  # locale as "caf<c3><a9>" (#42).
  x <- "\x81\x8d"
  Encoding(x) <- "latin1"
  expect_error(json_write(x), class = "zujson_write_error")
  expect_error(json_write(list(a = x)), class = "zujson_write_error")
  expect_error(json_write(stats::setNames(list(1), x)),
               class = "zujson_write_error")
  expect_error(json_write(factor(x)), class = "zujson_write_error")
  expect_error(json_write_ndjson(list(x)), class = "zujson_write_error")
  # every byte CP1252 does define still converts
  ok <- rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xe9, 0x80)))
  Encoding(ok) <- "latin1"
  expect_identical(json_write(ok), '"café€"')

  # The C locale is ASCII on Unix, which is the case this pins. Windows maps
  # it to a code page in which these bytes convert, so it is skipped there.
  skip_on_os("windows")
  cafe <- rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))
  withr::local_locale(c(LC_CTYPE = "C"))
  expect_error(json_write(cafe), class = "zujson_write_error")
  expect_error(json_write_raw(list(name = cafe)), class = "zujson_write_error")
  marked <- cafe
  Encoding(marked) <- "UTF-8"
  expect_identical(json_write_raw(marked), charToRaw('"café"'))
})
