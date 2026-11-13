# For test-session.R. A helper file rather than file scope in the test file,
# because `shuffle = TRUE` reorders every top-level expression of a test file
# and a test could otherwise run before this was defined.

# The same calls, in both directions, whose output must not depend on the
# session: numbers, dates, strings in two encodings, and every writer and
# reader route (#32).
session_outputs <- function() {
  x <- list(
    d = c(0.1, 1e-300, 1e300, 2^53 + 2, 123456.7, -0.5),
    i = c(1L, NA, -2147483647L),
    when = as.Date("2024-02-29"),
    at = .POSIXct(1709164800.75, tz = "UTC"),
    s = c("café", "plain"),
    f = factor(c("b", "a"))
  )
  latin <- "caf\xe9"
  Encoding(latin) <- "latin1"
  list(
    write = json_write(x),
    pretty = json_write(x, pretty = TRUE),
    raw = json_write_raw(x),
    ndjson = json_write_ndjson(data.frame(a = c(1.5, 2), b = c("x", "y"))),
    latin = json_write(list(k = latin)),
    parse = json_parse("[1.5, 2.25, 1e400, 1.5e400, -0.0, 12345678901234567890]"),
    parse_df = json_parse('[{"a":1.5},{"a":2}]', data_frame = TRUE),
    parse_ndjson = json_parse_ndjson("1.5\n[2.5,3]\n")
  )
}
