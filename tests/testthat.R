# This file is part of the standard setup for testthat.
# It is recommended that you do not modify it.
#
# Where should you do additional test configuration?
# Learn more about the roles of various files in:
# * https://r-pkgs.org/testing-design.html#sec-tests-files-overview
# * https://testthat.r-lib.org/articles/special-files.html

# testthat and withr are in Suggests, so CRAN's NOSUGGESTS flavour runs this
# file without them. Running no tests there is the accepted outcome: that
# flavour checks the package stands up without its suggested packages, not that
# the suite does. withr is guarded too, because the tests call withr:: directly
# and a library with testthat but not withr would otherwise fail test by test.
if (
  requireNamespace("testthat", quietly = TRUE) &&
    requireNamespace("withr", quietly = TRUE)
) {
  library(testthat)
  library(zujson)

  test_check("zujson")
}
