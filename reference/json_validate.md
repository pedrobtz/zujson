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

A length-1 `logical`, never `NA`: `TRUE` when `x` is well-formed JSON by
the reader's rules, `FALSE` otherwise. `NA_character_` is `FALSE` rather
than `NA`. A `TRUE` is not a promise that
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
will succeed – the two cases above are valid JSON that this package
cannot turn into an R value.

## Details

This answers "is this valid JSON", which is very nearly but not exactly
"will
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
succeed". The two come apart on JSON that is valid and still cannot
become an R value, of which there are two kinds:

- a string or key R cannot hold: one containing an escaped NUL
  (`\u0000`), or one longer than `.Machine$integer.max` bytes.
  [`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
  raises `zujson_parse_error`.

- nesting deeper than 1000 levels. RFC 8259 leaves any depth limit to
  the implementation, so such a document is still valid JSON.
  [`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
  raises `zujson_depth_error`, because its recursive tree builder has a
  C stack to protect; the reader underneath it is iterative and does
  not.

This function returns `TRUE` for both, and is right to: it is asked
whether the bytes are JSON, not whether this package can materialise
them. Code that must not fail should handle the condition from
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
