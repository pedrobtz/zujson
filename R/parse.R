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
#' Simplification never coerces across kinds: `[1, "a"]` stays a list rather
#' than becoming `c("1", "a")`, so a value's type survives the round trip. Set
#' `simplify = FALSE` to get a list for every array regardless.
#'
#' Arrays of objects are *not* turned into data frames. Nesting deeper than
#' 1000 levels is rejected with a `zujson_depth_error`, which is what makes the
#' parser safe to point at an untrusted response body.
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
#' @param simplify Whether to simplify JSON arrays to atomic vectors. `TRUE`
#'   (the default) applies the table above; `FALSE` makes every array a list.
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
json_parse <- function(x, simplify = TRUE) {
  simplify <- zu_check_flag(simplify, "simplify")
  if (is.raw(x)) {
    return(.Call(C_zujson_parse_raw, x, simplify))
  }
  x <- zu_check_string(x, "x")
  .Call(C_zujson_parse_str, x, simplify)
}

#' @rdname json_parse
#' @export
#' @examples
#'
#' json_parse_raw(charToRaw('[1, 2, 3]'))
json_parse_raw <- function(x, simplify = TRUE) {
  if (!is.raw(x)) {
    zu_abort("zujson_arg_error", "`x` must be a raw vector.")
  }
  .Call(C_zujson_parse_raw, x, zu_check_flag(simplify, "simplify"))
}

#' @rdname json_parse
#' @export
#' @examples
#'
#' path <- tempfile(fileext = ".json")
#' writeLines('{"a": [1, 2]}', path)
#' json_parse_file(path)
#' unlink(path)
json_parse_file <- function(path, simplify = TRUE) {
  path <- zu_check_string(path, "path")
  # Expand here rather than let the C fopen() see a literal "~": file.exists()
  # expands it and fopen() does not, so without this a readable file reports
  # itself as unreadable.
  path <- path.expand(path)
  if (!file.exists(path)) {
    zu_abort("zujson_arg_error", paste0("File '", path, "' does not exist."))
  }
  .Call(C_zujson_parse_file, path, zu_check_flag(simplify, "simplify"))
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
