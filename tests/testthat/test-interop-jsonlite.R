# Differential tests with jsonlite as an oracle.
#
# This is deliberately not a port of jsonlite's own suite. That suite is
# self-referential: 60 of its 77 fromJSON() calls are fromJSON(toJSON(x))
# roundtrips and only three take a literal JSON string, so running it here
# would mostly exercise arguments zujson does not have -- digits, na, null,
# POSIXt, Date, complex, matrix, dataframe -- and two thirds of its files
# (serializeJSON of functions and environments, sf/geojson, rbind_pages) are
# about features outside this package entirely.
#
# What survives the framing in CLAUDE.md is the question a caller moving from
# jsonlite actually has: for JSON *text*, which is all an HTTP client ever
# sees, where do the two agree and where do they not? Both tables below state
# zujson's own expected value rather than just comparing the two packages, so
# a change in jsonlite fails with the blame in the right place instead of
# looking like a regression here.
#
# The divergence table is the point of the file. It turns "how zujson differs
# from jsonlite" into an executable contract, and it fails if a future change
# quietly makes this package more jsonlite-like than §5 of the design says it
# should be.

test_that("zujson and jsonlite read ordinary JSON text the same way", {
  skip_if_not_installed("jsonlite")

  cases <- list(
    # objects and the plain shapes a response body is made of
    list('{"a":1}',                            list(a = 1L)),
    list('{"a":1,"b":"x","c":true,"d":null}',  list(a = 1L, b = "x", c = TRUE,
                                                    d = NULL)),
    list('{"a":[1,2],"b":{"c":true}}',         list(a = 1:2, b = list(c = TRUE))),
    list('{}',                                 setNames(list(), character(0))),
    list('{"a":{}}',                           list(a = setNames(list(),
                                                                 character(0)))),
    # duplicate and empty keys are kept, not merged or dropped
    list('{"a":1,"a":2}',   setNames(list(1L, 2L), c("a", "a"))),
    list('{"":1}',          setNames(list(1L), "")),

    # arrays that do agree on a type
    list('[1,2,3]',         1:3),
    list('[1,2.5]',         c(1, 2.5)),
    list('[true,false]',    c(TRUE, FALSE)),
    list('["a","b"]',       c("a", "b")),

    # null inside a simplified array is NA, and null on its own is NULL
    list('[1,null,3]',      c(1L, NA, 3L)),
    list('["a",null]',      c("a", NA)),
    list('[true,null]',     c(TRUE, NA)),
    list('[null,null]',     c(NA, NA)),
    list('null',            NULL),

    # a nested container makes the array a list in both packages
    list('[1,{}]',          list(1L, setNames(list(), character(0)))),
    list('["a",[1]]',       list("a", 1L)),

    # scalars at the root
    list('1',     1L),
    list('-1',    -1L),
    list('1.5',   1.5),
    list('"s"',   "s"),
    list('true',  TRUE),
    list('false', FALSE)
  )

  json <- vapply(cases, `[[`, character(1), 1L)
  want <- lapply(cases, `[[`, 2L)
  names(want) <- json

  # naming by the JSON text makes a failure point at the row that moved
  expect_identical(setNames(lapply(json, json_parse), json), want)
  expect_identical(setNames(lapply(json, jsonlite::fromJSON), json), want)
})

test_that("zujson and jsonlite agree at the edges of the number line", {
  skip_if_not_installed("jsonlite")

  cases <- list(
    list('[0]',            0L),
    list('[-0]',           0L),
    list('[1e2]',          100),
    list('[-1.5e-3]',      -0.0015),
    list('[0.1]',          0.1),
    # the int32 boundary, including the value that is NA_INTEGER's bit pattern
    list('[2147483647]',   2147483647L),
    list('[-2147483648]',  -2147483648),
    list('[2147483648]',   2147483648),
    # the double boundary: finite either side, Inf past it, 0 on underflow
    list('[1e308]',        1e308),
    list('[1e-400]',       0),
    list('[1e309]',        Inf),
    list('[-1e309]',       -Inf),
    # wider than int64, so neither package keeps it exact
    list('[123456789012345678901234567890]',
         as.numeric("123456789012345678901234567890")),
    list('[9223372036854775808]', as.numeric("9223372036854775808"))
  )

  json <- vapply(cases, `[[`, character(1), 1L)
  want <- lapply(cases, `[[`, 2L)
  names(want) <- json

  expect_identical(setNames(lapply(json, json_parse), json), want)
  expect_identical(setNames(lapply(json, jsonlite::fromJSON), json), want)
})

test_that("zujson and jsonlite decode strings and escapes the same way", {
  skip_if_not_installed("jsonlite")

  cases <- list(
    list('[""]',                    ""),
    list('["\\u0041"]',             "A"),
    list('["\\\\"]',                "\\"),
    list('["\\/"]',                 "/"),
    list('["a\\"b"]',               "a\"b"),
    list('["\\b\\f\\n\\r\\t"]',     "\b\f\n\r\t"),
    # a surrogate pair has to become one code point, not two
    list('["\\uD83D\\uDE02"]',      "\U0001F602"),
    # the same character escaped and literal must land on the same string
    list('["\\u00e9"]',             "é"),
    list('{"\\u00e9":1}',           setNames(list(1L), "é"))
  )

  json <- vapply(cases, `[[`, character(1), 1L)
  want <- lapply(cases, `[[`, 2L)
  names(want) <- json

  expect_identical(setNames(lapply(json, json_parse), json), want)
  expect_identical(setNames(lapply(json, jsonlite::fromJSON), json), want)
})

test_that("the divergences from jsonlite are exactly the documented ones", {
  skip_if_not_installed("jsonlite")

  empty_obj <- setNames(list(), character(0))

  # json, what zujson gives by default, what jsonlite gives.
  # Every row here is a decision in design §5, not an accident.
  cases <- list(
    # an empty array has no elements to take a type from, so it is the
    # zero-length atomic vector, not a list (§5, resolved question 3)
    list('[]',        logical(0),               list()),
    list('[[]]',      list(logical(0)),         list(list())),
    list('{"a":[]}',  list(a = logical(0)),     list(a = list())),

    # preserve keeps the type and gives up the uniform shape: a field that is
    # usually a number and sometimes a string is a bug worth seeing
    list('[1,"a"]',   list(1L, "a"),            c("1", "a")),

    # an array of objects is a list of named lists unless data_frame = TRUE
    list('[{"a":1},{"b":2}]',
         list(list(a = 1L), list(b = 2L)),
         data.frame(a = c(1L, NA), b = c(NA, 2L))),
    list('[{}]',
         list(empty_obj),
         jsonlite::fromJSON('[{}]')),

    # no matrix or n-d array detection, in any mode (§5, questions 5 and 6)
    list('[[1,2],[3,4]]',
         list(1:2, 3:4),
         matrix(c(1L, 3L, 2L, 4L), nrow = 2))
  )

  json    <- vapply(cases, `[[`, character(1), 1L)
  want_zu <- lapply(cases, `[[`, 2L)
  want_jl <- lapply(cases, `[[`, 3L)
  names(want_zu) <- names(want_jl) <- json

  expect_identical(setNames(lapply(json, json_parse), json), want_zu)
  expect_identical(setNames(lapply(json, jsonlite::fromJSON), json), want_jl)

  # and they really are different, so a row that converges is not missed
  for (j in json) expect_false(identical(want_zu[[j]], want_jl[[j]]))
})

test_that("the opt-in modes converge on jsonlite where they are meant to", {
  skip_if_not_installed("jsonlite")

  # simplify = "coerce" follows R's own promotion, which is what jsonlite does
  for (j in c('[1,"a"]', '[1,true,"a"]', '[1.5,"a",null]')) {
    expect_identical(json_parse(j, simplify = "coerce"), jsonlite::fromJSON(j))
  }

  # data_frame = TRUE builds the frame jsonlite builds, ragged records included
  for (j in c('[{"id":1,"nm":"a"},{"id":2,"nm":"b"}]',
              '[{"a":1},{"b":2}]',
              '[{}]')) {
    expect_identical(json_parse(j, data_frame = TRUE), jsonlite::fromJSON(j))
  }

  # a matrix stays a list of rows in every mode: this one does not converge
  expect_identical(
    json_parse('[[1,2],[3,4]]', simplify = "coerce", data_frame = TRUE),
    list(1:2, 3:4)
  )
})

test_that("jsonlite reads back everything json_write() emits", {
  skip_if_not_installed("jsonlite")

  # what jsonlite makes of our output. Whole doubles are written without a
  # decimal point on purpose, so 1 comes back as 1L -- that is the documented
  # cost of emitting integers a schema will accept, not a roundtrip failure.
  cases <- list(
    list(list(a = 1L, b = "x", c = TRUE),  '{"a":1,"b":"x","c":true}',
         list(a = 1L, b = "x", c = TRUE)),
    list(list(a = 1:3, b = list(c = TRUE)), '{"a":[1,2,3],"b":{"c":true}}',
         list(a = 1:3, b = list(c = TRUE))),
    list(1:3,                    '[1,2,3]',        1:3),
    list(c("a", "b"),            '["a","b"]',      c("a", "b")),
    list(c(TRUE, FALSE),         '[true,false]',   c(TRUE, FALSE)),
    list(c(1, NA),               '[1,null]',       c(1L, NA)),
    list(setNames(list(), character(0)), '{}',     setNames(list(),
                                                            character(0))),
    list(data.frame(id = 1:2, nm = c("a", "b")),
         '[{"id":1,"nm":"a"},{"id":2,"nm":"b"}]',
         data.frame(id = 1:2, nm = c("a", "b"))),
    list("Zürich",          '"Zürich"',  "Zürich"),
    list("a\"b\nc",              '"a\\"b\\nc"',    "a\"b\nc")
  )

  for (case in cases) {
    js <- json_write(case[[1]])
    expect_identical(js, case[[2]])
    expect_true(jsonlite::validate(js))
    expect_identical(jsonlite::fromJSON(js), case[[3]])
  }

  # a double that is not whole survives the trip through jsonlite exactly,
  # which is what tells us the writer emits enough digits
  for (x in c(pi, 1 / 3, 0.1, 1e-300, 2^53, .Machine$double.xmax)) {
    expect_identical(jsonlite::fromJSON(json_write(x)), x)
  }
})
