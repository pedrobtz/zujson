#!/usr/bin/env Rscript
#
# Exercise the C layer under a sanitizer, using nothing but base R.
#
# The sanitizer jobs care about the compiled code: memory errors, undefined
# behaviour, and leaks on the unwind path. They do not care about testthat's
# assertions. Depending on testthat would make the jobs fail for an unrelated
# reason -- the r-hub containers' binary repository does not host it, and
# building it and its dependencies from source under a sanitizer is slow and
# fragile. So this script has no dependencies at all.
#
# It deliberately spends most of its effort on *error* paths. An R error is a
# longjmp that skips the explicit yyjson_doc_free() and leaves the external
# pointer's finalizer to reclaim the document, which is the most delicate thing
# in the C layer and the thing a leak checker is best placed to catch.
#
# Usage:  Rscript tools/sanitizer-exercise.R

library(zujson)

failures <- 0L
checked <- 0L

check <- function(label, expr) {
  checked <<- checked + 1L
  ok <- tryCatch(isTRUE(expr), error = function(e) {
    message("  ERROR in ", label, ": ", conditionMessage(e))
    FALSE
  })
  if (!ok) {
    failures <<- failures + 1L
    message("  FAILED: ", label)
  }
  invisible(ok)
}

# Anything that raises a zujson condition is fine; a crash or a bare R error is
# not, and the sanitizer will say so independently.
quietly <- function(expr) {
  tryCatch({ force(expr); "ok" },
           zujson_error = function(e) "condition",
           error = function(e) paste0("bare: ", conditionMessage(e)))
}

cat("-- round trips ----------------------------------------------------\n")

values <- list(
  NULL, TRUE, FALSE, 42L, -7L, 3.14159265358979, 0, -0.5,
  "hello", "42", "true", "", "café — 日本語",
  list(1L, 2L, 3L), list(a = 1L, b = "x"),
  list(a = list(b = list(c = 1L))),
  as.list(seq_len(50)), as.list(letters),
  structure(list(), names = character()), list()
)
for (v in values) {
  check(paste("round trip", deparse(v)[1]),
        !is.null(quietly(json_parse(json_write(v)))))
}

cat("-- parsing, including every error path ----------------------------\n")

sources <- c(
  '{"a":1}', "[1,2,3]", '["a","b"]', "[true,false,null]", "null", "{}", "[]",
  '{"a":{"b":{"c":[1,2,{"d":null}]}}}', '[1,"a"]', '[1,{}]', "[null,null]",
  # numbers at the edges of both R types
  "2147483647", "-2147483648", "2147483648", "9007199254740993",
  "1e308", "1e-308", "-0.0", "1e400",
  # strings that stress the CHARSXP guards
  '"\\u00e9"', '"\\ud83d\\ude00"', '"\\u0000"', '{"\\u0000":1}',
  # error paths
  "{bad", "[1,2", '{"a":}', '{"a" 1}', "tru", "", " ", "\xef\xbb\xbf{}",
  "[[[[[[[[[[1]]]]]]]]]]",
  paste0(strrep("[", 2000), strrep("]", 2000)),   # past ZUJSON_MAX_DEPTH
  paste0('{"a":', strrep("[", 1500), strrep("]", 1500), "}")
)
for (src in sources) {
  for (mode in list(TRUE, FALSE, "coerce")) {
    for (df in c(FALSE, TRUE)) {
      r <- quietly(json_parse(src, simplify = mode, data_frame = df))
      check(paste("parse:", substr(encodeString(src), 1, 24),
                  "/", mode, "/", df),
            r %in% c("ok", "condition"))
    }
  }
  check(paste("validate:", substr(encodeString(src), 1, 24)),
        is.logical(json_validate(src)))
  check(paste("raw parse:", substr(encodeString(src), 1, 24)),
        quietly(json_parse_raw(charToRaw(src))) %in% c("ok", "condition"))
}

cat("-- the coerce path ------------------------------------------------\n")

# The mixed-kind branch allocates a second vector and coerces it, so it is the
# one parse path with a non-trivial allocation pattern.
coerce_srcs <- c(
  '[1,"a"]', '[true,"x"]', '[1.5,null,"a"]', '[1,2,3,"a"]',
  '[0.3333333333333333,"a"]', '[1e30,"a",null,true]',
  paste0("[", paste(c(seq_len(500), '"tail"'), collapse = ","), "]")
)
for (src in coerce_srcs) {
  check(paste("coerce:", substr(src, 1, 24)),
        is.character(json_parse(src, simplify = "coerce")))
}

cat("-- data frames ----------------------------------------------------\n")

df_srcs <- c(
  '[{"a":1},{"a":2}]', '[{"a":1},{"b":2}]', '[{},{}]', '[{"a":[1,2]},{"a":3}]',
  '[{"a":1},{"a":"x"}]', '[{"a":null},{"a":1}]',
  # every record inventing new keys: the quadratic branch of the key union
  paste0("[", paste(sprintf('{"k%d":%d}', 1:200, 1:200), collapse = ","), "]"),
  # many rows, few columns
  paste0("[", paste(rep('{"a":1,"b":"x"}', 500), collapse = ","), "]")
)
for (src in df_srcs) {
  for (mode in list(TRUE, "coerce")) {
    r <- quietly(json_parse(src, data_frame = TRUE, simplify = mode))
    check(paste("data frame:", substr(src, 1, 24), "/", mode),
          r %in% c("ok", "condition"))
  }
}

cat("-- NDJSON ---------------------------------------------------------\n")

nd_srcs <- c(
  '{"a":1}\n{"a":2}\n', '{"a":1}', "", "\n\n\n", '{"a":1}\n\n{"a":2}',
  '{"a":1}\r\n{"a":2}\r\n', '{"a":1}\n{bad}\n', '[1]\n[2]\n'
)
for (src in nd_srcs) {
  check(paste("ndjson:", substr(encodeString(src), 1, 24)),
        quietly(json_parse_ndjson(src)) %in% c("ok", "condition"))
  check(paste("ndjson write:", substr(encodeString(src), 1, 24)),
        quietly(json_write_ndjson(list(list(a = 1L), list(a = 2L)))) == "ok")
}

cat("-- writing, including every error path ----------------------------\n")

write_vals <- list(
  1:1000, seq(0, 1, length.out = 500), rep(c(TRUE, NA), 100), letters,
  list(a = 1:10, b = letters), I("x"), I(1L), as.Date("2026-09-08"),
  as.POSIXct("2026-09-08 12:00:00", tz = "UTC"),
  data.frame(id = 1:20, nm = letters[1:20], stringsAsFactors = FALSE),
  c(a = 1, b = 2), NA, NaN, Inf, -Inf, NULL, list(),
  structure(1:3, class = "unknown_s3_class"),

  # Date and POSIXct are doubles, so a value can sit far outside the range
  # int64_t holds. Converting one is undefined behaviour that a release build
  # merely saturates, which is exactly what a sanitizer is here to catch: the
  # boundaries either side, and values past every boundary there is.
  structure(c(-719528, 2932896), class = "Date"),
  structure(c(-719529, 2932897), class = "Date"),
  structure(c(0, 1e300, -1e300, 1e18, .Machine$double.xmax), class = "Date"),
  .POSIXct(c(-62167219200, 253402300799), tz = "UTC"),
  .POSIXct(c(-62167219201, 253402300800), tz = "UTC"),
  .POSIXct(c(0, 1e300, -1e300, 1e18, .Machine$double.xmax), tz = "UTC"),

  # "bytes" has no encoding to convert from, and is refused before the R
  # internals raise a bare error about it
  structure(list(a = `Encoding<-`("\xe4\xf6", "bytes")), class = "list")
)
for (v in write_vals) {
  check(paste("write", class(v)[1]),
        quietly(json_write(v)) %in% c("ok", "condition"))
  check(paste("write raw", class(v)[1]),
        quietly(json_write_raw(v)) %in% c("ok", "condition"))
  check(paste("write pretty", class(v)[1]),
        quietly(json_write(v, pretty = TRUE)) %in% c("ok", "condition"))
}

cat("-- unwind path (errors while the C document is live) --------------\n")

# The document is owned by an external pointer precisely so that a condition
# raised mid-conversion cannot leak it. Depth and NUL errors are raised deep in
# the walk, after the document exists and after some of the result is built.
ragged <- paste0("[", paste0(sprintf('{"k%d":%d}', 1:4000, 1:4000),
                            collapse = ","), "]")

# A low budget so the ragged parse *aborts* here rather than succeeding: this
# loop is about the unwind, and a 4000 x 4000 frame built 200 times would only
# be slow. base R throughout, so the option is restored by hand.
old_opts <- options(zujson.max_df_cells = 1000)

for (i in seq_len(200)) {
  quietly(json_parse(paste0(strrep("[", 1200), strrep("]", 1200))))
  quietly(json_parse('{"a":[1,2,"\\u0000"]}'))
  quietly(json_parse('[{"a":1},{"\\u0000":2}]', data_frame = TRUE))
  quietly(json_parse("{bad"))
  # the frame paths abort with the key table and the cell matrix live: both are
  # R_alloc'd, so the longjmp has to be what releases them
  quietly(json_parse('[{"a":1,"a":2}]', data_frame = TRUE))
  quietly(json_parse(ragged, data_frame = TRUE))
  quietly(json_parse(paste0(strrep("[", 999), '{"a":1}', strrep("]", 999)),
                     data_frame = TRUE))
}
options(old_opts)
gc()
check("unwind path survived 1400 aborted parses", TRUE)
check("the budget option was restored",
      zujson_info()$max_df_cells > 1000)

# A malformed option is refused in R and never reaches C.
for (bad in list("x", 0, -1, NA_real_, Inf)) {
  opts <- options(zujson.max_df_cells = bad)
  check(paste("budget option refused:", format(bad)),
        quietly(json_parse('[{"a":1}]', data_frame = TRUE)) == "condition")
  options(opts)
}

# A well-formed one that is merely enormous is *not* refused -- that is how the
# limit is switched off -- so it is the value that reaches the cast to
# R_xlen_t. Unclamped, converting it is undefined, which is exactly the check
# -fsanitize=undefined's float-cast-overflow makes. The two clamps are
# defence in depth, so this line fails only with *both* removed; the check
# below is what fails when the one in zu_df_cells() goes on its own, since
# without it the option is reported back at the 1e300 it was set to rather
# than at the ceiling the parser will enforce.
opts <- options(zujson.max_df_cells = 1e300)
check("budget switched off",
      quietly(json_parse('[{"a":1},{"b":2}]', data_frame = TRUE)) == "ok")
check("switched off, the reported limit is the clamped one",
      identical(zujson_info()$max_df_cells, zujson:::zu_build_info()$max_xlen))
options(opts)

# The same key table and cell matrix on the paths that *succeed*, at a size
# that makes the hash table resize and the matrix large enough to matter.
wide <- paste0("[", paste0(rep(paste0("{", paste0(sprintf('"k%d":1', 1:300),
                                                 collapse = ","), "}"), 300),
                           collapse = ","), "]")
check("wide frame", quietly(json_parse(wide, data_frame = TRUE)) == "ok")
check("ragged frame under the budget",
      quietly(json_parse(paste0("[", paste0(sprintf('{"k%d":%d}', 1:1000, 1:1000),
                                            collapse = ","), "]"),
                         data_frame = TRUE)) == "ok")

# The key index is sized by the budget wherever the budget is the tighter of
# the two bounds, so a low limit against a wide body is where its arrays are
# at their smallest relative to the keys offered: 90000 members, room interned
# for seventeen. An off-by-one in that sizing is a heap overflow, and this is
# where asan can see it -- every other frame case leaves the arrays oversized.
#
# The budget is 5100 rather than something tighter for asan's sake, not the
# index's. R_alloc serves a request of 128 data bytes or less from R's pooled
# small-vector nodes, several to a malloc'd page, where an overrun lands in a
# neighbouring node and asan has no redzone to trip. 5100 / 300 rows is 17
# columns, which puts all three arrays (17 x 16, 17 x 8, 64 x 8 bytes) past
# that threshold and onto individually malloc'd blocks that asan does police.
opts <- options(zujson.max_df_cells = 5100)
check("wide frame refused with the key index at its tightest",
      quietly(json_parse(wide, data_frame = TRUE)) == "condition")
options(opts)

cat("-- files ----------------------------------------------------------\n")

path <- tempfile(fileext = ".json")
writeLines('{"a":[1,2,3],"b":{"c":"x"}}', path)
check("parse file", quietly(json_parse_file(path)) == "ok")
check("parse file, data frame", quietly(json_parse_file(path, data_frame = TRUE)) == "ok")
unlink(path)
check("missing file is a condition", quietly(json_parse_file(path)) == "condition")

writeLines("{bad", path)
check("unparseable file is a condition", quietly(json_parse_file(path)) == "condition")
unlink(path)

cat("\n", checked, " checks, ", failures, " failures\n", sep = "")
if (failures > 0L) quit(status = 1L)
