# correctness.md, "Test under a hostile session": the same calls give the same
# bytes whatever the session's locale and number-formatting options (#32).

test_that("output does not depend on the session's number formatting", {
  base <- session_outputs()
  withr::local_options(OutDec = ",", scipen = -5, digits = 3)
  expect_identical(session_outputs(), base)
  withr::local_options(scipen = 100)
  expect_identical(session_outputs(), base)
})

test_that("output does not depend on LC_NUMERIC or the C locale", {
  base <- session_outputs()
  withr::local_locale(c(LC_CTYPE = "C"))
  expect_identical(session_outputs(), base)
  comma <- c("de_DE.UTF-8", "de_DE.utf8", "fr_FR.UTF-8", "fr_FR.utf8")
  ok <- FALSE
  for (loc in comma) {
    ok <- suppressWarnings(nzchar(Sys.setlocale("LC_NUMERIC", loc)))
    if (ok) break
  }
  withr::defer(Sys.setlocale("LC_NUMERIC", "C"))
  skip_if_not(ok, "no comma-decimal locale on this machine")
  expect_identical(session_outputs(), base)
})
