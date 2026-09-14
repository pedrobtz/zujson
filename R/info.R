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
  info <- zu_build_info()
  # max_xlen is the ceiling zu_df_cells() clamps the option to, which is an
  # internal detail of how the budget is carried into C, not a limit a caller
  # has to reason about
  info$max_xlen <- NULL
  # the limit in force, not the compiled-in default, since the option can
  # change it -- and the clamped value, since that is what will be enforced
  info$max_df_cells <- zu_df_cells()
  c(list(zujson = as.character(utils::packageVersion("zujson"))), info)
}
