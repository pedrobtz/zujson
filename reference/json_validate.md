# Check whether input is valid JSON

Parses `x` and reports whether it succeeded, without building an R
result and without raising a condition. Use it to decide whether a
response body is worth parsing; use
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
when a failure should be an error you can read.

## Usage

``` r
json_validate(x)
```

## Arguments

- x:

  A single string of JSON text, or a raw vector of JSON bytes.

## Value

`TRUE` or `FALSE`.

## Details

This answers "is this valid JSON", which is very nearly but not exactly
"will
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
succeed". The one input where they differ is a string or key containing
an escaped NUL (`\u0000`): that is valid JSON, so this returns `TRUE`,
but no R string can hold the result, so
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
raises `zujson_parse_error`. Code that must not fail should handle the
condition from
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
rather than pre-screening with this.

## Examples

``` r
json_validate('{"a": 1}')
#> [1] TRUE
json_validate('{"a": }')
#> [1] FALSE
json_validate(charToRaw("[]"))
#> [1] TRUE
```
