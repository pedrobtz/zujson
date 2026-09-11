test_that("json_validate reports valid and invalid input without erroring", {
  expect_true(json_validate('{"a": 1}'))
  expect_true(json_validate("[]"))
  expect_true(json_validate("null"))
  expect_false(json_validate("{"))
  expect_false(json_validate(""))
  expect_false(json_validate("{'a': 1}"))
  expect_false(json_validate(NA_character_))
})

test_that("json_validate accepts raw bytes", {
  expect_true(json_validate(charToRaw('{"a": 1}')))
  expect_false(json_validate(charToRaw("{")))
  expect_false(json_validate(raw()))
})

test_that("an out-of-range number is valid JSON and says so", {
  # the read flags are shared, so this is really asserting that the reader
  # does not reject a document over a number it cannot hold as a double
  expect_true(json_validate("1e309"))
  expect_true(json_validate("[-1e309, 1]"))
  # the literals that are not JSON stay invalid: we do not allow inf/nan
  expect_false(json_validate("[Infinity]"))
  expect_false(json_validate("[-Infinity]"))
  expect_false(json_validate("[NaN]"))
  expect_false(json_validate("[inf]"))
})

test_that("json_validate agrees with json_parse", {
  # everything except the two documented divergences below, which have their
  # own test. Nesting right up to the cap belongs here rather than there: the
  # two agree at 1000 and only part company at 1001.
  at_cap <- paste0(strrep("[", 1000), strrep("]", 1000))
  for (s in c('{"a":1}', "[]", "null", "{", "", "[1,]", '{"a"}',
              "1e309", "[1e309]", "[Infinity]", "[NaN]", at_cap)) {
    parsed <- tryCatch({ json_parse(s); TRUE }, zujson_error = function(e) FALSE)
    expect_identical(json_validate(s), parsed)
  }
})

test_that("validity and parseability diverge on exactly two classes of input", {
  # Both are valid JSON that cannot become an R value, so json_validate() is
  # right to say TRUE and json_parse() is right to fail. ?json_validate lists
  # both; there is no third.

  # 1. a string R cannot hold. The escape is legal JSON and an R string cannot
  #    carry a NUL. (The >INT_MAX case is the same guard in zu_mkchar(), and is
  #    not tested here because it would need a 2GB string.)
  esc <- paste0("\\", "u0000")
  js <- paste0('["a', esc, 'b"]')
  expect_true(json_validate(js))
  expect_error(json_parse(js), class = "zujson_parse_error")

  # 2. nesting past the cap. RFC 8259 leaves a depth limit to the
  #    implementation, so the bytes are valid; it is our recursive tree builder
  #    that cannot take them, and yyjson's iterative reader never notices.
  over <- paste0(strrep("[", 1001), strrep("]", 1001))
  expect_true(json_validate(over))
  expect_error(json_parse(over), class = "zujson_depth_error")

  # validation stays cheap and safe however deep the input goes -- that is why
  # it does not enforce the cap, rather than an oversight
  expect_true(json_validate(paste0(strrep("[", 1e5), strrep("]", 1e5))))
})

test_that("bad arguments are rejected", {
  expect_error(json_validate(1), class = "zujson_arg_error")
  expect_error(json_validate(list()), class = "zujson_arg_error")
})
