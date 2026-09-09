# Helpers for test-fuzz.R.
#
# These live in a helper file rather than at the top of the test file because
# `shuffle = TRUE` reorders *every* top-level expression in a test file, plain
# assignments included, so a file-scope object is not guaranteed to exist by the
# time a test needs it. Helper files are sourced whole before any test runs.

# Iteration count, kept small by default so the fuzzing costs little on every
# run; ZUJSON_FUZZ raises it for the scheduled CI job. `max` caps the count for
# the slower tests, which do real work per iteration.
fuzz_iters <- function(max = Inf) {
  n <- suppressWarnings(as.integer(Sys.getenv("ZUJSON_FUZZ", "300")))
  if (is.na(n) || n < 1L) n <- 300L
  as.integer(min(n, max))
}

# Every parse must land in exactly one of these two outcomes.
outcome <- function(expr) {
  tryCatch({ force(expr); "value" },
           zujson_error = function(e) "condition",
           error = function(e) paste0("BARE ERROR: ", conditionMessage(e)),
           warning = function(w) paste0("WARNING: ", conditionMessage(w)))
}

random_bytes <- function(n) {
  paste(rawToChar(as.raw(sample(c(32:126, 9L, 10L, 13L), n, replace = TRUE))),
        collapse = "")
}

# Bytes drawn from JSON's own alphabet find structural bugs that uniform random
# text never reaches: it almost never produces a balanced brace.
json_soup <- function(n) {
  alphabet <- c("{", "}", "[", "]", ":", ",", '"', "\\", "/", "-", "+", ".",
                "e", "E", "0", "1", "9", "t", "r", "u", "e", "f", "a", "l",
                "s", "n", "i", " ", "\t", "\n", "é", "\\u0000", "\\ud800")
  paste(sample(alphabet, n, replace = TRUE), collapse = "")
}
