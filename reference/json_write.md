# Serialize R as JSON

`json_write()` renders an R object as JSON text. `json_write_raw()`
returns the same JSON as UTF-8 bytes, which is the form an HTTP request
body wants.

## Usage

``` r
json_write(x, pretty = FALSE, auto_unbox = TRUE)

json_write_raw(x, pretty = FALSE, auto_unbox = TRUE)
```

## Arguments

- x:

  The R object to serialize.

- pretty:

  Whether to indent the output. `FALSE` (the default) writes the compact
  form, which is what you want for a request body.

- auto_unbox:

  Whether a length-1 atomic vector becomes a bare JSON scalar (`TRUE`,
  the default) or a one-element array. Wrap a value in
  [`I()`](https://rdrr.io/r/base/AsIs.html) to keep it an array under
  `auto_unbox = TRUE`; that is the escape hatch for an API field that
  must always be a list.

## Value

`json_write()` returns a single string; `json_write_raw()` returns a raw
vector of UTF-8 bytes.

## Type mapping

|  |  |
|----|----|
| R | JSON |
| `NULL` | `null` |
| `NA`, `NaN`, `Inf` | `null` |
| `list(a = 1, b = 2)` | `{"a":1,"b":2}` |
| `list(1, 2)` | `[1,2]` |
| `c(a = 1, b = 2)` | `{"a":1,"b":2}` |
| `1:3` | `[1,2,3]` |
| `"a"` | `"a"` (see `auto_unbox`) |
| `I("a")` | `["a"]` |
| `factor` | its level, as a string |
| `Date` | `"YYYY-MM-DD"` |
| `POSIXct` | `"YYYY-MM-DDTHH:MM:SSZ"`, in UTC |
| `data.frame` | array of one object per row |
| [`list()`](https://rdrr.io/r/base/list.html) | `[]` |
| `structure(list(), names = character())` | [`{}`](https://rdrr.io/r/base/Paren.html) |

A vector or list becomes a JSON **object** when every element is named,
and an **array** otherwise. Partial names would produce keys like `""`,
which is valid JSON but almost never intended, so a partially named
vector is written as an array and its names are dropped.

Data frames are written row-oriented, because that is what an HTTP API
means by a table. To get the column-oriented form instead, strip the
class first: `json_write(as.list(df))`.

Every kind of missing value becomes `null`: JSON has no `NA`, and `NaN`
and `Infinity` are not JSON either. `POSIXct` is always written as UTC
no matter what its `tzone` says, since it is the same instant either
way, and sub-second parts are dropped.

Doubles are written compactly and always read back as the same number,
so `0.1` is `0.1` rather than `0.10000000000000001`. A double that is a
whole number is written without a decimal point at all — R has no
integer literal, so `1` is a double, and `1.0` is rejected by a schema
expecting an integer.

Complex vectors, raw vectors, functions, environments and `POSIXlt` have
no sensible JSON form and raise a `zujson_unsupported_type` error rather
than being guessed at. (`POSIXlt` is a list of 11 broken-down time
fields; convert it with
[`as.POSIXct()`](https://rdrr.io/r/base/as.POSIXlt.html) first.) A
vector carrying an unrecognised class is written as its underlying type,
which for a matrix means its values in column-major order with `dim`
dropped — matrices are not turned into nested arrays in this version.

## See also

[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
for the other direction.

## Examples

``` r
json_write(list(name = "ada", ids = 1:3, ok = TRUE))
#> [1] "{\"name\":\"ada\",\"ids\":[1,2,3],\"ok\":true}"

# length-1 vectors unbox by default; I() keeps them arrays
json_write(list(tag = "x", tags = I("x")))
#> [1] "{\"tag\":\"x\",\"tags\":[\"x\"]}"

# every atomic vector stays an array
json_write(list(tag = "x"), auto_unbox = FALSE)
#> [1] "{\"tag\":[\"x\"]}"

cat(json_write(list(a = 1, b = list(c = 2)), pretty = TRUE))
#> {
#>   "a": 1,
#>   "b": {
#>     "c": 2
#>   }
#> }

json_write(data.frame(id = 1:2, nm = c("a", "b")))
#> [1] "[{\"id\":1,\"nm\":\"a\"},{\"id\":2,\"nm\":\"b\"}]"

# bytes, ready to be an HTTP request body
json_write_raw(list(q = "search"))
#>  [1] 7b 22 71 22 3a 22 73 65 61 72 63 68 22 7d
```
