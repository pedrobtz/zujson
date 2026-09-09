# zujson (development version)

## Bug fixes

* `json_parse_file()` on a directory now raises `zujson_io_error` on every
  platform. It already did on macOS and Windows, where `fopen()` refuses a
  directory; on Linux `fopen()` succeeds, so yyjson failed later with a memory
  allocation error and the call raised `zujson_parse_error` instead. The path
  is a directory either way, which is an io problem, not a malformed document.

## Parsing

* `simplify` gains named modes. `"preserve"` (the default, and what `TRUE`
  has always meant) keeps a mixed-kind array as a list; `"coerce"` promotes it
  to a character vector following R's own rules, so `[1, "a"]` becomes
  `c("1", "a")` and a JSON `null` becomes `NA` rather than the string `"NA"`.
  `"none"` is `FALSE`. `TRUE` and `FALSE` keep working and mean exactly what
  they did, so nothing written against the old API changes meaning.

* `data_frame = TRUE` turns a non-empty array whose elements are all objects
  into a data frame, wherever one appears. Columns are the union of the keys
  in first-seen order and a missing key reads as `NA`, so ragged records still
  give a rectangular result. Columns simplify with the active `simplify` mode.
  Off by default: the documented type mapping is unchanged unless you ask.

## Infrastructure

* Sanitizer and randomised-input CI. `tools/sanitizer-exercise.R` drives the C
  layer using nothing but base R, with most of its effort on the error paths,
  where an R error longjmps past the explicit free; `hardening.yaml` runs it
  under clang-asan, clang-ubsan and gcc-asan, and fuzzes the parser separately.
  `tests/testthat/test-fuzz.R` runs a smaller version of the same idea on every
  test run.

# zujson 0.1.0

First release.

* `json_parse()`, `json_parse_raw()` and `json_parse_file()` turn JSON into R
  vectors and lists. Arrays simplify to atomic vectors only when their elements
  share a type, so a value's type survives the round trip; `simplify = FALSE`
  turns simplification off entirely.
* `json_write()` and `json_write_raw()` serialize R as JSON text or as UTF-8
  bytes. A fully named vector or list becomes an object, anything else becomes
  an array, and length-1 atomic vectors unbox unless wrapped in `I()`.
* `json_validate()` reports whether input parses, without building a result.
* `json_parse_ndjson()`, `json_write_ndjson()` and `json_write_ndjson_raw()`
  handle `application/x-ndjson` (JSON Lines): one JSON value per line, parsed
  and written with the same type mappings as single documents. Parsing always
  returns a list of records and reports the line number on failure; a data
  frame writes one object per row. There is no `pretty` option, because
  indented JSON contains newlines and would break the framing.
* `zujson_info()` reports the package version, the vendored yyjson version and
  the nesting limit.
* Every failure raises a condition inheriting from `zujson_error`:
  `zujson_parse_error`, `zujson_write_error`, `zujson_unsupported_type`,
  `zujson_depth_error`, `zujson_io_error` and `zujson_arg_error`.
* A leading UTF-8 byte order mark is ignored rather than rejected, and a
  `POSIXlt` is refused rather than serialized as its 11 internal fields.
* yyjson 0.12.0 is vendored under `src/vendor/yyjson`; no system library is
  needed.
