#' Serialize R as JSON
#'
#' `json_write()` renders an R object as JSON text. `json_write_raw()` returns
#' the same JSON as UTF-8 bytes, which is the form an HTTP request body wants.
#'
#' # Type mapping
#'
#' | R | JSON |
#' | --- | --- |
#' | `NULL` | `null` |
#' | `NA`, `NaN`, `Inf` | `null` |
#' | `list(a = 1, b = 2)` | `{"a":1,"b":2}` |
#' | `list(1, 2)` | `[1,2]` |
#' | `c(a = 1, b = 2)` | `{"a":1,"b":2}` |
#' | `1:3` | `[1,2,3]` |
#' | `"a"` | `"a"` (see `auto_unbox`) |
#' | `I("a")` | `["a"]` |
#' | `factor` | its level, as a string |
#' | `Date` | `"YYYY-MM-DD"` |
#' | `POSIXct` | `"YYYY-MM-DDTHH:MM:SSZ"`, in UTC |
#' | `data.frame` | array of one object per row |
#' | `list()` | `[]` |
#' | `structure(list(), names = character())` | `{}` |
#'
#' A vector or list becomes a JSON **object** when every element is named, and
#' an **array** otherwise. Partial names would produce keys like `""`, which is
#' valid JSON but almost never intended, so a partially named vector is written
#' as an array and its names are dropped.
#'
#' Data frames are written row-oriented, because that is what an HTTP API means
#' by a table. To get the column-oriented form instead, strip the class first:
#' `json_write(as.list(df))`.
#'
#' Every kind of missing value becomes `null`: JSON has no `NA`, and `NaN` and
#' `Infinity` are not JSON either. `POSIXct` is always written as UTC no matter
#' what its `tzone` says, since it is the same instant either way, and
#' sub-second parts are dropped.
#'
#' Doubles are written with the shortest representation that reads back
#' identically, so `0.1` is `0.1` rather than `0.10000000000000001`.
#'
#' Complex vectors, raw vectors, functions and environments have no sensible
#' JSON form and raise a `zujson_unsupported_type` error rather than being
#' guessed at. A vector carrying an unrecognised class is written as its
#' underlying type.
#'
#' @param x The R object to serialize.
#' @param pretty Whether to indent the output. `FALSE` (the default) writes the
#'   compact form, which is what you want for a request body.
#' @param auto_unbox Whether a length-1 atomic vector becomes a bare JSON
#'   scalar (`TRUE`, the default) or a one-element array. Wrap a value in
#'   [I()] to keep it an array under `auto_unbox = TRUE`; that is the escape
#'   hatch for an API field that must always be a list.
#'
#' @return `json_write()` returns a single string; `json_write_raw()` returns a
#'   raw vector of UTF-8 bytes.
#' @seealso [json_parse()] for the other direction.
#' @export
#'
#' @examples
#' json_write(list(name = "ada", ids = 1:3, ok = TRUE))
#'
#' # length-1 vectors unbox by default; I() keeps them arrays
#' json_write(list(tag = "x", tags = I("x")))
#'
#' # every atomic vector stays an array
#' json_write(list(tag = "x"), auto_unbox = FALSE)
#'
#' cat(json_write(list(a = 1, b = list(c = 2)), pretty = TRUE))
#'
#' json_write(data.frame(id = 1:2, nm = c("a", "b")))
json_write <- function(x, pretty = FALSE, auto_unbox = TRUE) {
  .Call(C_zujson_write, x,
        zu_check_flag(pretty, "pretty"),
        zu_check_flag(auto_unbox, "auto_unbox"),
        FALSE)
}

#' @rdname json_write
#' @export
#' @examples
#'
#' # bytes, ready to be an HTTP request body
#' json_write_raw(list(q = "search"))
json_write_raw <- function(x, pretty = FALSE, auto_unbox = TRUE) {
  .Call(C_zujson_write, x,
        zu_check_flag(pretty, "pretty"),
        zu_check_flag(auto_unbox, "auto_unbox"),
        TRUE)
}
