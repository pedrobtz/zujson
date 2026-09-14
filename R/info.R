#' Report what this build of zujson contains
#'
#' Returns the package version, the version of the vendored yyjson sources it
#' was compiled against, and the nesting depth limit the parser and serializer
#' both enforce.
#'
#' @return A named list with `zujson`, `yyjson`, `max_depth` and
#'   `max_df_cells`. `max_depth` is compiled in and fixed; `max_df_cells` is
#'   the limit in force, which `options(zujson.max_df_cells = )` changes.
#' @export
#'
#' @examples
#' zujson_info()
zujson_info <- function() {
  # Everything but the package version comes from the compiled object rather
  # than being restated here, so there is only ever one copy of each.
  info <- .Call(C_zujson_build_info)
  # the limit in force, not the compiled-in default, since the option can
  # change it and a caller asking is asking what will happen
  info$max_df_cells <- zu_df_cells()
  c(list(zujson = as.character(utils::packageVersion("zujson"))), info)
}
