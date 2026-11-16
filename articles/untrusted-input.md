# Handle malformed or untrusted input

``` r

library(zujson)
```

This guide is for code that parses a body it did not write: a response
from a service, a file a user uploaded. It shows how to catch a failure,
how to tell one kind from another, and which limits stop a hostile
document from exhausting the C stack or memory. It assumes you have read
[`vignette("zujson")`](https://pedrobtz.github.io/zujson/articles/zujson.md).

## Catch every failure with one handler

Every condition the package raises inherits from `zujson_error`. Wrap
the call once, and nothing zujson raises escapes as a bare error:

``` r

parse_or_null <- function(x) {
  tryCatch(json_parse(x), zujson_error = function(e) NULL)
}

parse_or_null('{"ok": true}')
#> $ok
#> [1] TRUE
parse_or_null("{bad")
#> NULL
```

## Tell the failures apart

In front of `zujson_error` sits a class that says what went wrong.
Handle the ones you can act on, and leave the rest to the general
handler.

| Class | Raised when |
|----|----|
| `zujson_parse_error` | the input is not JSON, or is JSON that R cannot hold |
| `zujson_depth_error` | nesting goes past `zujson_info()$max_depth` levels |
| `zujson_limit_error` | `data_frame = TRUE` would build more than `zujson_info()$max_df_cells` cells |
| `zujson_io_error` | [`json_parse_file()`](https://pedrobtz.github.io/zujson/reference/json_parse.md) cannot read the file |
| `zujson_write_error` | a value cannot be written, such as a date outside years 0000 to 9999 |
| `zujson_unsupported_type` | an R type has no JSON form, such as a complex or raw vector |
| `zujson_arg_error` | an argument is of the wrong type or length |

The class comes first in `class(e)`, and the message says where in the
input the problem is:

``` r

e <- tryCatch(json_parse('{"a": }'), zujson_error = function(e) e)
class(e)
#> [1] "zujson_parse_error" "zujson_error"       "error"             
#> [4] "condition"
conditionMessage(e)
#> [1] "invalid JSON at byte 6: unexpected character, expected a JSON value"
```

For NDJSON the message names the line, since a byte offset into ten
thousand records helps nobody:

``` r

json_parse_ndjson('{"id": 1}\n{"id": \n{"id": 3}\n')
#> Error:
#> ! invalid JSON on line 2 at byte 7 of that line: unexpected end of data
```

## Do not rely on validating first

[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
answers “is this JSON?”. That is nearly, but not exactly, “will
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
succeed?”. Two kinds of document are valid JSON and still cannot become
R values. The first is nesting deeper than the limit:

``` r

deep <- paste0(strrep("[", 1500), strrep("]", 1500))

json_validate(deep)
#> [1] TRUE
class(tryCatch(json_parse(deep), zujson_error = function(e) e))[1]
#> [1] "zujson_depth_error"
```

The second is a string R cannot hold, such as one with an escaped NUL:

``` r

nul <- '["a\\u0000b"]'

json_validate(nul)
#> [1] TRUE
class(tryCatch(json_parse(nul), zujson_error = function(e) e))[1]
#> [1] "zujson_parse_error"
```

So code that must not fail handles the condition from
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md).
Use
[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
when the yes or no is all you need.
[`?json_validate`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
gives the reasoning for both cases.

## The limits

[`zujson_info()`](https://pedrobtz.github.io/zujson/reference/zujson_info.md)
reports the two limits in force, with the package and yyjson versions:

``` r

str(zujson_info())
#> List of 4
#>  $ zujson      : chr "0.1.1.9000"
#>  $ yyjson      : chr "0.12.0"
#>  $ max_depth   : int 1000
#>  $ max_df_cells: num 5e+07
```

**Depth.** Building the R value is recursive, so nesting is capped at
`max_depth` levels and a deeper document raises `zujson_depth_error`
instead of overflowing the C stack. The cap is compiled in.
[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
does not apply it, because the reader underneath is iterative and RFC
8259 leaves the limit to the implementation.

**Data frame cells.** A data frame is rectangular, so records that share
no keys ask for one cell per record, per record: the size grows with the
square of the body. `max_df_cells` bounds the total for one document.
Here a limit of 10 cells refuses three records that share no keys:

``` r

withr::with_options(list(zujson.max_df_cells = 10), {
  json_parse('[{"a":1,"b":1},{"c":1,"d":1},{"e":1,"f":1}]', data_frame = TRUE)
})
#> Error:
#> ! a data frame of 3 records x 4 columns needs more than the 10 cells left of the document's 10 cell limit
```

Set `options(zujson.max_df_cells = )` to raise or lower it for the
session.

## Text must be UTF-8

Every string zujson returns is marked UTF-8, and that mark is true
because yyjson checked the bytes. Input that is not valid UTF-8 is
refused, not repaired:

``` r

latin1 <- as.raw(c(0x22, 0xE9, 0x22)) # "é" in Latin-1, between quotes
json_validate(latin1)
#> [1] FALSE
```

Convert such input with [`iconv()`](https://rdrr.io/r/base/iconv.html)
before parsing. A leading UTF-8 byte order mark is skipped and not
refused, since real services send one.

## See also

- [`?json_parse`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
  for everything the parser refuses and why.
- [Testing and
  conformance](https://pedrobtz.github.io/zujson/articles/testing.md)
  for how these paths are exercised under sanitizers and fuzzing.
