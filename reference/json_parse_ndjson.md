# Parse and write NDJSON

NDJSON (`application/x-ndjson`, also called JSON Lines) is one JSON
value per line. `json_parse_ndjson()` turns such a body into a list of
records; `json_write_ndjson()` and `json_write_ndjson_raw()` go the
other way.

## Usage

``` r
json_parse_ndjson(x, simplify = TRUE, data_frame = FALSE)

json_write_ndjson(x, auto_unbox = TRUE)

json_write_ndjson_raw(x, auto_unbox = TRUE)
```

## Arguments

- x:

  For `json_parse_ndjson()`, a single string or a raw vector of NDJSON
  bytes. For the writers, a list of records or a data frame — a data
  frame is written one object per row, which is the shape NDJSON exists
  for.

- simplify:

  Passed through to
  [`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
  for each record.

- data_frame:

  Passed through to
  [`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
  for each record. Note that records are parsed one at a time, so this
  turns an array *inside* a record into a data frame; it does not make a
  frame out of the stream.

- auto_unbox:

  Passed through to
  [`json_write()`](https://pedrobtz.github.io/zujson/reference/json_write.md)
  for each record.

## Value

`json_parse_ndjson()` returns a list with one element per record.
`json_write_ndjson()` returns a single string, and
`json_write_ndjson_raw()` a raw vector of UTF-8 bytes. Both end with a
trailing newline, so appending another record is always valid.

## Details

Each line is parsed exactly as
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
would parse it, and each record is written exactly as
[`json_write()`](https://pedrobtz.github.io/zujson/reference/json_write.md)
would write it, so the type mappings documented there apply unchanged.
The result of parsing is **always a list**, one element per record,
however uniform the records are — records are independent documents, and
an NDJSON body is not a table.

Blank lines are skipped rather than treated as records, and `\r\n` line
endings are accepted. A parse failure reports the **line number**,
because "invalid JSON at byte 41827" is not useful in a body of 10,000
records.

## Why line framing is safe

A raw newline byte cannot appear inside a JSON string — it must be
escaped as `\\n` — and zujson's writer always escapes it. A serialized
record therefore never contains a bare newline, so splitting on newlines
can never cut a record in half. This is the property the format rests
on.

It is also why there is no `pretty` argument: indented JSON contains
newlines, and a newline inside a record is exactly what NDJSON framing
cannot survive. Pretty-printed NDJSON is corrupt, not prettier.

## See also

[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
and
[`json_write()`](https://pedrobtz.github.io/zujson/reference/json_write.md)
for single documents.

## Examples

``` r
body <- '{"id":1,"ok":true}\n{"id":2,"ok":false}\n'
json_parse_ndjson(body)
#> [[1]]
#> [[1]]$id
#> [1] 1
#> 
#> [[1]]$ok
#> [1] TRUE
#> 
#> 
#> [[2]]
#> [[2]]$id
#> [1] 2
#> 
#> [[2]]$ok
#> [1] FALSE
#> 
#> 

# a data frame is one record per row
cat(json_write_ndjson(data.frame(id = 1:2, nm = c("a", "b"))))
#> {"id":1,"nm":"a"}
#> {"id":2,"nm":"b"}

# round trip
recs <- list(list(a = 1L), list(b = "x"))
identical(json_parse_ndjson(json_write_ndjson(recs)), recs)
#> [1] TRUE

# bytes, ready to be an HTTP request body
json_write_ndjson_raw(list(list(a = 1L), list(a = 2L)))
#>  [1] 7b 22 61 22 3a 31 7d 0a 7b 22 61 22 3a 32 7d 0a
```
