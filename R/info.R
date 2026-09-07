#' Report what this build of zujson contains
#'
#' Returns the package version, the version of the vendored yyjson sources it
#' was compiled against, and the nesting depth limit the parser and serializer
#' both enforce.
#'
#' @return A named list.
#' @export
#'
#' @examples
#' zujson_info()
zujson_info <- function() {
  list(
    zujson = as.character(utils::packageVersion("zujson")),
    yyjson = .Call(C_zujson_yyjson_version),
    max_depth = 1000L
  )
}
