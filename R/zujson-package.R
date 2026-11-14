#' @section Scope:
#' zujson is the JSON an HTTP client needs: one document, or one NDJSON body,
#' in memory, to and from ordinary R vectors and lists. It leaves out, on
#' purpose:
#'
#' * matrix and N-d array simplification: a JSON array of arrays stays a list,
#'   and a matrix is written as its values in column-major order;
#' * incremental streaming of a document that does not fit in memory;
#' * JSON Pointer, JSON Patch and schema validation;
#' * custom serializers for classes the type mapping does not name.
#'
#' Data frame reconstruction is opt-in, through `data_frame = TRUE`, so that
#' the default mapping documented in [json_parse()] is what you get unless you
#' ask for something else. Use jsonlite when you need one of the above.
#'
#' @seealso
#' The other packages of the `zu*` family:
#' [zukomp](https://github.com/pedrobtz/zukomp) for compression,
#' [zuxml](https://github.com/pedrobtz/zuxml) for XML,
#' [zuyaml](https://github.com/pedrobtz/zuyaml) for YAML, and zuhttp, the HTTP
#' client that uses them.
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @useDynLib zujson, .registration = TRUE, .fixes = "C_"
## usethis namespace: end
NULL
