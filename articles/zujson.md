# Getting started with zujson

``` r

library(zujson)
```

`zujson` exists to serve `zuhttp`: parsing a response body and building
a request body are the two things it is designed around. That is why it
is narrower than `jsonlite`, and why the type mapping below is part of
the contract rather than an implementation detail — what goes in and
what comes out should both be predictable.

Ten functions, and that is the whole package.

## Parsing

[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
accepts a character string or a raw vector;
[`json_parse_raw()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
and
[`json_parse_file()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
are the explicit forms, and
[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
answers the question without building anything.

``` r

json_parse('{"ok": true, "ids": [1, 2, 3]}')
#> $ok
#> [1] TRUE
#> 
#> $ids
#> [1] 1 2 3

json_validate('{"a": 1}')
#> [1] TRUE
json_validate("{bad")
#> [1] FALSE
```

JSON objects always become named lists. Arrays become an atomic vector
when their elements agree on a type and a list when they do not, so the
type is never coerced away:

``` r

json_parse("[1, 2, 3]")
#> [1] 1 2 3
json_parse('[1, "a"]')
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "a"
```

The mapping in full:

| JSON                 | R                         |
|----------------------|---------------------------|
| `{"a": 1}`           | `list(a = 1L)`            |
| `[1, 2, 3]`          | `1:3`                     |
| `[1, "a"]`           | `list(1L, "a")`           |
| `[]`, `[null, null]` | `logical(0)`, `c(NA, NA)` |
| `null`               | `NULL`                    |

## Simplification modes

`simplify` decides what happens to an array whose elements do not share
a kind. That is the *only* thing it changes: the promotions within the
numeric family are the same in every mode, and a nested container is
never coerced away.

``` r

json_parse('[1, "a"]')                        # preserve, the default
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "a"
json_parse('[1, "a"]', simplify = "coerce")
#> [1] "1" "a"
json_parse('[1, "a"]', simplify = "none")
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "a"
```

`preserve` keeps the type and gives up the uniform shape, on the view
that a field which is usually a number and occasionally a string is a
bug worth seeing rather than one worth papering over. `coerce` is the
opt-in for callers who would rather have the vector. It follows R’s own
promotion exactly, so the strings are the ones
[`as.character()`](https://rdrr.io/r/base/character.html) gives — which
matters more than it sounds, because a hand-rolled format would not
agree with R at 15 significant digits:

``` r

json_parse('[0.3333333333333333, "a"]', simplify = "coerce")
#> [1] "0.333333333333333" "a"
identical(json_parse('[1, null, "a"]', simplify = "coerce"), c("1", NA, "a"))
#> [1] TRUE
```

Note that JSON `null` becomes `NA` there and never the string `"NA"`.

`TRUE` and `FALSE` remain exact synonyms for `"preserve"` and `"none"`,
so nothing written against the original API changes meaning.

## Data frames

`data_frame = TRUE` turns any non-empty array whose elements are all
objects — the shape an API uses for a list of records — into a data
frame.

``` r

json_parse('[{"id":1,"nm":"a"},{"id":2,"nm":"b"}]', data_frame = TRUE)
#>   id nm
#> 1  1  a
#> 2  2  b
```

Records are not required to agree on their keys. Columns are the union,
in the order first seen, and a record missing a key contributes `NA`, so
the result is rectangular however ragged the input:

``` r

json_parse('[{"a":1},{"b":2},{"a":3,"c":4}]', data_frame = TRUE)
#>    a  b  c
#> 1  1 NA NA
#> 2 NA  2 NA
#> 3  3 NA  4
```

Each column is simplified with the active `simplify` mode, so the two
features compose rather than competing:

``` r

str(json_parse('[{"v":1},{"v":"x"}]', data_frame = TRUE)$v)
#> List of 2
#>  $ : int 1
#>  $ : chr "x"
str(json_parse('[{"v":1},{"v":"x"}]', data_frame = TRUE, simplify = "coerce")$v)
#>  chr [1:2] "1" "x"
```

Anything that is not a non-empty array of objects is left exactly as it
was, and the reconstruction applies wherever such an array appears,
however deeply nested.

``` r

str(json_parse('{"rows":[{"a":1},{"a":2}]}', data_frame = TRUE))
#> List of 1
#>  $ rows:'data.frame':    2 obs. of  1 variable:
#>   ..$ a: int [1:2] 1 2
```

## Serializing

A **fully named** vector or list becomes an object; anything else
becomes an array. Length-1 atomic vectors unbox to bare scalars by
default, so wrap one in [`I()`](https://rdrr.io/r/base/AsIs.html) when a
field must stay an array.

``` r

json_write(list(a = 1, b = 2))
#> [1] "{\"a\":1,\"b\":2}"
json_write(c(a = 1, b = 2))
#> [1] "{\"a\":1,\"b\":2}"
json_write(list(1, 2))
#> [1] "[1,2]"

json_write("x")
#> [1] "\"x\""
json_write(I("x"))
#> [1] "[\"x\"]"
```

| R                    | JSON                  |
|----------------------|-----------------------|
| `list(a = 1, b = 2)` | `{"a":1,"b":2}`       |
| `c(a = 1, b = 2)`    | `{"a":1,"b":2}`       |
| `list(1, 2)`         | `[1,2]`               |
| `"x"` / `I("x")`     | `"x"` / `["x"]`       |
| `NA`, `NaN`, `Inf`   | `null`                |
| `Date`, `POSIXct`    | ISO 8601 strings, UTC |
| `data.frame`         | one object per row    |

``` r

json_write(list(when = as.Date("2026-09-08"), missing = NA, ratio = Inf))
#> [1] "{\"when\":\"2026-09-08\",\"missing\":null,\"ratio\":null}"
```

[`?json_parse`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
and
[`?json_write`](https://pedrobtz.github.io/zujson/reference/json_write.md)
carry the same tables.

## Raw bytes, both directions

A response body arrives as raw bytes and a request body should leave as
raw bytes. Going through a character string in between would mean an
encoding round trip that neither side asked for, so the raw path is
direct:

``` r

body <- json_write_raw(list(q = "cats"))
body
#>  [1] 7b 22 71 22 3a 22 63 61 74 73 22 7d

json_parse(body)
#> $q
#> [1] "cats"
```

## NDJSON

NDJSON (`application/x-ndjson`) is one JSON value per line — the shape
of log tails, change feeds and bulk uploads.

``` r

json_write_ndjson(data.frame(id = 1:2, ok = c(TRUE, FALSE)))
#> [1] "{\"id\":1,\"ok\":true}\n{\"id\":2,\"ok\":false}\n"

json_parse_ndjson('{"id":1}\n{"id":2}\n')
#> [[1]]
#> [[1]]$id
#> [1] 1
#> 
#> 
#> [[2]]
#> [[2]]$id
#> [1] 2
```

[`json_write_ndjson_raw()`](https://pedrobtz.github.io/zujson/reference/json_parse_ndjson.md)
is the raw-bytes form.

## Safety

Parsing is meant to be pointed at an untrusted response body. yyjson
validates UTF-8, and nesting beyond 1000 levels is rejected with a
structured condition rather than walking off the C stack.

[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
does **not** apply that cap, and deliberately: RFC 8259 leaves any depth
limit to the implementation, so a deeply nested document is still valid
JSON, and the reader underneath is iterative — a million nested arrays
validate in milliseconds without touching the C stack. The cap protects
the recursive step that builds the R value, which validation never
reaches. So the two can differ:

``` r

deep <- paste0(strrep("[", 1500), strrep("]", 1500))

json_validate(deep)
#> [1] TRUE
class(tryCatch(json_parse(deep), error = function(e) e))
#> [1] "zujson_depth_error" "zujson_error"       "error"             
#> [4] "condition"
```

That is the second of exactly two cases where a document passes
[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
and still fails
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md);
the other is a string R cannot hold, such as one containing an escaped
NUL. Both are listed in
[`?json_validate`](https://pedrobtz.github.io/zujson/reference/json_validate.md),
and both are why code that must not fail should handle the condition
from
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
rather than pre-screening.

Every failure the package raises inherits from `zujson_error`, so one
handler catches all of them:

``` r

tryCatch(json_parse("{bad"), zujson_error = function(e) conditionMessage(e))
#> [1] "invalid JSON at byte 1: unexpected character, expected a string key"

class(tryCatch(json_parse("{bad"), zujson_error = function(e) e))
#> [1] "zujson_parse_error" "zujson_error"       "error"             
#> [4] "condition"
```

[`zujson_info()`](https://pedrobtz.github.io/zujson/reference/zujson_info.md)
reports the build and the vendored yyjson version:

``` r

zujson_info()
#> $zujson
#> [1] "0.0.0.9000"
#> 
#> $yyjson
#> [1] "0.12.0"
#> 
#> $max_depth
#> [1] 1000
#> 
#> $max_df_cells
#> [1] 5e+07
```

## Conformance

Claims about what a parser rejects are worth little without an external
check, so the package is run against
[JSONTestSuite](https://github.com/nst/JSONTestSuite) — the standard
corpus for exactly this question. Its files are named by what a parser
must do: `y_` must be accepted, `n_` must be rejected, and `i_` is left
to the implementation.

``` r
# tools/jsontestsuite.R, against a pinned upstream commit
y_ must be accepted           95 files,   0 wrong
n_ must be rejected          188 files,   0 wrong
i_ implementation-defined     35 files,  12 accepted,  23 rejected
318 parsing files, 0 wrong
```

Every file is handed to
[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
as **raw bytes**. Reading them as text would be wrong twice over: the
suite is full of deliberately invalid UTF-8, which a text read mangles,
and of embedded NULs, which no R string can carry. Bytes are also what a
response body actually is.

### The implementation-defined cases

The 35 `i_` files are where conforming parsers legitimately disagree, so
they are the interesting ones. The answers here follow a single split:
**generous about numbers, strict about text.**

A number outside what a `double` can hold still has a well-defined
nearest value, and R’s own reader already agrees what it is — so the
document is read and the number is converted. Refusing the whole body
over one absurd value would be a wildly disproportionate failure for an
HTTP client.

``` r

json_parse("[123123e100000]")   # overflows: Inf, as as.numeric() gives
#> [1] Inf
json_parse("[123e-10000000]")   # underflows: 0
#> [1] 0
json_parse("[100000000000000000000]") # wider than int64: nearest double
#> [1] 1e+20
```

That covers ten of the twelve acceptances: five overflow to `±Inf`, two
underflow to `0`, and three are integers too wide for `int64`.

Text is the opposite. Every string that comes back is marked as UTF-8,
and that mark is only honest because yyjson validated the bytes.
Accepting malformed text would mean handing back an R string that claims
an encoding it does not have — so all 23 rejections are text that is not
valid UTF-8, in three groups.

Eleven involve surrogates that do not form a valid pair — ten written as
`\uXXXX` escapes, one encoded straight into the bytes. A surrogate is
only meaningful as half of a pair, and an unpaired one encodes no
character:

``` r

json_validate('["\\ud800"]')        # lone high surrogate
#> [1] FALSE
json_validate('["\\uDd1e\\uD834"]') # a valid pair, inverted
#> [1] FALSE
json_validate('["\\ud83d\\ude02"]') # a correct pair: fine
#> [1] TRUE
```

Nine are invalid UTF-8 byte sequences — truncated characters, overlong
encodings, stray continuation bytes, Latin-1 text mislabelled as JSON:

``` r

json_validate(as.raw(c(0x22, 0xC0, 0xAF, 0x22))) # overlong encoding of "/"
#> [1] FALSE
json_validate(as.raw(c(0x22, 0xE9, 0x22)))       # Latin-1 e-acute, not UTF-8
#> [1] FALSE
```

The last three are UTF-16, with and without a byte order mark. RFC 8259
is explicit that JSON exchanged between systems is UTF-8, so these are
not JSON this package reads; convert with
[`iconv()`](https://rdrr.io/r/base/iconv.html) first if you have one.

``` r

json_validate(as.raw(c(0xFF, 0xFE, 0x22, 0x00, 0x61, 0x00, 0x22, 0x00)))
#> [1] FALSE
```

The remaining two acceptances are structural rather than textual. 500
nested arrays are fine, because the depth cap is 1000 — the cap exists
to protect the C stack, not to second-guess the sender. And a UTF-8 byte
order mark is skipped rather than rejected, because RFC 8259 forbids
*emitting* one but allows ignoring it, and real APIs emit them anyway.

``` r

json_validate(paste0(strrep("[", 500), strrep("]", 500)))
#> [1] TRUE
json_parse(as.raw(c(0xEF, 0xBB, 0xBF, 0x7B, 0x7D)))  # BOM, then {}
#> named list()
```

## What it deliberately does not do

No matrix or N-d array simplification, no incremental streaming yet, no
JSON pointer or patch, no custom serializers. Data frame reconstruction
is opt-in rather than absent, and stays off by default so that the type
mapping above is what you get unless you ask for something else.

## How it differs from jsonlite

`jsonlite` is excellent and much broader. Everything below is the price
of a mapping small enough to hold in your head, not an oversight, and
all of it is pinned in the package’s own tests — which use `jsonlite` as
an oracle over JSON text, so a divergence that stops being deliberate
fails the suite.

Every cell in the tables below is computed by running both packages when
this page is built, so none of it can quietly go stale.

### Parsing

Most JSON reads the same way in both: objects, nulls, scalars, escapes,
surrogate pairs and the integer boundaries all agree. Four things do
not, and three of them have an opt-in that closes the gap.

| JSON | zujson | jsonlite | Opt-in that agrees |
|:---|:---|:---|:---|
| `[]` | `logical(0)` | [`list()`](https://rdrr.io/r/base/list.html) | none needed — see below |
| `[1, "a"]` | `list(1L, "a")` | `c("1", "a")` | `simplify = "coerce"` |
| `[{"a":1},{"b":2}]` | `list(list(a = 1L), list(b = 2L))` | `data.frame(a = c(1L, NA), b = c(NA, 2L))` | `data_frame = TRUE` |
| `[[1,2],[3,4]]` | `list(1:2, 3:4)` | `matrix(c(1L, 3L, 2L, 4L), nrow = 2)` | none; no matrix detection |

The empty array is the one with no opt-in and no argument about it: with
no elements to take a type from, the zero-length atomic vector is as
good an answer as the empty list, and this package prefers the one that
keeps `[]` and `[1,2]` in the same family.

### Serializing

This is where the two differ most, because `toJSON()` has a dozen
arguments shaping its output and
[`json_write()`](https://pedrobtz.github.io/zujson/reference/json_write.md)
has two.

| R value | zujson | jsonlite, at its defaults |
|:---|:---|:---|
| `35` | `35` | `[35]` |
| `c(a = 1, b = 2)` | `{"a":1,"b":2}` | `[1,2]` |
| `c(1, NA, Inf)` | `[1,null,null]` | `[1,"NA","Inf"]` |
| `pi` | `3.141592653589793` | `[3.1416]` |
| `NULL` | `null` | [`{}`](https://rdrr.io/r/base/Paren.html) |
| `as.POSIXct("2013-06-17 22:33:44", tz = "UTC")` | `"2013-06-17T22:33:44Z"` | `["2013-06-17 22:33:44"]` |
| `matrix(1:4, 2)` | `[1,2,3,4]` | `[[1,3],[2,4]]` |
| `complex(real = 2, imaginary = 2)` | `error: zujson_unsupported_type` | `["2+2i"]` |
| `charToRaw("bla")` | `error: zujson_unsupported_type` | `["Ymxh"]` |
| `as.POSIXlt("2013-06-17 22:33:44", tz = "UTC")` | `error: zujson_unsupported_type` | `["2013-06-17 22:33:44"]` |

Four of those are worth a sentence.

The unboxing defaults are **opposite**:
[`json_write()`](https://pedrobtz.github.io/zujson/reference/json_write.md)
unboxes a length-1 vector and `toJSON()` does not, which is the first
thing to trip over when porting code. A **named atomic vector** is an
object here and an array there, and this is the one with no argument
that reconciles it — `toJSON()` drops vector names unless asked with
`keep_vec_names`, which it also warns about. Every **missing or
non-finite** value is `null` here, where `toJSON()`’s default makes a
numeric `NA` the *string* `"NA"` while a character or logical `NA`
becomes `null`. And **doubles** are written so they read back as the
same number, rather than rounded to four digits.

The refusals at the bottom of the table are deliberate: a complex
number, a raw vector and a `POSIXlt` have no obvious JSON form, so they
raise `zujson_unsupported_type` instead of being guessed at. A data
frame column that is itself a data frame is refused for the same reason.
`POSIXct` is always UTC, which is the same instant whatever `tzone`
says.

### Failing

The divergence that matters most to a client: every failure here is a
typed condition rather than a bare `simpleError`, so one handler catches
the lot and can still tell the cases apart.

| Input | zujson | jsonlite |
|:---|:---|:---|
| `"{bad"` | `zujson_parse_error` | `simpleError` |
| an escaped NUL, `"\u0000"` | `zujson_parse_error` | silently truncates to `a` |
| nesting 1500 deep | `zujson_depth_error` | C stack overflow |
| a URL or file path | never read; [`json_parse_file()`](https://pedrobtz.github.io/zujson/reference/json_parse.md) is explicit | fetched or read |

The middle two are the ones to notice. An escaped NUL is valid JSON that
no R string can hold, so refusing it is the only honest answer —
returning a silently shortened string loses data without saying so. And
the depth cap turns what would be a C stack overflow into a condition
you can catch, which is what makes the parser safe to point at a body
you did not write.

## Related

`zujson` is part of the `zu*` family:
[zukomp](https://github.com/pedrobtz/zukomp) for compression,
[zuxml](https://github.com/pedrobtz/zuxml) for XML,
[zuyaml](https://github.com/pedrobtz/zuyaml) for YAML, and `zuhttp` for
the HTTP client that uses them.
