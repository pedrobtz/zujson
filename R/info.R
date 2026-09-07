#' Report what this build of zujson contains
#'
#' Returns the package version, the version of the vendored yyjson sources it
#' was compiled against, and the nesting depth limit the parser and serializer
#' both enforce.
#'
#' @return A named list with `zujson`, `yyjson` and `max_depth`.
#' @export
#'
#' @examples
#' zujson_info()
zujson_info <- function() {
  # yyjson and max_depth come from the compiled object rather than being
  # restated here, so there is only ever one copy of either.
  c(list(zujson = as.character(utils::packageVersion("zujson"))),
    .Call(C_zujson_build_info))
}
