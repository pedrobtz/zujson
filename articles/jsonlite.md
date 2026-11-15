# Coming from jsonlite

``` r

library(zujson)
```

This guide is for someone who knows
[jsonlite](https://CRAN.R-project.org/package=jsonlite) and is moving
code to zujson, or deciding whether to. It lists every place the two
give different results at their defaults, in parsing, writing and
failing, with the argument that brings them back into agreement where
there is one.

The functions correspond like this:

| jsonlite | zujson |
|----|----|
| `fromJSON(txt)` on a string | `json_parse(txt)` |
| `fromJSON(path)` on a file | `json_parse_file(path)` |
| `toJSON(x)` | `json_write(x)` |
| `toJSON(x, auto_unbox = TRUE)` | `json_write(x)`, which unboxes by default |
| `validate(txt)` | `json_validate(txt)` |
| `stream_in()`, `stream_out()` | [`json_parse_ndjson()`](https://pedrobtz.github.io/zujson/reference/json_parse_ndjson.md), [`json_write_ndjson()`](https://pedrobtz.github.io/zujson/reference/json_parse_ndjson.md), on a whole body |

jsonlite is much broader. Everything below is the price of a mapping
small enough to hold in your head, and all of it is pinned in the
package’s own tests, which use jsonlite as an oracle over JSON text, so
a divergence that stops being deliberate fails the suite.

Every cell in the tables below is computed by running both packages when
this page is built.

## Parsing

Most JSON reads the same way in both: objects, nulls, scalars, escapes,
surrogate pairs and the integer boundaries all agree. Four things do
not, and three of them have an opt-in that closes the gap.

| JSON | zujson | jsonlite | Opt-in that agrees |
|:---|:---|:---|:---|
| `[]` | `logical(0)` | [`list()`](https://rdrr.io/r/base/list.html) | none needed — see below |
| `[1, "a"]` | `list(1L, "a")` | `c("1", "a")` | `simplify = "coerce"` |
| `[{"a":1},{"b":2}]` | `list(list(a = 1L), list(b = 2L))` | `data.frame(a = c(1L, NA), b = c(NA, 2L))` | `data_frame = TRUE` |
| `[[1,2],[3,4]]` | `list(1:2, 3:4)` | `matrix(c(1L, 3L, 2L, 4L), nrow = 2)` | none; no matrix detection |

The record case is explicit because turning records into a data frame
changes what a missing key means, and the matrix case because JSON
carries no dimensions to infer one from.

The empty array is the one with no opt-in and no argument about it: with
no elements to take a type from, the zero-length atomic vector is as
good an answer as the empty list, and this package prefers the one that
keeps `[]` and `[1,2]` in the same family.

## Serializing

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

## Failing

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

## See also

- [`?json_parse`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
  and
  [`?json_write`](https://pedrobtz.github.io/zujson/reference/json_write.md)
  for the full mapping in each direction.
- [Testing and
  conformance](https://pedrobtz.github.io/zujson/articles/testing.md)
  for the differential tests that keep this page true.
