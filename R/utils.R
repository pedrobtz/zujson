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
  zu_check_bytes(x, arg)
}

# "bytes" is R saying it does not know the string's encoding, and the C layer
# reaches such a string only through Rf_translateCharUTF8(), which answers with
# a bare simpleError raised inside R itself -- outside the zujson_error
# contract. Refusing it here keeps every failure this package can produce a
# zujson_error, which is what a caller handling `zujson_error` once relies on.
# Pass the raw vector instead: bytes are exactly what the raw path takes.
zu_check_bytes <- function(x, arg) {
  if (any(Encoding(x) == "bytes")) {
    zu_abort("zujson_arg_error",
             paste0("`", arg, "` is marked \"bytes\", an unknown encoding. ",
                    "Pass the bytes as a raw vector instead."))
  }
  x
}

# `data_frame`, as the number the C layer threads through the recursion: 0 is
# off, and anything else is the cell budget for the call.
#
# The budget is resolved here rather than in C so that the option is checked
# where every other argument is, and so that C never has to decide what a
# malformed option means. The compiled-in default is read once and cached: it
# is the only copy of the number, so R and C cannot drift.
zu_cache <- new.env(parent = emptyenv())

# The compiled-in constants, read once: they cannot change within a session,
# and zu_df_cells() runs on every `data_frame = TRUE` parse.
zu_build_info <- function() {
  if (is.null(zu_cache$info)) zu_cache$info <- .Call(C_zujson_build_info)
  zu_cache$info
}

zu_df_cells <- function() {
  n <- getOption("zujson.max_df_cells")
  if (is.null(n)) return(zu_build_info()$max_df_cells)
  # Inf is not how the limit is switched off. A number larger than any frame
  # that could be built is, and it says the same thing without asking C to
  # convert something no integer type has a value for.
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || !is.finite(n) || n < 1) {
    zu_abort("zujson_arg_error",
             paste0("`options(zujson.max_df_cells = )` must be a single ",
                    "finite number of 1 or more."))
  }
  # Clamped to what an R_xlen_t holds, since the cast in C is undefined past
  # that -- and clamped *here*, so that the number zujson_info() reports is the
  # number the parser enforces rather than the one that was asked for. The
  # ceiling comes from the compiled object because R_xlen_t is int on a build
  # without long vectors, where a literal 2^52 would be wrong.
  min(as.double(n), zu_build_info()$max_xlen)
}

zu_check_df <- function(x, arg = "data_frame") {
  if (zu_check_flag(x, arg)) zu_df_cells() else 0
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
