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

# Simplification mode, as an integer the C layer switches on.
#
# `simplify` began as a flag and grew a third state, so both spellings have to
# keep working: TRUE and FALSE are the original API and stay exact synonyms for
# "preserve" and "none". The strings exist because "coerce" needs a name, and a
# named mode reads better at a call site than a bare TRUE ever did.
ZU_SIMPLIFY <- c(none = 0L, preserve = 1L, coerce = 2L)

zu_check_simplify <- function(x, arg = "simplify") {
  if (is.logical(x) && length(x) == 1L && !is.na(x)) {
    return(if (x) ZU_SIMPLIFY[["preserve"]] else ZU_SIMPLIFY[["none"]])
  }
  if (is.character(x) && length(x) == 1L && !is.na(x) &&
        x %in% names(ZU_SIMPLIFY)) {
    return(ZU_SIMPLIFY[[x]])
  }
  zu_abort(
    "zujson_arg_error",
    paste0("`", arg, "` must be TRUE, FALSE, ",
           '"preserve", "coerce" or "none".')
  )
}
