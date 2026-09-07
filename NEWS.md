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
* `zujson_info()` reports the package version, the vendored yyjson version and
  the nesting limit.
* Every failure raises a condition inheriting from `zujson_error`.
* yyjson 0.12.0 is vendored under `src/vendor/yyjson`; no system library is
  needed.
