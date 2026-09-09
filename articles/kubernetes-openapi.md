# The Kubernetes API spec in JSON

`zujson` exists to read HTTP response bodies, so the honest test is a
real one. The Kubernetes OpenAPI specification is 3.3 MB of deeply
nested JSON describing 476 endpoints and 635 object types — larger than
almost any response an API will hand you, and far more irregular.

The URL is pinned to a release tag rather than a branch, so the file —
and therefore everything printed below — does not change under you.

``` r

library(zujson)

url <- paste0("https://raw.githubusercontent.com/kubernetes/kubernetes/",
              "v1.31.0/api/openapi-spec/swagger.json")
path <- file.path(tempdir(), "swagger.json")
download.file(url, path, quiet = TRUE)

file.size(path)
#> [1] 3277085
```

## Reading it

``` r

api <- json_parse_file(path)

names(api)
#> [1] "definitions"         "info"                "parameters"
#> [4] "paths"               "security"            "securityDefinitions"
#> [7] "swagger"

c(paths = length(api$paths), definitions = length(api$definitions))
#>       paths definitions
#>         476         635
```

That took about 19 milliseconds for 3.3 MB — roughly 170 MB/s, which is
yyjson’s doing rather than anything clever here. The whole document
becomes 51,727 R objects nested 7 levels deep.

[`json_parse_file()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
rather than reading the file into a string first: the bytes go straight
from the file to the parser, which is the same reason
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
accepts a raw vector.

## Asking it questions

Once it is R data, it is just R:

``` r

verbs <- unlist(lapply(api$paths, function(p) {
  intersect(names(p), c("get", "put", "post", "delete", "patch", "head", "options"))
}))

sort(table(verbs), decreasing = TRUE)
#> verbs
#>     get  delete     put   patch    post    head options
#>     463     145     117     116      91       6       6
```

## Records become data frames

Almost every API document contains arrays of objects — records, in all
but name. `data_frame = TRUE` reconstructs them wherever they appear:

``` r

d <- json_parse_file(path, data_frame = TRUE)
```

One pass over the parsed spec finds **1,096** of them. Here is the
group/version/kind table that Kubernetes attaches to a type:

``` r

g <- d$definitions[["io.k8s.apimachinery.pkg.apis.meta.v1.WatchEvent"]][["x-kubernetes-group-version-kind"]]

dim(g)
#> [1] 60  3

head(g, 6)
#>                          group       kind  version
#> 1                              WatchEvent       v1
#> 2             admission.k8s.io WatchEvent       v1
#> 3             admission.k8s.io WatchEvent  v1beta1
#> 4 admissionregistration.k8s.io WatchEvent       v1
#> 5 admissionregistration.k8s.io WatchEvent v1alpha1
#> 6 admissionregistration.k8s.io WatchEvent  v1beta1
```

## Ragged records are the normal case

Real documents do not have records that agree on their keys, and this
spec is a good demonstration of why the union-of-keys rule matters. A
path’s `parameters` array mixes two shapes: `$ref` pointers to shared
parameters, and parameter objects written inline.

``` r

q <- d$paths[["/api/v1/watch/namespaces/{namespace}/configmaps/{name}"]]$parameters

dim(q)
#> [1] 13  7

q[1:6, c("name", "in", "type", "description")]
#>   name in   type   description
#> 1 <NA> <NA> <NA>   <NA>
#> 2 <NA> <NA> <NA>   <NA>
#> 3 <NA> <NA> <NA>   <NA>
#> 4 <NA> <NA> <NA>   <NA>
#> 5 <NA> <NA> <NA>   <NA>
#> 6 name path string name of the ConfigMap
```

The first five rows are `$ref` entries, so every inline-parameter column
is `NA` for them; the sixth is a real parameter, so its `$ref` column is
`NA` instead. Columns are the union of all the keys, a missing key reads
as `NA`, and the frame is rectangular however ragged the input:

``` r

vapply(q, function(x) class(x)[1], "")
#>        $ref description          in        name    required        type
#> "character" "character" "character" "character"   "logical" "character"
#> uniqueItems
#>   "logical"
```

Nothing was coerced to make that work: `required` and `uniqueItems` are
logical because every value in them is a boolean or absent.

## The type-preserving default

By default an array whose elements disagree stays a list rather than
becoming a character vector:

``` r

json_parse('[1, "a"]')
#> [[1]]
#> [1] 1
#>
#> [[2]]
#> [1] "a"
```

In a specification that is what you want — a field that is usually a
number and occasionally a string is a bug in the document, and silently
stringifying it hides the bug. When you would rather have the vector,
ask:

``` r

json_parse('[1, "a"]', simplify = "coerce")
#> [1] "1" "a"
```

The two modes agree everywhere else, and both leave nested containers
alone.

## Pointing it at something you did not write

This file came off the internet, which is the case the parser is built
for. Nesting is capped at 1000 levels and rejected with a classed
condition rather than a stack overflow, and every failure the package
raises inherits from `zujson_error`, so one handler covers all of them:

``` r

result <- tryCatch(json_parse_file(path),
                   zujson_error = function(e) NULL)
```

[`json_validate()`](https://pedrobtz.github.io/zujson/reference/json_validate.md)
answers the yes/no question without building anything, which is cheaper
when all you need is to decide whether a body is worth parsing.
