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

test_that("json_validate agrees with json_parse", {
  for (s in c('{"a":1}', "[]", "null", "{", "", "[1,]", '{"a"}')) {
    parsed <- tryCatch({ json_parse(s); TRUE }, zujson_error = function(e) FALSE)
    expect_identical(json_validate(s), parsed)
  }
})

test_that("bad arguments are rejected", {
  expect_error(json_validate(1), class = "zujson_arg_error")
  expect_error(json_validate(list()), class = "zujson_arg_error")
})
