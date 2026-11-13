# Serializing to an exact string is the whole point of a serializer, so the
# assertion is on the bytes rather than on a re-parsed structure.
# identical() compares characters, not a CHARSXP's encoding mark, so the mark
# is asserted separately: non-ASCII output must be marked UTF-8 (#72).
expect_json <- function(x, expected, ...) {
  out <- json_write(x, ...)
  testthat::expect_identical(out, expected)
  if (!all(utf8ToInt(enc2utf8(out)) < 128L)) {
    testthat::expect_identical(Encoding(out), "UTF-8")
  }
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

# A bit64::integer64 vector built without bit64: the class over a double whose
# bits are the int64 value, given as its low and high 32-bit words. Reading the
# words back as a double in the same byte order makes the bits right on any
# endianness. hi = NA_integer_ with lo = 0 is INT64_MIN, bit64's NA.
as_int64 <- function(lo, hi = ifelse(lo < 0L, -1L, 0L)) {
  words <- as.vector(rbind(as.integer(lo), as.integer(hi)))
  bits <- writeBin(words, raw(), endian = "little")
  structure(
    readBin(bits, "double", n = length(lo), endian = "little"),
    class = "integer64"
  )
}

# `x` wrapped in `k` single-element lists, so it sits at depth k + its own.
wrap_list <- function(x, k) {
  for (i in seq_len(k)) {
    x <- list(x)
  }
  x
}
