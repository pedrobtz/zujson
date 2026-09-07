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
