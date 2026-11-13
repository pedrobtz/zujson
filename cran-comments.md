## Submission

This is an update, zujson 0.1.0 to 0.1.1. It fixes the bugs found by an
adversarial review of 0.1.0 (wrong JSON written for a few R value types, a
data frame option that could be made to run in quadratic time, and conditions
that escaped the package's documented error classes), and makes five small
behaviour changes, each listed in NEWS.md.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

These are the legs of the package's continuous integration, which runs
`R CMD check --as-cran` on each:

* GitHub Actions: macOS, Windows and Ubuntu, R release; Windows, R-devel;
  Ubuntu, R oldrel-1
* R-hub containers on R-devel matching CRAN's Linux flavours: clang23 (clang
  23, -std=gnu23), ubuntu-clang, ubuntu-gcc16, and the no-Suggests and
  no-long-double (nold) flavours
* local macOS (x86_64 build of R 4.6.2), R release

## Reverse dependencies

Two CRAN packages suggest zujson: zumime and zutoml. Both were checked with
`R CMD check` against this version, with zujson 0.1.1 installed and their
zujson-using tests run: both are Status: OK, with no new problems.

## Bundled sources

src/vendor/yyjson/ is yyjson 0.12.0, included verbatim under the MIT licence
and unchanged since 0.1.0. Its author is credited in Authors@R with the roles
"ctb" and "cph", the upstream licence ships as src/vendor/yyjson/LICENSE, and
the provenance is recorded in inst/COPYRIGHTS.

## Compiled code

The package contains C code and is checked in continuous integration under
AddressSanitizer, UndefinedBehaviorSanitizer, valgrind, rchk, gcc -fanalyzer,
gctorture and an allocation-failure sweep, all clean.
