# Serializing to an exact string is the whole point of a serializer, so the
# assertion is on the bytes rather than on a re-parsed structure.
expect_json <- function(x, expected, ...) {
  testthat::expect_identical(json_write(x, ...), expected)
}

# A round trip is only interesting when it lands on the *same* object, so this
# uses identical() rather than equal(): an integer quietly becoming a double
# is exactly the kind of drift worth failing on.
expect_roundtrip <- function(x, simplify = TRUE, ...) {
  testthat::expect_identical(json_parse(json_write(x, ...), simplify = simplify), x)
}

# JSON text nested `depth` containers deep, e.g. depth 2 -> "[[null]]".
nested_json <- function(depth) {
  paste0(strrep("[", depth), "null", strrep("]", depth))
}

# An R list nested `depth` levels deep.
nested_list <- function(depth) {
  x <- NULL
  for (i in seq_len(depth)) x <- list(x)
  x
}
