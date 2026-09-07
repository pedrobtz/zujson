# zujson

<!-- badges: start -->
<!-- badges: end -->

`zujson` converts between JSON and ordinary R vectors and lists. It vendors
[yyjson](https://github.com/ibireme/yyjson) and needs no system JSON library.

It exists to serve `zuhttp`: parsing a response body and building a request
body are the two things it is designed around, and it is deliberately narrower
than `jsonlite`.

## Installation

```r
# install.packages("pak")
pak::pak("pedrobtz/zujson")
```

## Usage

Six functions, and that is the whole package.

```r
library(zujson)

# JSON -> R
json_parse('{"ok": true, "ids": [1, 2, 3]}')
#> $ok
#> [1] TRUE
#>
#> $ids
#> [1] 1 2 3

# R -> JSON
json_write(list(query = "cats", limit = 10L))
#> [1] "{\"query\":\"cats\",\"limit\":10}"
```

A response body arrives as raw bytes, and a request body should leave as raw
bytes, so both directions take and return them without a detour through a
string:

```r
json_parse(response_bytes)          # raw vector in, R object out
json_write_raw(list(q = "cats"))    # R object in, UTF-8 bytes out
```

The rest: `json_parse_raw()`, `json_parse_file()` and `json_validate()`.

## What the mapping is

JSON objects always become named lists. JSON arrays become an atomic vector
when their elements agree on a type, and a list when they do not — the type is
never coerced away, so `[1, "a"]` is a list rather than `c("1", "a")`.

| JSON | R |
| --- | --- |
| `{"a": 1}` | `list(a = 1L)` |
| `[1, 2, 3]` | `1:3` |
| `[1, "a"]` | `list(1L, "a")` |
| `[]`, `[null, null]` | `logical(0)`, `c(NA, NA)` |
| `null` | `NULL` |

Going the other way, a **fully named** vector or list becomes an object and
anything else becomes an array. Length-1 atomic vectors unbox to bare scalars
by default; wrap one in `I()` when a field must stay an array.

| R | JSON |
| --- | --- |
| `list(a = 1, b = 2)` | `{"a":1,"b":2}` |
| `c(a = 1, b = 2)` | `{"a":1,"b":2}` |
| `list(1, 2)` | `[1,2]` |
| `"x"` / `I("x")` | `"x"` / `["x"]` |
| `NA`, `NaN`, `Inf` | `null` |
| `Date`, `POSIXct` | ISO 8601 strings, UTC |
| `data.frame` | one object per row |

`?json_parse` and `?json_write` carry the full tables.

## What it deliberately does not do

No data frame reconstruction on parse, no matrix or N-d array simplification,
no streaming or NDJSON, no JSON pointer or patch, no custom serializers. `v1`
is the JSON an HTTP client needs and nothing else.

## Safety

Parsing is meant to be pointed at an untrusted response body: yyjson validates
UTF-8, and nesting beyond 1000 levels is rejected with a structured condition
rather than walking off the C stack. Every failure the package raises inherits
from `zujson_error`, so one handler catches all of them.

```r
tryCatch(json_parse(body), zujson_error = function(e) NULL)
```

## Related

`zujson` is part of the `zu*` family: [zukomp](https://github.com/pedrobtz/zukomp)
for compression, `zuxml` for XML, and `zuhttp` for the HTTP client that uses
them.
