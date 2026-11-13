# zujson 0.1.1

## Bug fixes

* A `POSIXlt` data frame column, and a `POSIXlt` passed to
  `json_write_ndjson()`, now raise `zujson_unsupported_type`. Both used to
  skip the check and write the 11 broken-down time fields as data: in an
  11-row frame, row *i* became field *i* (#40).

* A `POSIXct` a fraction of a second before midnight is written as
  `23:59:59`. Floating-point rounding could print hour `24` instead, as in
  `"1969-12-31T24:00:00Z"`, which no RFC 3339 parser accepts (#41).

* A classed vector whose storage the class cannot mean -- a `Date` stored as
  character, a factor with integer levels, a data frame that is not a list of
  vector columns -- raises `zujson_unsupported_type` instead of a bare R error
  that escaped the `zujson_error` contract. An all-`NA` logical `Date` or
  `POSIXct`, such as `structure(NA, class = "Date")`, is written as `null`
  (#43).

* A zero-row data frame is charged one nesting level, for the `[]` it writes,
  not two. It used to be refused at a depth `json_parse()` reads back (#57).

* `data_frame = TRUE` no longer slows to quadratic time on keys chosen to
  collide in its index. The key hash is now seeded per call and fully mixed;
  2^15 colliding keys took 5.7 s, against 0.014 s for ordinary ones, and could
  not be interrupted until the end (#44).

* An integer too wide for 64 bits parses to the nearest `double`. About 1 in
  1000 came back one unit in the last place off, and differently from the same
  number written with `.0` (#46).

* Every `json_parse_ndjson()` error names its line, including those raised
  while building a record: an embedded NUL, nesting too deep, a duplicate key
  in a data frame record, the cell limit (#54).

* Condition messages are valid UTF-8 and marked as such. A long non-ASCII key
  or column name could be cut mid-character (#53).

* `zujson_info()$max_df_cells` reports a fractional option as the whole number
  of cells the parser enforces (#55).

* A body built by `json_write_ndjson()` past 2^31 - 1 bytes raises
  `zujson_write_error`, pointing to `json_write_ndjson_raw()`, instead of a
  bare error from `paste()`. `json_write_ndjson_raw()` builds its bytes
  directly rather than from that string, so it has no such ceiling (#47).

* `json_parse_file()` reads a file with a non-ASCII name in any locale. It
  now reads the bytes in R and parses them by the raw route; the C layer used
  to open a translated copy of the path, which under the C locale named a
  file that does not exist (#50).

* The native memory behind a parse or a write can no longer leak if R fails
  an allocation at the moment it is handed to R. The external pointer that
  owns it is now made before the memory exists (#52).

## Behaviour changes

* A string that is not valid in the encoding it declares raises
  `zujson_parse_error` in `json_parse()` and `json_parse_ndjson()`, and
  `zujson_write_error` in the writers, and `json_validate()` returns `FALSE`
  for it. R's conversion used to rewrite such bytes as text, so a body read
  with `readLines()` under the C locale came back as `"caf<c3><a9>"`, and
  `"<81>"` was sent for a latin1 byte with no character (#42).
* `bit64::integer64` vectors are written as the 64-bit integers they hold,
  with `NA` as `null`. They used to fall through to their storage type and be
  written as the doubles their bits spell, so `1` went out as `5e-324` (#48).

* The data frame cell limit, `zujson_info()$max_df_cells`, now bounds the
  whole document rather than each frame in it, as `?json_parse` describes it.
  Many frames each under the limit used to be accepted together, however far
  past it their total went (#45).

* `json_parse_ndjson()` accepts a UTF-8 byte order mark only at the start of
  the body, and a body that is only a BOM is empty. A BOM at the start of any
  later line was accepted, and a BOM-only first line was an error (#56).
||||||| a962bb7

# zujson 0.1.0

First release. Everything below is the work that went into it, newest first.

## Bug fixes

* A data frame's row objects are now charged a nesting level in both
  directions. Parsing, they were not charged at all, so a document one level
  too deep to parse as a list parsed as a frame; writing, a list column was
  charged twice, so a frame whose JSON sat exactly at the 1000-level limit was
  rejected. `zujson_info()$max_depth` now means the same thing whichever
  options are passed.

* `Date` and `POSIXct` outside `0000-01-01` to `9999-12-31` now raise
  `zujson_write_error`. Both are doubles in R, so they reach far past what a
  timestamp can be written as: `1e300` produced
  `"2030437271-06-06T-596523:-14:-8Z"`, and converting it to `int64_t` on the
  way was undefined behaviour rather than merely wrong.

* A string whose `Encoding()` is `"bytes"` now raises `zujson_arg_error` when
  parsing and `zujson_write_error` when writing, instead of the bare
  `simpleError` that `Rf_translateCharUTF8()` raises from inside R. Everything
  this package can fail with is a `zujson_error` again. Pass the bytes as a
  raw vector, which is what the raw path is for.

* `data_frame = TRUE` no longer drops a value when one record carries the same
  key twice. It raises `zujson_parse_error`: a column has one cell per record,
  and plain parsing keeps both values, so quietly keeping one made an option
  about *shape* change *content*.

## Data frames

* Building a frame is now linear in the length of the input rather than
  quadratic in the number of distinct keys. The union of the keys is collected
  through a hash index instead of a scan of the keys so far, and cells are
  filled by one pass over the records instead of a lookup per cell that
  rescanned the record. A 4000 x 2000 frame went from 69s to 1.6s.

* The size of a frame is now capped. Because the result is rectangular, its
  size is set by the union of the keys and not by how much JSON arrived: 5000
  records sharing no keys is a 5000 x 5000 frame — 96 MB — from 72 kB of body,
  which is a denial-of-service path for a package meant to be pointed at
  untrusted bodies. A limit on the body cannot stand in for one here, because
  the growth is quadratic in it. More than `zujson_info()$max_df_cells` cells
  now raises `zujson_limit_error`, as the offending column appears rather than
  after the allocation.

  The default is 50 million cells, roughly 400 MB of doubles, plus the same
  order again for the pointer matrix the records are scattered through — 100k
  rows by 200 columns is 20 million, so a real tabular response has room to
  spare. `options(zujson.max_df_cells = )` changes it for the session, and
  `zujson_info()$max_df_cells` reports the limit actually in force. Setting it
  larger than any frame that could be built switches the check off, at the
  price that an oversized body then raises R's own allocation error rather than
  a `zujson_limit_error`.

* `simplify = "none"` takes precedence over `data_frame = TRUE`, and says so.
  That mode's promise is that every JSON array arrives as an R list; the two
  options are not combined.

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
