# zujson

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/pedrobtz/zujson/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zujson/actions/workflows/R-CMD-check.yaml)
[![hardening](https://github.com/pedrobtz/zujson/actions/workflows/hardening.yaml/badge.svg)](https://github.com/pedrobtz/zujson/actions/workflows/hardening.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zujson/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zujson/actions/workflows/coverage.yaml)
<!-- badges: end -->

zujson converts between JSON and ordinary R vectors and lists, using vendored
[yyjson](https://github.com/ibireme/yyjson) sources, so no system JSON library
is required. It exists to serve `zuhttp`: parsing a response body and building a
request body are the two things it is designed around, which makes it
deliberately narrower than `jsonlite`, with a type mapping that is fully documented.

## Installation

Install the development version from GitHub:

``` r
# install.packages("pak")
pak::pak("pedrobtz/zujson")
```

## Usage

`json_parse()` turns JSON into R objects. An array becomes an atomic vector when
its elements agree on a type, and a list when they do not — the type is never
coerced away.

``` r
library(zujson)

json_parse('{"ok": true, "ids": [1, 2, 3]}')
#> $ok
#> [1] TRUE
#> 
#> $ids
#> [1] 1 2 3
```

`json_write()` goes the other way. A fully named vector or list becomes an
object, anything else becomes an array.

``` r
json_write(list(query = "cats", limit = 10L))
#> [1] "{\"query\":\"cats\",\"limit\":10}"
```

A response body arrives as raw bytes and a request body should leave as raw
bytes, so both directions take and return them without a detour through a
string:

``` r
json_write_raw(list(q = "cats"))
#>  [1] 7b 22 71 22 3a 22 63 61 74 73 22 7d

json_parse(json_write_raw(list(q = "cats")))
#> $q
#> [1] "cats"
```

`json_parse_ndjson()` and `json_write_ndjson()` handle
`application/x-ndjson`; `json_parse_file()`, `json_parse_raw()`,
`json_validate()` and `json_write_ndjson_raw()` round out the set. The [getting
started article](https://pedrobtz.github.io/zujson/articles/zujson.html) carries
the full type mapping in both directions, the safety limits, and what the
package deliberately does not do.
