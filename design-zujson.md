# zujson Design

**Status:** v1 shipped
**Package:** `zujson`
**Purpose:** Small, portable JSON parsing and serialization for R, designed for direct reuse by `zuhttp`
**Implementation:** C with vendored yyjson
**Target:** CRAN-compatible source package
**Non-goals:** A `jsonlite` replacement, streaming/NDJSON, JSON Pointer/Patch/Schema, data frame reconstruction, custom serializer dispatch

---

## 1. Executive summary

`zujson` vendors [yyjson](https://github.com/ibireme/yyjson) and exposes a
narrow API for the two things an HTTP client does with JSON:

- turn a response body — raw bytes — into R vectors and lists;
- turn an R object into the UTF-8 bytes of a request body.

Everything else is out of scope for v1. The intended stack:

```text
                    zuhttp
                      |
          Content-Type: application/json
                      |
                 response body
                      |
                    zujson
                      |
            R vectors and lists
```

`zuhttp` should stay byte- and transport-focused and never see a `yyjson_doc`.

## 2. Why a separate package

The `zu*` family's rule is one small dependency per concern, no system
libraries, and a C core that a sibling package can reuse. JSON is the most
common response type an HTTP client meets, so it gets its own package rather
than living inside `zuhttp`.

`jsonlite` is excellent and much broader. Breadth is the cost here: `zujson`
wants a mapping small enough to state on one page and hold in your head.

## 3. Why yyjson

- C, no dependencies, MIT licensed;
- a single `.c`/`.h` pair, which makes vendoring and auditing trivial;
- an iterative (non-recursive) reader, so a hostile document cannot blow the
  stack inside the parser;
- UTF-8 validation on by default;
- shortest-round-trip double formatting, so `0.1` writes as `0.1`;
- fast enough that the R-side tree building is the bottleneck, which is the
  right place for it to be.

## 4. Public R API

Six functions. That is the whole surface.

```r
json_parse(x, simplify = TRUE)        # character or raw -> R
json_parse_raw(x, simplify = TRUE)    # raw -> R
json_parse_file(path, simplify = TRUE)
json_write(x, pretty = FALSE, auto_unbox = TRUE)      # R -> character
json_write_raw(x, pretty = FALSE, auto_unbox = TRUE)  # R -> raw
json_validate(x)                      # character or raw -> TRUE/FALSE
zujson_info()                         # build metadata
```

`json_parse()` accepts raw as well as character so the common `zuhttp` call is
`json_parse(resp_body(res))` with no conversion step. `json_write_raw()` exists
for the same reason in the other direction: a request body is bytes, and
routing it through an R string would mean an extra copy and an encoding
question that has only one right answer anyway.

## 5. JSON to R

Objects are **always** named lists. Arrays simplify to an atomic vector when
their elements agree on a type, and become a list when they do not.

### The lattice

```
numeric family:   null < logical < integer < double
strings:          a separate kind, compatible only with strings and null
null:             a wildcard -- becomes NA, never promotes
```

```
nested object or array present          -> list
string present AND non-string present   -> list
string present (strings and null only)  -> character
numeric family only                     -> logical | integer | double (max rank)
empty, or all null                      -> logical
```

| array | R type |
| --- | --- |
| `[1,2,3]` | `integer` |
| `[1,2,3,4.0]` | `double` |
| `[true,false]` | `logical` |
| `[true,1]` | `integer` |
| `["a","b"]` | `character` |
| `[1,"a"]` | `list` |
| `[true,"x"]` | `list` |
| `[1,{}]` | `list` |
| `[]`, `[null,null]` | `logical` |

**This is type-preserving, not coercing.** R's own `c()` and `jsonlite`'s
default would make `[1,2,3,"hello"]` into `c("1","2","3","hello")`, keeping the
textual value and silently destroying the type. `zujson` keeps the type and
gives up the uniform atomic shape. The alternative was considered and rejected
for v1: a response field that is usually numbers and occasionally a string is
a bug worth seeing, not one worth papering over.

### R-specific integer rules

R's `integer` is 32-bit and `NA_INTEGER` *is* `INT_MIN`, so:

- a JSON integer above `INT_MAX` promotes to `double`;
- a genuine `-2147483648` also promotes to `double`, since keeping it an
  integer would make it indistinguishable from `NA`.

### Resolved open questions

These were the questions left open in the earlier `jsx3` notes. v1's answers:

1. **Default mode** — `preserve`, as above. `coerce` is not implemented; adding
   it later is a new argument value, not a breaking change.
2. **Logical as its own kind?** No: `[true,1]` is `integer`, because `TRUE -> 1`
   is lossless.
3. **Empty array `[]`** — `logical(0)`.
4. **All-null `[null,null]`** — `c(NA, NA)`, R's convention.
5. **Matrix detection** — not in v1.
6. **N-d arrays** — not in v1.
7. **data.frame detection** — not in v1. An array of objects is a list of named
   lists.
8. **Objects** — always a named list, no exceptions.

### Valid JSON that R cannot hold

Three documents are valid JSON and still cannot become R values: a string or
key containing `\u0000` (no R string holds a NUL), one longer than `INT_MAX`
bytes, and anything nested past the depth cap. All three raise
`zujson_parse_error`, because a caller handling `zujson_error` must not be
surprised by a bare `simpleError` from the R internals — which is exactly what
`Rf_mkCharLenCE` raises if a NUL reaches it. Both guards live in `zu_mkchar()`,
the single place a CHARSXP is made, so string values and object keys cannot
drift apart.

This makes `json_validate()` and `json_parse()` disagree on precisely one
input. The NUL escape is valid JSON, so `json_validate()` says `TRUE`, and
`json_parse()` still fails; both answers are right for the questions they are
asked. `?json_validate` documents the divergence and points callers who must
not fail at handling the condition rather than pre-screening.

A leading UTF-8 BOM is **ignored**, via one shared flag set (`ZUJSON_READ_FLAGS`)
used by every read path so parse and validate cannot drift apart. RFC 8259
forbids emitting one but allows ignoring it, and real APIs emit them; failing a
response body over three leading bytes would serve nobody.

## 6. R to JSON

Two rules carry most of the mapping:

- a **fully named** vector or list becomes an object; anything else becomes an
  array;
- a length-1 atomic vector **unboxes** to a bare scalar unless `I()`-wrapped or
  `auto_unbox = FALSE`.

| R | JSON |
| --- | --- |
| `NULL` | `null` |
| `NA` / `NaN` / `Inf` (any type) | `null` |
| `list(a=1,b=2)`, `c(a=1,b=2)` | `{"a":1,"b":2}` |
| `list(1,2)`, `1:2` | `[1,2]` |
| `"x"` | `"x"` |
| `I("x")` | `["x"]` |
| `factor` | its level, as a string |
| `Date` | `"YYYY-MM-DD"` |
| `POSIXct` | `"YYYY-MM-DDTHH:MM:SSZ"`, UTC |
| `data.frame` | array of one object per row |
| `list()` | `[]` |
| `structure(list(), names=character())` | `{}` |
| `matrix` | flat array, column-major, `dim` dropped |
| complex, raw, closure, environment, `POSIXlt` | `zujson_unsupported_type` |

### Decisions worth recording

**`auto_unbox = TRUE` is the default**, unlike `jsonlite`. The package exists to
build request bodies, and `{"limit":[10]}` is wrong for almost every API that
`{"limit":10}` is right for. `I()` is the escape hatch for the genuinely
repeated field, and it is a much rarer case than the scalar one.

**Partial names produce an array, not empty keys.** `c(a=1, 2)` could be
`{"a":1,"":2}`, which is valid JSON and essentially never intended. Dropping
the names is the lesser surprise, and it is documented rather than silent.

**Names on atomic vectors are honoured.** `jsonlite` drops them. Silently
discarding data the caller attached is worse than the small asymmetry it
creates on the way back (a JSON object always parses to a named *list*).

**Whole doubles lose their decimal point.** R has no integer literal, so `1` is
a double, and yyjson's real writer emits `1.0`. A schema expecting an integer
rejects that. Any double that is a whole number within int64's range is written
as an integer. The bound is int64, not 2^53: a double that is *already* a whole
number is exactly that integer whatever its magnitude, so the conversion is
lossless; 2^53 is where consecutive integers stop being representable, which is
a different question and the wrong test here.

**Data frames are row-oriented.** That is what an HTTP API means by a table.
The column-oriented reading remains available as `json_write(as.list(df))`.

**`POSIXct` is always UTC.** It is an instant; `tzone` is a display preference.
Sub-second parts are dropped — RFC 3339 to the second is what APIs use. Both
`Date` and `POSIXct` are formatted with Howard Hinnant's civil-date algorithm
rather than a libc calendar call, so output does not vary by platform or locale.

**Unsupported types error; unrecognised classes do not.** There is no defensible
JSON for a closure or an environment, so those raise. A vector carrying a class
`zujson` has never heard of is written as its underlying type, because a new S3
class should not be a hard failure.

`POSIXlt` is the exception that proves the rule, and it raises. It is a *list*
of 11 broken-down time fields, so the permissive path would emit
`{"sec":0,"min":0,...,"gmtoff":0}` — valid JSON, and never what anyone meant by
sending a timestamp. Falling through to the underlying type is only defensible
when the underlying type still carries the value; here it does not.

A matrix does fall through, to its values in column-major order with `dim`
dropped. That is out of scope per §5 question 5 rather than an oversight, and
it is documented and tested rather than left to be discovered.

## 7. Error model

Every failure raises a condition of class

```
c(<specific>, "zujson_error", "error", "condition")
```

so a caller wrapping a whole request/response cycle handles `zujson_error` once.

| class | raised when |
| --- | --- |
| `zujson_parse_error` | input is not valid JSON (message names the byte offset) |
| `zujson_write_error` | serialization failed (e.g. a string that is not the UTF-8 it claims to be), or output exceeds a single R string |
| `zujson_io_error` | `json_parse_file()` could not read the file at all |
| `zujson_unsupported_type` | an R type or shape with no JSON form |
| `zujson_depth_error` | nesting beyond `ZUJSON_MAX_DEPTH` |
| `zujson_arg_error` | an argument failed its check before reaching C |

Conditions are built in C (`zu_stop()` in `src/zu_cond.c`) rather than
re-signalled in R, so the class is attached where the cause is known. Argument
checks in R raise the same shape, so the boundary is invisible to a caller.

Tests assert on **classes, never message text**, so wording can change without
breaking the suite.

## 8. Memory model

The single invariant, inherited from `zukomp` design §13:

> Anything holding heap state across a longjmp must be owned by R.

`zu_stop()`, `R_CheckUserInterrupt()` and every R allocator longjmp straight
past a `free()`. So a `yyjson_doc`, a `yyjson_mut_doc` and yyjson's output
buffer are each handed to a finalized external pointer (`zu_extptr_own_*`)
*before* the first thing that can jump, and released eagerly on the success
path. Finalizers clear the address first, which is what makes eager release and
a later GC pass mutually safe.

The corollary: nothing in the C layer needs a cleanup path on error, and
`zu_stop()` can be called from anywhere in either recursion.

## 9. Depth limiting

yyjson's reader is iterative, but `zujson`'s tree builders are recursive in both
directions, so an untrusted body of 100k nested arrays would walk off the C
stack before any R code saw it. `ZUJSON_MAX_DEPTH` is 1000 — far beyond what a
real API sends, far below what the smallest supported stack survives.

**Depth counts containers, not values.** The root container is level 1 and a
scalar inside it is not a level of its own, so the limit means the same thing
when parsing and when writing. Getting this wrong in the obvious way (checking
on entry to every value) makes the two directions disagree by one.

A data frame is the one value that emits **two** container levels at once — the
array of rows, and each row object — so it is charged for both. Charging it one
lets `json_write()` emit JSON that `json_parse()` then rejects, which is the
worst kind of bug this package can have: output it will not read back.

## 10. Layout and naming

```
R/{parse,write,info,utils,zujson-package}.R
src/{init,zu_cond,zu_parse,zu_write,zu_info}.c + src/zujson.h
src/vendor/yyjson/{yyjson.c,yyjson.h,LICENSE}
tools/vendor-yyjson.R
tests/testthat/
```

| layer | prefix |
| --- | --- |
| R exports | `json_` (plus `zujson_info()`) |
| R internals | `zu_` |
| C internals | `zu_` |
| `.Call` entry points | `zujson_` |

`json_parse` / `json_write` mirrors `zuxml`'s `xml_parse` / `xml_write`, so the
family reads consistently from `zuhttp`.

**Adding a C source file means editing `OBJECTS` in `src/Makevars` by hand.** R
auto-compiles only `src/*.c`, yyjson lives in a subdirectory, and a
`$(wildcard)` would force `SystemRequirements: GNU make`. A file that is not in
`OBJECTS` is silently not built.

## 11. Vendoring

`src/vendor/yyjson/` is yyjson 0.12.0, unmodified, refreshed by
`tools/vendor-yyjson.R`. Nothing is disabled at compile time: UTF-8 validation
and the reader's number handling are exactly what make it safe to point at an
untrusted body.

Vendored code is never edited in place. The version is asserted from
`zujson_info()` and from `test-info.R`, so an upstream bump has to be
deliberate — `tools/` is not installed, so the test carries the literal.

## 12. Testing

Conventions inherited from `zukomp`:

- self-sufficient tests that build their own inputs inside `test_that()`;
- assertions on condition classes, never message text;
- order independence — `devtools::test(shuffle = TRUE)` is part of done;
- `expect_json()` asserts on exact output bytes, because that is what a
  serializer is for;
- `expect_roundtrip()` uses `identical()`, so an integer quietly becoming a
  double fails.

`test-conditions.R` re-runs failing calls fifty times against successful ones,
which is what would catch the memory model of §8 being wrong.

Deliberately outside the suite, for later: ASan/UBSan and valgrind jobs, and
fuzzing the parser against a corpus. PROTECT discipline is currently checked
with `gctorture(TRUE)` over both directions.

## 13. Acceptance criteria for v1

1. `R CMD check --as-cran` clean — 0 errors, 0 warnings, 0 notes. ✅
2. Suite green under `shuffle = TRUE`. ✅
3. Both directions clean under `gctorture(TRUE)`. ✅
4. No system library; builds with the ordinary R toolchain. ✅
5. Every documented mapping row has a test. ✅
6. Every raised condition inherits `zujson_error`. ✅
7. Untrusted input cannot exhaust the C stack. ✅
8. Response bytes in and request bytes out with no string detour. ✅
9. **Used by a real `zuhttp`.** ❌ — open, deliberately: `zuhttp` is still an
   empty skeleton. The shapes are covered by `test-roundtrip.R`, but the
   criterion cannot close until there is something to integrate with.

## 14. What comes after v1

Not more of §13.9. In rough order:

- `simplify = "coerce"` as an opt-in mode (§5, question 1);
- data frame simplification on parse, which is the one asymmetry users will
  actually ask about;
- a public C API through `LinkingTo: zujson`, so `zuhttp` can parse from C —
  worth doing only once a caller exists, following `zukomp`'s registered
  C-callable pattern rather than exporting yyjson types;
- fuzzing and sanitizer CI jobs;
- NDJSON, if a streaming API ever needs it.
