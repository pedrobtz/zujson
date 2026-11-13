#!/usr/bin/env Rscript
#
# The workload for r-actions' alloc-failure.yml (alloc-failure.yaml), which
# runs it once per allocation, failing a different one each time.
#
# What the sweep checks: a run whose injected failure is not absorbed must die
# with R's own allocation error, which the workflow's expect-pattern matches,
# never with a crash or an unrelated error. A run that absorbs the failure
# must still get the right answer, which only the workload can check -- so
# every call below compares its result against a literal, and a wrong one
# stops with "WRONG RESULT", which the pattern does not match.
#
# It covers every C entry point that holds native memory across an R
# allocation (design §8): parse from a string, from raw and line by line;
# validate; the data frame builder; write to a string, to raw, and line by
# line, with a data frame. Each also runs once on its error path, where the
# finalizer rather than the explicit free reclaims the document.
#
# Base R only, and small: it runs once for every allocation in the sweep.
#
# Usage:  Rscript tools/alloc-exercise.R

library(zujson)

check <- function(got, want, what) {
  if (!identical(got, want)) {
    stop("WRONG RESULT from ", what, call. = FALSE)
  }
}

# Only the package's own condition classes are caught. An injected failure
# that surfaces as R's allocation error, or as the package's own out-of-memory
# condition, propagates and ends the run with that message, which the sweep's
# patterns match; catching every error here reported it as "WRONG RESULT"
# instead (#69, the check for #52).
classed <- function(expr, cls, what) {
  got <- tryCatch(
    {
      force(expr)
      "value"
    },
    zujson_error = function(e) {
      # fixed matching: a regex would compile through TRE, which itself
      # fails, or crashes, under an injected allocation failure
      m <- conditionMessage(e)
      if (grepl("failed to allocate memory", m, fixed = TRUE) ||
          grepl("out of memory", m, fixed = TRUE)) {
        stop(e)
      }
      class(e)
    }
  )
  if (!cls %in% got) stop("WRONG RESULT from ", what, call. = FALSE)
}

doc <- '{"id":7,"tags":["a","b"],"rows":[{"x":1,"y":"p"},{"x":2,"y":"q"}]}'

check(json_parse(doc)$tags, c("a", "b"), "json_parse")
check(json_parse_raw(charToRaw(doc))$id, 7L, "json_parse_raw")
check(json_validate(doc), TRUE, "json_validate")
check(
  json_parse(doc, data_frame = TRUE)$rows$y,
  c("p", "q"),
  "json_parse(data_frame = TRUE)"
)
check(
  json_parse('[1,"a",null]', simplify = "coerce"),
  c("1", "a", NA),
  "json_parse(simplify = \"coerce\")"
)
check(
  json_parse_ndjson('{"a":1}\n{"a":2}\n'),
  list(list(a = 1L), list(a = 2L)),
  "json_parse_ndjson"
)

x <- list(
  id = 7L,
  tags = c("a", "b"),
  rows = data.frame(x = 1:2, y = c("p", "q"))
)
check(
  json_write(x),
  '{"id":7,"tags":["a","b"],"rows":[{"x":1,"y":"p"},{"x":2,"y":"q"}]}',
  "json_write"
)
check(json_write_raw(x), charToRaw(json_write(x)), "json_write_raw")
check(
  json_write_ndjson(data.frame(a = 1:2)),
  '{"a":1}\n{"a":2}\n',
  "json_write_ndjson"
)

classed(json_parse('{"a":[1,2'), "zujson_parse_error", "a truncated document")
classed(
  json_parse('[{"k":1,"k":2}]', data_frame = TRUE),
  "zujson_parse_error",
  "a duplicate key in a data frame record"
)
classed(
  json_parse_ndjson('{"a":1}\n{oops}\n'),
  "zujson_parse_error",
  "a bad NDJSON record"
)
classed(
  json_write(list(f = sum)),
  "zujson_unsupported_type",
  "an unsupported value"
)

cat("alloc-exercise: ok\n")
