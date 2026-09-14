# Parse JSON into R

`json_parse()` turns JSON text, or the raw bytes of an HTTP response
body, into ordinary R vectors and lists. `json_parse_raw()` and
`json_parse_file()` are the same parser reached directly, for when the
input type is already known.

## Usage

``` r
json_parse(x, simplify = TRUE, data_frame = FALSE)

json_parse_raw(x, simplify = TRUE, data_frame = FALSE)

json_parse_file(path, simplify = TRUE, data_frame = FALSE)
```

## Arguments

- x:

  For `json_parse()`, a single string of JSON text or a raw vector of
  UTF-8 JSON bytes. For `json_parse_raw()`, a raw vector.

- simplify:

  How to simplify JSON arrays to atomic vectors: one of `"preserve"`
  (the default), `"coerce"` or `"none"`. `TRUE` and `FALSE` are accepted
  as synonyms for `"preserve"` and `"none"`. See *Simplification modes*
  below.

- data_frame:

  Whether an array of objects becomes a data frame. `FALSE` by default,
  in which case it stays a list of named lists. See *Data frames* below.

- path:

  Path to a file containing JSON.

## Value

The parsed R object.

## Type mapping

JSON objects always become named lists. JSON arrays become an atomic
vector when every element agrees on a type and a list otherwise:

|                      |                                          |
|----------------------|------------------------------------------|
| JSON                 | R                                        |
| `{"a": 1}`           | named `list`                             |
| `[1, 2, 3]`          | `integer`                                |
| `[1, 2.5]`           | `double`                                 |
| `[true, false]`      | `logical`                                |
| `["a", "b"]`         | `character`                              |
| `[1, "a"]`           | `list` (no common type without coercing) |
| `[1, {}]`            | `list` (nested container)                |
| `[]`, `[null, null]` | `logical`                                |
| `null`               | `NULL`                                   |

Numbers become `integer` when they fit in R's 32-bit integer and
`double` otherwise. A number too large for any finite `double` becomes
`Inf` rather than an error: RFC 8259 sets no limit on the magnitude of a
number, so `1e309` is valid JSON, and the value is the one
[`as.numeric()`](https://rdrr.io/r/base/numeric.html) gives the same
token. A `null` inside an array being simplified becomes `NA`; a `null`
anywhere else becomes `NULL`. Strings arrive as UTF-8.

## Simplification modes

`simplify` picks what happens to an array whose elements do not share a
kind. The three modes agree everywhere else, including the promotions
*within* the numeric family (`[true, 1]` is `c(1L, 1L)` in all of them):

|  |  |
|----|----|
| mode | `[1, "a"]` becomes |
| `"preserve"`, or `TRUE` (default) | `list(1L, "a")` |
| `"coerce"` | `c("1", "a")` |
| `"none"`, or `FALSE` | `list(1L, "a")`, and every other array is a list too |

`preserve` keeps the type and gives up the uniform shape, on the view
that a field which is usually a number and occasionally a string is a
bug worth seeing. `coerce` is the opt-in for callers who would rather
have the vector: it follows R's own promotion, so the strings are
exactly what [`as.character()`](https://rdrr.io/r/base/character.html)
produces. A nested object or array is never coerced away.

## Data frames

`data_frame = TRUE` turns any non-empty array whose elements are *all*
objects into a data frame. Columns are the union of the keys in the
order first seen, so the result is rectangular however ragged the
records are. A record missing a key contributes `NA` in an atomic column
and `NULL` in a list column – the same as an explicit JSON `null` in
either case, because "absent" and "null" are one thing once the value is
in a column. Each column is then simplified with the active `simplify`
mode, so a column of mixed kinds is a list column under `preserve` and a
character column under `coerce`. It applies wherever such an array
appears, however deeply nested.

`simplify = "none"` takes precedence: it is the mode that guarantees
every JSON array arrives as an R list, and a data frame is not one. The
two options are not combined, and `data_frame = TRUE` is ignored under
it.

Two limits apply, both raising a structured condition rather than a bare
error. An object with the same key twice cannot become a row – a column
has one cell per record – so it raises `zujson_parse_error` instead of
silently keeping one of the values; plain parsing, which puts both in a
list, is unaffected. And because the frame is rectangular, its size is
set by the union of the keys rather than by the length of the body:
records that share no keys at all would ask for one cell per record *per
record*, and no limit on the size of the body can stand in for a limit
on that, because the growth is quadratic in it. More than
`zujson_info()$max_df_cells` cells raises `zujson_limit_error`. The
default is 50 million – clear of any real tabular response, and far
below what a hostile one reaches – and `options(zujson.max_df_cells = )`
changes it for the session.

Nesting deeper than 1000 levels is rejected with a `zujson_depth_error`,
which is what makes the parser safe to point at an untrusted response
body.

A leading UTF-8 byte order mark is ignored rather than rejected: RFC
8259 forbids emitting one but allows ignoring it, and real APIs emit
them. The bare literals `Infinity`, `-Infinity` and `NaN` are not JSON
and stay rejected, which is a separate question from the magnitude of a
number that *is* written as one.

Two *further* things are valid JSON and still cannot become R values,
and both raise `zujson_parse_error` rather than a bare error, so a
caller handling `zujson_error` catches them alongside everything else: a
string or key containing an escaped NUL (`\u0000`), which no R string
can hold, and one longer than `.Machine$integer.max` bytes.
`json_parse_file()` additionally raises `zujson_io_error` when the file
cannot be read at all, which is a different problem from its contents
not being JSON.

## See also

[`json_write()`](https://pedrobtz.github.io/zujson/reference/json_write.md)
for the other direction,
[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
to check without building a result.

## Examples

``` r
json_parse('{"ok": true, "ids": [1, 2, 3]}')
#> $ok
#> [1] TRUE
#> 
#> $ids
#> [1] 1 2 3
#> 

# arrays that have no common type stay lists
json_parse('[1, "a"]')
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "a"
#> 

# raw bytes, as an HTTP response body arrives
json_parse(charToRaw('{"ok": true}'))
#> $ok
#> [1] TRUE
#> 

# no simplification at all
json_parse('[1, 2, 3]', simplify = FALSE)
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] 2
#> 
#> [[3]]
#> [1] 3
#> 

# coerce across kinds instead of keeping the type
json_parse('[1, "a"]', simplify = "coerce")
#> [1] "1" "a"

# a number past the range of a double is Inf, not a parse failure
json_parse("[1e309]")
#> [1] Inf

# an array of records, as a data frame
json_parse('[{"id":1,"nm":"a"},{"id":2,"nm":"b"}]', data_frame = TRUE)
#>   id nm
#> 1  1  a
#> 2  2  b

json_parse_raw(charToRaw('[1, 2, 3]'))
#> [1] 1 2 3

path <- tempfile(fileext = ".json")
writeLines('{"a": [1, 2]}', path)
json_parse_file(path)
#> $a
#> [1] 1 2
#> 
unlink(path)
```
