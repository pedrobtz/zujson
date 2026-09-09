# Report what this build of zujson contains

Returns the package version, the version of the vendored yyjson sources
it was compiled against, and the nesting depth limit the parser and
serializer both enforce.

## Usage

``` r
zujson_info()
```

## Value

A named list with `zujson`, `yyjson` and `max_depth`.

## Examples

``` r
zujson_info()
#> $zujson
#> [1] "0.1.0"
#> 
#> $yyjson
#> [1] "0.12.0"
#> 
#> $max_depth
#> [1] 1000
#> 
```
