# Argument checks raise the same structured conditions the C layer does, so a
# caller can handle `zujson_error` once and catch everything the package
# throws, whichever side of the boundary it came from.
zu_abort <- function(class, message) {
  stop(structure(
    class = c(class, "zujson_error", "error", "condition"),
    list(message = message, call = NULL)
  ))
}

zu_check_flag <- function(x, arg) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    zu_abort("zujson_arg_error",
             paste0("`", arg, "` must be TRUE or FALSE."))
  }
  x
}

zu_check_string <- function(x, arg) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    zu_abort("zujson_arg_error",
             paste0("`", arg, "` must be a single string."))
  }
  x
}
