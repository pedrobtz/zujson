# zujson 0.0.0.9000 (development version)

Nothing has been released yet, so everything below is unreleased, newest work
first. The mappings may still change if the design argues for it.

## Bug fixes

* A number too large for any finite `double` now parses as `Inf` instead of
  failing the whole read. RFC 8259 puts no limit on the magnitude of a number,
  so `1e309` is valid JSON, and rejecting it let one absurd value anywhere in
  a response body make the entire body unparseable. The value is the one
  `as.numeric()` gives the same token, so an integer wider than `int64` reads
  as the nearest double. `json_validate("1e309")` is `TRUE` for the same
  reason. The bare literals `Infinity`, `-Infinity` and `NaN` are not JSON and
  are still rejected.

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

* Differential tests against `jsonlite`, in `tests/testthat/test-interop-jsonlite.R`.
  Two tables over JSON text: where the two packages agree, and a divergence
  table pinning the places they are meant not to — `[]` is `logical(0)`,
  `preserve` keeps `[1, "a"]` a list, there is no matrix detection, and data
  frames are opt-in. The second table is the useful one: it fails if a change
  quietly makes this package more `jsonlite`-like than the documented mapping
  says. `jsonlite` is a suggested package and the tests skip without it.

* Conformance against `nst/JSONTestSuite`, in `tools/jsontestsuite.R`. Every
  file is handed to `json_validate()` as raw bytes — the suite is full of
  deliberately invalid UTF-8 and embedded NULs, which a text read would mangle.
  The package accepts all 95 files it must accept and rejects all 188 it must
  reject; of the 35 implementation-defined files it accepts 12, the rejections
  being invalid UTF-8 and lone surrogates. The script pins an upstream commit
  so the result cannot drift under it, and needs the network only once.

* Sanitizer and randomised-input CI. `tools/sanitizer-exercise.R` drives the C
  layer using nothing but base R, with most of its effort on the error paths,
  where an R error longjmps past the explicit free; `hardening.yaml` runs it
  under clang-asan, clang-ubsan and gcc-asan, and fuzzes the parser separately.
  `tests/testthat/test-fuzz.R` runs a smaller version of the same idea on every
  test run.

## Initial feature set

The v1 work, previously labelled 0.1.0 — a version number, not a release.

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
