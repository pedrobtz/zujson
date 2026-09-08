#' Parse JSON into R
#'
#' `json_parse()` turns JSON text, or the raw bytes of an HTTP response body,
#' into ordinary R vectors and lists. `json_parse_raw()` and
#' `json_parse_file()` are the same parser reached directly, for when the input
#' type is already known.
#'
#' # Type mapping
#'
#' JSON objects always become named lists. JSON arrays become an atomic vector
#' when every element agrees on a type and a list otherwise:
#'
#' | JSON | R |
#' | --- | --- |
#' | `{"a": 1}` | named `list` |
#' | `[1, 2, 3]` | `integer` |
#' | `[1, 2.5]` | `double` |
#' | `[true, false]` | `logical` |
#' | `["a", "b"]` | `character` |
#' | `[1, "a"]` | `list` (no common type without coercing) |
#' | `[1, {}]` | `list` (nested container) |
#' | `[]`, `[null, null]` | `logical` |
#' | `null` | `NULL` |
#'
#' Numbers become `integer` when they fit in R's 32-bit integer and `double`
#' otherwise. A `null` inside an array being simplified becomes `NA`; a `null`
#' anywhere else becomes `NULL`. Strings arrive as UTF-8.
#'
# Simplification modes
#'
#' `simplify` picks what happens to an array whose elements do not share a
#' kind. The three modes agree everywhere else, including the promotions
#' *within* the numeric family (`[true, 1]` is `c(1L, 1L)` in all of them):
#'
#' | mode | `[1, "a"]` becomes |
#' | --- | --- |
#' | `"preserve"`, or `TRUE` (default) | `list(1L, "a")` |
#' | `"coerce"` | `c("1", "a")` |
#' | `"none"`, or `FALSE` | `list(1L, "a")`, and every other array is a list too |
#'
#' `preserve` keeps the type and gives up the uniform shape, on the view that a
#' field which is usually a number and occasionally a string is a bug worth
#' seeing. `coerce` is the opt-in for callers who would rather have the vector:
#' it follows R's own promotion, so the strings are exactly what
#' `as.character()` produces. A nested object or array is never coerced away.
#'
#' # Data frames
#'
#' `data_frame = TRUE` turns any non-empty array whose elements are *all*
#' objects into a data frame. Columns are the union of the keys in the order
#' first seen; a record missing a key contributes `NA`, so the result is
#' rectangular however ragged the records are. Each column is then simplified
#' with the active `simplify` mode, so a column of mixed kinds is a list column
#' under `preserve` and a character column under `coerce`. It applies wherever
#' such an array appears, however deeply nested.
#'
#' Nesting deeper than 1000 levels is rejected with a `zujson_depth_error`,
#' which is what makes the parser safe to point at an untrusted response body.
#'
#' A leading UTF-8 byte order mark is ignored rather than rejected: RFC 8259
#' forbids emitting one but allows ignoring it, and real APIs emit them.
#'
#' Two things that are valid JSON still cannot become R values, and both raise
#' `zujson_parse_error` rather than a bare error: a string or key containing an
#' escaped NUL (`\u0000`), which no R string can hold, and one longer than
#' `.Machine$integer.max` bytes. `json_parse_file()` additionally raises
#' `zujson_io_error` when the file cannot be read at all, which is a different
#' problem from its contents not being JSON.
#'
#' @param x For `json_parse()`, a single string of JSON text or a raw vector of
#'   UTF-8 JSON bytes. For `json_parse_raw()`, a raw vector.
#' @param path Path to a file containing JSON.
#' @param simplify How to simplify JSON arrays to atomic vectors: one of
#'   `"preserve"` (the default), `"coerce"` or `"none"`. `TRUE` and `FALSE` are
#'   accepted as synonyms for `"preserve"` and `"none"`. See *Simplification
#'   modes* below.
#' @param data_frame Whether an array of objects becomes a data frame. `FALSE`
#'   by default, in which case it stays a list of named lists. See *Data
#'   frames* below.
#'
#' @return The parsed R object.
#' @seealso [json_write()] for the other direction, [json_validate()] to check
#'   without building a result.
#' @export
#'
#' @examples
#' json_parse('{"ok": true, "ids": [1, 2, 3]}')
#'
#' # arrays that have no common type stay lists
#' json_parse('[1, "a"]')
#'
#' # raw bytes, as an HTTP response body arrives
#' json_parse(charToRaw('{"ok": true}'))
#'
#' # no simplification at all
#' json_parse('[1, 2, 3]', simplify = FALSE)
#'
#' # coerce across kinds instead of keeping the type
#' json_parse('[1, "a"]', simplify = "coerce")
#'
#' # an array of records, as a data frame
#' json_parse('[{"id":1,"nm":"a"},{"id":2,"nm":"b"}]', data_frame = TRUE)
json_parse <- function(x, simplify = TRUE, data_frame = FALSE) {
  simplify <- zu_check_simplify(simplify)
  data_frame <- zu_check_flag(data_frame, "data_frame")
  if (is.raw(x)) {
    return(.Call(C_zujson_parse_raw, x, simplify, data_frame))
  }
  x <- zu_check_string(x, "x")
  .Call(C_zujson_parse_str, x, simplify, data_frame)
}

#' @rdname json_parse
#' @export
#' @examples
#'
#' json_parse_raw(charToRaw('[1, 2, 3]'))
json_parse_raw <- function(x, simplify = TRUE, data_frame = FALSE) {
  if (!is.raw(x)) {
    zu_abort("zujson_arg_error", "`x` must be a raw vector.")
  }
  .Call(C_zujson_parse_raw, x, zu_check_simplify(simplify),
        zu_check_flag(data_frame, "data_frame"))
}

#' @rdname json_parse
#' @export
#' @examples
#'
#' path <- tempfile(fileext = ".json")
#' writeLines('{"a": [1, 2]}', path)
#' json_parse_file(path)
#' unlink(path)
json_parse_file <- function(path, simplify = TRUE, data_frame = FALSE) {
  path <- zu_check_string(path, "path")
  # Expand here rather than let the C fopen() see a literal "~": file.exists()
  # expands it and fopen() does not, so without this a readable file reports
  # itself as unreadable.
  path <- path.expand(path)
  if (!file.exists(path)) {
    zu_abort("zujson_arg_error", paste0("File '", path, "' does not exist."))
  }
  .Call(C_zujson_parse_file, path, zu_check_simplify(simplify),
        zu_check_flag(data_frame, "data_frame"))
}

#' Check whether input is valid JSON
#'
#' Parses `x` and reports whether it succeeded, without building an R result
#' and without raising a condition. Use it to decide whether a response body is
#' worth parsing; use [json_parse()] when a failure should be an error you can
#' read.
#'
#' This answers "is this valid JSON", which is very nearly but not exactly "will
#' [json_parse()] succeed". The one input where they differ is a string or key
#' containing an escaped NUL (`\u0000`): that is valid JSON, so this returns
#' `TRUE`, but no R string can hold the result, so `json_parse()` raises
#' `zujson_parse_error`. Code that must not fail should handle the condition
#' from `json_parse()` rather than pre-screening with this.
#'
#' @param x A single string of JSON text, or a raw vector of JSON bytes.
#' @return `TRUE` or `FALSE`.
#' @export
#'
#' @examples
#' json_validate('{"a": 1}')
#' json_validate('{"a": }')
#' json_validate(charToRaw("[]"))
json_validate <- function(x) {
  if (is.raw(x)) {
    return(.Call(C_zujson_validate_raw, x))
  }
  if (!is.character(x) || length(x) != 1L) {
    zu_abort("zujson_arg_error",
             "`x` must be a single string or a raw vector.")
  }
  .Call(C_zujson_validate_str, x)
}
