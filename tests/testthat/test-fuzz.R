# Randomised input, on the principle that hand-written cases only cover what
# the author thought of.
#
# The contract being checked is narrow and absolute: for *any* input, parsing
# either returns an R value or raises a `zujson_error`. It never segfaults,
# never returns a corrupt object, and never lets a bare R error escape --- a
# bare error would mean some path bypassed the structured-condition contract
# that callers handle on.
#
# Kept small by default so it costs little on every run; ZUJSON_FUZZ raises the
# iteration count for the scheduled CI job.

n_iter <- {
  n <- suppressWarnings(as.integer(Sys.getenv("ZUJSON_FUZZ", "300")))
  if (is.na(n) || n < 1L) 300L else n
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

test_that("random bytes never crash and never escape the condition contract", {
  set.seed(20260908)
  bad <- character()

  for (i in seq_len(n_iter)) {
    src <- if (i %% 2L == 0L) random_bytes(sample(60L, 1L))
           else json_soup(sample(60L, 1L))
    mode <- sample(list(TRUE, FALSE, "coerce"), 1L)[[1]]
    df <- sample(c(TRUE, FALSE), 1L)

    got <- outcome(json_parse(src, simplify = mode, data_frame = df))
    if (!got %in% c("value", "condition")) {
      bad <- c(bad, sprintf("%s on %s", got, encodeString(src)))
    }

    # json_validate() must answer for the same input without raising at all.
    v <- tryCatch(json_validate(src), error = function(e) e)
    if (!is.logical(v) || length(v) != 1L || is.na(v)) {
      bad <- c(bad, sprintf("validate did not answer for %s", encodeString(src)))
    }
  }

  expect_identical(bad, character(), info = paste(head(bad, 5), collapse = "\n"))
})

test_that("raw and character input agree on every random input", {
  set.seed(1L)
  for (i in seq_len(min(n_iter, 200L))) {
    src <- json_soup(sample(40L, 1L))
    # Only ASCII here: the two paths legitimately differ on how a native-encoded
    # string is transcoded, which is not what this is testing.
    if (grepl("[^ -~\t\n]", src)) next
    expect_identical(json_validate(src), json_validate(charToRaw(src)),
                     info = encodeString(src))
  }
})

test_that("valid JSON built at random survives a round trip", {
  set.seed(42L)

  gen <- function(depth) {
    if (depth > 3L) return(sample(list(1L, 2.5, TRUE, "s", NULL), 1L)[[1]])
    switch(sample(3L, 1L),
      sample(list(1L, -7L, 2.5, TRUE, FALSE, "text", "", NULL), 1L)[[1]],
      lapply(seq_len(sample(0:4, 1L)), function(i) gen(depth + 1L)),
      {
        n <- sample(1:4, 1L)
        stats::setNames(lapply(seq_len(n), function(i) gen(depth + 1L)),
                        paste0("k", seq_len(n)))
      }
    )
  }

  for (i in seq_len(min(n_iter, 200L))) {
    x <- gen(1L)
    txt <- tryCatch(json_write(x), zujson_error = function(e) NULL)
    if (is.null(txt)) next
    # What is asserted is that the output re-parses, not that it equals `x`:
    # the type mapping is documented as lossy in specific places (a named list
    # of one element unboxes, NULL drops out), and those are pinned exactly in
    # test-roundtrip.R rather than approximately here.
    expect_true(json_validate(txt), info = txt)
    expect_identical(outcome(json_parse(txt)), "value", info = txt)
  }
})

test_that("deeply nested input is rejected, not survived by luck", {
  for (d in c(1001L, 1500L, 5000L)) {
    src <- paste0(strrep("[", d), strrep("]", d))
    expect_error(json_parse(src), class = "zujson_depth_error")
    expect_error(json_parse(src, data_frame = TRUE), class = "zujson_depth_error")
  }
  # Just inside the limit still parses, so the boundary is where it is claimed.
  ok <- paste0(strrep("[", 1000L), strrep("]", 1000L))
  expect_type(json_parse(ok), "list")
})
