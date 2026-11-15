# Get started with zujson

``` r

library(zujson)
```

We take the kind of JSON body an API returns, read it into R, write some
of it back out, and see what happens when a body is broken. By the end
you will have met the seven functions that do most of the work, and the
rule that decides what each JSON value becomes in R. The full type
mapping, the limits and the differences from jsonlite are left to the
help pages and the articles listed at the end.

## Parse a response body

Here is a small response: a count, a cursor that is `null`, and two
records.

``` r

body <- '{
  "total": 2,
  "cursor": null,
  "items": [
    {"id": 1, "name": "Ada", "tags": ["admin", "dev"], "score": 9.5},
    {"id": 2, "name": "Grace", "tags": [], "score": null}
  ]
}'
```

[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
turns it into R. Look at what each kind of JSON value has become:

``` r

res <- json_parse(body)
str(res)
#> List of 3
#>  $ total : int 2
#>  $ cursor: NULL
#>  $ items :List of 2
#>   ..$ :List of 4
#>   .. ..$ id   : int 1
#>   .. ..$ name : chr "Ada"
#>   .. ..$ tags : chr [1:2] "admin" "dev"
#>   .. ..$ score: num 9.5
#>   ..$ :List of 4
#>   .. ..$ id   : int 2
#>   .. ..$ name : chr "Grace"
#>   .. ..$ tags : logi(0) 
#>   .. ..$ score: NULL
```

A JSON **object** is a named list, and `null` is `NULL`. A JSON
**array** is an atomic vector when its elements are all strings, all
numbers or all logical values, which is why Ada’s `tags` is a character
vector. Any other array is a list, which is why `items`, an array of
objects, is a list of two records. Grace’s empty `tags` has no element
to take a type from, and is an empty logical vector. A whole number is
an integer, and any other number a double.

The type of a value is never changed to make a vector. An array that
mixes numbers and strings stays a list, with the number still a number:

``` r

str(json_parse('[1, "Ada"]'))
#> List of 2
#>  $ : int 1
#>  $ : chr "Ada"
```

[`?json_parse`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
has the complete mapping, and the `simplify` argument that changes this
rule.

## Get records as a data frame

An array of objects is how an API sends a table. With
`data_frame = TRUE`,
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
builds a data frame from every such array, wherever it sits in the
document. Here it is `items`:

``` r

json_parse(body, data_frame = TRUE)$items
#>   id  name       tags score
#> 1  1   Ada admin, dev   9.5
#> 2  2 Grace               NA
```

Each key is a column. `score` was `null` for Grace and is `NA` here, and
`tags`, which holds a vector per record, is a list column.

## Write a request body

[`json_write()`](https://pedrobtz.github.io/zujson/reference/json_write.md)
goes the other way and returns the JSON as one string, which
[`cat()`](https://rdrr.io/r/base/cat.html) prints without R’s escapes.
We build the body of a request that adds a third record:

``` r

new_item <- list(name = "Edsger", tags = "dev", active = TRUE)
cat(json_write(new_item))
#> {"name":"Edsger","tags":"dev","active":true}
```

A list whose elements are all named is written as an object; a list or
vector without names is written as an array, except that a vector of
length one is written as a bare value. So `tags` came out as a string.
The API sent `tags` as an array, so we wrap it in
[`I()`](https://rdrr.io/r/base/AsIs.html) to keep it one:

``` r

new_item$tags <- I("dev")
cat(json_write(new_item))
#> {"name":"Edsger","tags":["dev"],"active":true}
```

Writing `res`, the response we parsed, and parsing the result gives back
the same R object:

``` r

identical(json_parse(json_write(res)), res)
#> [1] TRUE
```

## Send and receive bytes

An HTTP client hands you a response body as a raw vector and wants a
request body as one.
[`json_write_raw()`](https://pedrobtz.github.io/zujson/reference/json_write.md)
returns UTF-8 bytes, and
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
accepts them as it accepts a string:

``` r

bytes <- json_write_raw(new_item)
head(bytes)
#> [1] 7b 22 6e 61 6d 65

str(json_parse(bytes))
#> List of 3
#>  $ name  : chr "Edsger"
#>  $ tags  : chr "dev"
#>  $ active: logi TRUE
```

The one-element array we wrote for `tags` reads back as a character
vector of length one.

When the JSON is in a file,
[`json_parse_file()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
reads it without the detour through a string:

``` r

path <- tempfile(fileext = ".json")
writeBin(bytes, path)

json_parse_file(path)$name
#> [1] "Edsger"
```

## Handle a broken body

A connection that drops leaves you with part of a body. We cut ours off
after 40 characters.
[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
says whether the input is JSON, without building anything and without
raising an error:

``` r

truncated <- substr(body, 1, 40)
json_validate(truncated)
#> [1] FALSE
```

[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
stops, and the message says where:

``` r

json_parse(truncated)
#> Error:
#> ! invalid JSON at byte 40: unexpected end of data
```

Every error zujson raises has the class `zujson_error`, and a more
specific one before it, so a single handler can catch them all and still
tell them apart:

``` r

tryCatch(
  json_parse(truncated),
  zujson_error = function(e) class(e)[1]
)
#> [1] "zujson_parse_error"
```

## Read and write NDJSON

**NDJSON** is one JSON value per line, the format of log streams and
bulk uploads.
[`json_write_ndjson()`](https://pedrobtz.github.io/zujson/reference/json_parse_ndjson.md)
writes one line for each element of a list, or each row of a data frame:

``` r

lines <- json_write_ndjson(res$items)
cat(lines)
#> {"id":1,"name":"Ada","tags":["admin","dev"],"score":9.5}
#> {"id":2,"name":"Grace","tags":[],"score":null}
```

[`json_parse_ndjson()`](https://pedrobtz.github.io/zujson/reference/json_parse_ndjson.md)
reads such a body back as a list with one element per line:

``` r

records <- json_parse_ndjson(lines)
identical(records, res$items)
#> [1] TRUE
```

## Where next

zujson stops there on purpose: it has no matrices, no streaming parser
and no custom serializers, and
[`?zujson`](https://pedrobtz.github.io/zujson/reference/zujson-package.md)
lists what is out of scope.

- [Handle malformed or untrusted
  input](https://pedrobtz.github.io/zujson/articles/untrusted-input.html):
  the condition classes, the depth and size limits, and when validating
  first is not enough.
- [Read a large API
  document](https://pedrobtz.github.io/zujson/articles/kubernetes-openapi.html):
  the same functions on the 3.3 MB Kubernetes API specification.
- [Coming from
  jsonlite](https://pedrobtz.github.io/zujson/articles/jsonlite.html):
  where the two packages give different results for the same input.
- [Testing and
  conformance](https://pedrobtz.github.io/zujson/articles/testing.html):
  how the package is checked, and what it does with the JSON that
  parsers disagree on.
- The
  [reference](https://pedrobtz.github.io/zujson/reference/index.html):
  every function, with the full type mapping under
  [`?json_parse`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
  and
  [`?json_write`](https://pedrobtz.github.io/zujson/reference/json_write.md).
