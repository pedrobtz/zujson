## Submission

This is a new submission. zujson converts between JSON text and ordinary R
vectors and lists, backed by vendored 'yyjson' sources so that no system JSON
library is required.

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'Pedro Baltazar <pedrobtz@gmail.com>'
  New submission

  This is the expected note for a first submission.

## Test environments

* local macOS (aarch64), R release
* GitHub Actions: macOS, Windows, Ubuntu (R release and oldrel-1)
* R-hub containers on R-devel, matching CRAN's Linux flavours:
  clang23 (clang 23, -std=gnu23), ubuntu-clang, ubuntu-gcc16
* win-builder: R-devel and R-release

## Bundled sources

src/vendor/yyjson/ is yyjson 0.12.0, included verbatim under the MIT licence.
Its author is credited in Authors@R with the roles "ctb" and "cph", the
upstream licence ships as src/vendor/yyjson/LICENSE, and the provenance is
recorded in inst/COPYRIGHTS.

## Method references

There are no published references describing the methods in this package. It
implements JSON parsing and serialization against RFC 8259, with the type
mapping between JSON and R documented in full in ?json_parse and ?json_write.

## Compiled code

The package contains C code and is checked under AddressSanitizer,
UndefinedBehaviorSanitizer, valgrind, rchk and gctorture in continuous
integration, all clean.
