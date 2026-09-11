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
  for (s in c('{"a":1}', "[]", "null", "{", "", "[1,]", '{"a"}',
              "1e309", "[1e309]", "[Infinity]", "[NaN]")) {
    parsed <- tryCatch({ json_parse(s); TRUE }, zujson_error = function(e) FALSE)
    expect_identical(json_validate(s), parsed)
  }
})

test_that("validity and parseability diverge only on a NUL escape", {
  # the escape is valid JSON, so json_validate() is right to say TRUE, and an R
  # string cannot hold the result, so json_parse() is right to fail. This is
  # the only input where the two disagree, and ?json_validate says so.
  esc <- paste0("\\", "u0000")
  js <- paste0('["a', esc, 'b"]')
  expect_true(json_validate(js))
  expect_error(json_parse(js), class = "zujson_parse_error")
})

test_that("bad arguments are rejected", {
  expect_error(json_validate(1), class = "zujson_arg_error")
  expect_error(json_validate(list()), class = "zujson_arg_error")
})
