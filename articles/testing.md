# Testing and conformance

This article is for someone deciding whether to trust zujson with input
they do not control, or about to change its C code. It says how the
package is checked and what it does with the JSON that conforming
parsers disagree on.

No single test can establish that a JSON library is correct. zujson uses
five layers: focused package tests, the same suite across five platform
and R version combinations, differential tests against `jsonlite`, the
language-independent JSONTestSuite corpus, and sanitizer and fuzzing
jobs for the C boundary.

## Test suite

The files under `tests/testthat/` divide the public contract by concern:

| File | What it tests |
|----|----|
| `helper-expect.R` | Exact JSON output, identity-preserving round trips and nesting fixtures shared by the suite. |
| `helper-fuzz.R` | Deterministic random-input generators, iteration limits and the accepted parse outcomes used by fuzz tests. |
| `test-conditions.R` | The `zujson_error` hierarchy, useful diagnostics and recovery after repeated failures. |
| `test-fuzz.R` | Random malformed and valid input, raw/character agreement, round trips and deep-input rejection. |
| `test-info.R` | Package and yyjson versions, the nesting limit and the data-frame cell budget reported by [`zujson_info()`](https://pedrobtz.github.io/zujson/reference/zujson_info.md). |
| `test-interop-jsonlite.R` | Agreements with `jsonlite`, deliberate divergences and whether `jsonlite` accepts zujson output. *Skips entirely without `jsonlite`.* |
| `test-ndjson.R` | NDJSON framing, blank lines, CRLF, raw input, error locations, data-frame rows and large streams. |
| `test-parse.R` | The JSON-to-R mapping, number boundaries, strings, files, encodings, depth limits and parse errors. *One unreadable-file test skips on Windows and as root.* |
| `test-roundtrip.R` | Stable parse/write cycles for representative, raw, Unicode, deep and large payloads. |
| `test-simplify.R` | Simplification modes and data-frame construction, including missing keys, duplicate keys and allocation limits. |
| `test-validate.R` | Valid and invalid JSON plus the documented cases where validation succeeds but R materialization cannot. |
| `test-write.R` | The R-to-JSON mapping, exact bytes, classes, date/time bounds, encodings, data frames and write errors. *One latin1 test skips where that conversion is unavailable.* |

The serializer tests compare exact output bytes. Round-trip tests use
[`identical()`](https://rdrr.io/r/base/identical.html), so changing an
integer into a double is a failure rather than an approximately equal
result. Tests are self-contained and also run in shuffled order to
expose hidden dependencies between them.

Nothing is skipped on CRAN. There is no `skip_on_cran()` in the suite,
and it is kept to a few seconds precisely so that it never needs one — a
test that only ever runs elsewhere is a test nobody reads the result of.
The three conditional skips marked above depend on the machine rather
than on the checking flavour: a missing `jsonlite`, a user or filesystem
that ignores permission bits, or a platform with no latin1 conversion
available.

## Platforms

The suite runs on every pull request, and on pushes to the main
branches, across five combinations: macOS, Windows and Linux on the
current R release, plus R-devel and the previous release on Linux. A
package that vendors C and converts between C and R numeric types cannot
assume that one platform generalises to the others.

That layer is not ceremony. One recent example: three tests compared a
parsed number against the same literal written in R source, which is the
obvious way to write such an expectation and passed everywhere except
`macos-latest`. R’s own string-to-double conversion accumulates through
`LDOUBLE`, which on `aarch64` is plain `double` rather than 80-bit
extended, so on Apple silicon R’s reader lands a few units in the last
place away from the correctly rounded value:

| Token                 | R’s reader on `aarch64`   | Correctly rounded        |
|-----------------------|---------------------------|--------------------------|
| `1e308`               | `0x1.1ccf385ebc8a3p+1023` | `0x1.1ccf385ebc8ap+1023` |
| `9223372036854775808` | `0x1.0000000000001p+63`   | `0x1p+63` (exactly 2^63) |

zujson and `jsonlite` both produced the correctly rounded value and
agreed with each other, so the reference was wrong rather than either
parser — and the tell was that the `jsonlite` half of the differential
test failed too, which is one oracle layer catching a mistake in
another. Those expectations are now written as exact bit patterns, which
are platform-independent in a way decimal literals are not. Where a
value genuinely does go through R’s own reader,
[`as.numeric()`](https://rdrr.io/r/base/numeric.html) remains the right
reference, because tracking R is the documented behaviour there.

## jsonlite interoperability

`jsonlite` is the reference R implementation, but zujson does not try to
copy its complete test suite. Much of that suite tests `toJSON()` and
`fromJSON()` together or covers features outside zujson’s scope, such as
configurable encodings for matrices, complex values and specialized
classes. Porting those tests would mostly test choices zujson
deliberately does not offer.

`jsonlite` is a suggested package, not a dependency: it is used only by
these tests, each of which skips when it is not installed.

Instead, `test-interop-jsonlite.R` uses `jsonlite` as an independent
oracle over JSON text. The packages agree on ordinary objects and
arrays, nulls, scalars, number boundaries, UTF-8, escapes and surrogate
pairs. The tests also verify that `jsonlite` accepts and reads every
representative document emitted by zujson.

The places where the two deliberately differ are executable expectations
too. The divergence tests fail if either package starts returning the
other’s result, and the opt-in tests separately verify that
`simplify = "coerce"` and `data_frame = TRUE` converge with `jsonlite`
where intended. [Coming from
jsonlite](https://pedrobtz.github.io/zujson/articles/jsonlite.md) lists
each difference with the reason for it.

## JSONTestSuite

The
[`tools/jsontestsuite.R`](https://github.com/pedrobtz/zujson/blob/main/tools/jsontestsuite.R)
script runs a pinned revision of
[nst/JSONTestSuite](https://github.com/nst/JSONTestSuite). Pinning the
revision means a changed result reflects a change in zujson, not a newly
added upstream fixture.

Each fixture is read as raw bytes. This matters because the corpus
includes invalid UTF-8, embedded NULs and UTF-16 input that would be
changed or rejected if read through an R character string first.

| JSONTestSuite group           |                   Result |
|-------------------------------|-------------------------:|
| Must accept (`y_`)            |           95/95 accepted |
| Must reject (`n_`)            |         188/188 rejected |
| Implementation-defined (`i_`) | 12 accepted, 23 rejected |

The script checks both
[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
and
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md).
It fails on an incorrect required acceptance or rejection, a bare R
error, an invalid document that parses, or an unexpected change in the
known validate/parse split.

### Implementation-defined cases

The `i_` prefix means the corpus permits either answer, so these are
choices rather than a contract: the split is recorded as a baseline and
flagged when it moves, not enforced. Flagging is what tells a deliberate
change to a reader flag apart from a regression — enabling bignum-as-raw
handling, for instance, moved exactly five `i_` files and no required
answer. zujson’s 35 decisions follow one rule: **generous about numbers,
strict about text**.

| Input class | Count | Result | Reason |
|----|---:|----|----|
| Numeric overflow, underflow or integers wider than `int64` | 10 | Accept | R can represent the nearest value as `Inf`, `0` or a finite double, so one extreme number does not invalidate the entire response. |
| 500 nested arrays | 1 | Accept | The document is valid and remains below zujson’s 1,000-container materialization limit. |
| UTF-8 byte-order mark | 1 | Accept | RFC 8259 allows parsers to ignore a leading BOM, and real APIs sometimes emit one. |
| Invalid or unpaired Unicode surrogates | 11 | Reject | A surrogate has meaning only as part of a valid pair. |
| Invalid UTF-8 byte sequences | 9 | Reject | Returning them would falsely label malformed bytes as UTF-8 R strings. |
| UTF-16 documents | 3 | Reject | JSON exchanged between systems is expected to be UTF-8; callers must transcode first. |

Five numeric fixtures overflow to positive or negative infinity, two
underflow to zero and three contain integers wider than `int64`. Once
parsed, they are ordinary R doubles and participate in simplification
like any other number.

``` r

json_parse("[123123e100000]")         # overflows: Inf, as as.numeric() gives
#> [1] Inf
json_parse("[123e-10000000]")         # underflows: 0
#> [1] 0
json_parse("[100000000000000000000]") # wider than int64: nearest double
#> [1] 1e+20
```

Text is the opposite. Every string that comes back is marked as UTF-8,
and that mark is only true because yyjson validated the bytes, so all 23
rejections are text that is not valid UTF-8. A surrogate that is not
half of a valid pair encodes no character:

``` r

json_validate('["\\ud800"]')        # lone high surrogate
#> [1] FALSE
json_validate('["\\uDd1e\\uD834"]') # a valid pair, inverted
#> [1] FALSE
json_validate('["\\ud83d\\ude02"]') # a correct pair
#> [1] TRUE
```

Invalid byte sequences are truncated characters, overlong encodings,
stray continuation bytes and Latin-1 text mislabelled as JSON. UTF-16 is
refused with or without a byte order mark; convert it with
[`iconv()`](https://rdrr.io/r/base/iconv.html) first.

``` r

json_validate(as.raw(c(0x22, 0xC0, 0xAF, 0x22))) # overlong encoding of "/"
#> [1] FALSE
json_validate(as.raw(c(0x22, 0xE9, 0x22)))       # Latin-1 e-acute
#> [1] FALSE
json_validate(as.raw(c(0xFF, 0xFE, 0x22, 0x00, 0x61, 0x00, 0x22, 0x00)))
#> [1] FALSE
```

The two structural acceptances, 500 nested arrays and a UTF-8 byte order
mark before the document:

``` r

json_validate(paste0(strrep("[", 500), strrep("]", 500)))
#> [1] TRUE
json_parse(as.raw(c(0xEF, 0xBB, 0xBF, 0x7B, 0x7D))) # BOM, then {}
#> named list()
```

The suite also contains two valid strings with escaped NUL characters.
[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
correctly accepts the JSON, while
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
raises a structured error because R strings cannot contain NUL. The
other documented validation/materialization difference is nesting beyond
1,000 levels; the external corpus has no complete fixture beyond that
limit, so the package suite tests it directly.

## Sanitizers and fuzzing

[`tools/sanitizer-exercise.R`](https://github.com/pedrobtz/zujson/blob/main/tools/sanitizer-exercise.R)
is a small, dependency-free driver for the compiled C layer. It is not a
second unit-test suite. Its job is to make memory errors, leaks and
undefined behaviour observable when the package is compiled under a
sanitizer.

The script exercises:

- ordinary and raw round trips;
- successful and malformed parsing in every simplification mode;
- data-frame construction, duplicate-key errors and allocation-budget
  errors;
- NDJSON framing and writing;
- supported and out-of-range `Date` and `POSIXct` values;
- invalid encodings and unsupported R types;
- hundreds of failures followed by garbage collection; and
- successful and failing file input.

The repeated failure paths matter because an R error performs a long
jump: it does not return through the C stack and therefore skips an
ordinary `free()`. zujson transfers each live yyjson allocation to an R
external pointer before an error can occur. The exerciser checks that
finalizers reclaim those allocations without leaks, double frees or
use-after-free errors.

The hardening workflow compiles and runs this driver under `clang-asan`,
`gcc-asan` and `clang-ubsan`. AddressSanitizer detects invalid memory
access and leaks; UndefinedBehaviorSanitizer detects invalid casts,
overflow and related C undefined behaviour. The script uses only base R
so the sanitizer jobs test the C layer without first building the
testthat dependency tree.

`test-fuzz.R` complements the sanitizer driver with deterministic
randomized inputs. Ordinary test runs use 300 iterations, so the suite
stays fast; the hardening workflow sets `ZUJSON_FUZZ` to 50,000. That
workflow runs on every pull request, not only on its weekly schedule, so
the larger sample is part of reviewing a change rather than something
that surfaces days later. For every generated input, parsing must either
return a value or raise a `zujson_error`, validation must return one
logical value, and raw and character entry points must agree where their
encodings are equivalent. Generated valid values must also survive a
write/parse cycle.

Finally, C changes are exercised with `gctorture(TRUE)`. It forces
collections at allocation boundaries and is the most direct check that
objects crossing the R/C boundary are protected for exactly as long as
they are needed.

## See also

- [Handle malformed or untrusted
  input](https://pedrobtz.github.io/zujson/articles/untrusted-input.md)
  for what a caller does about the failures tested here.
- [Coming from
  jsonlite](https://pedrobtz.github.io/zujson/articles/jsonlite.md) for
  the differences the differential tests pin.
