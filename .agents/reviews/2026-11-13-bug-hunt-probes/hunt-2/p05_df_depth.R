W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
t <- function(e) tryCatch(e, error=function(e) structure(paste("ERR", paste(class(e)[1:2],collapse="/"), conditionMessage(e)), class="err"), warning=function(w) paste("WARN", conditionMessage(w)))
ok <- function(x) !inherits(x, "err")
nest <- function(n, inner) paste0(strrep("[", n), inner, strrep("]", n))
cat("== depth straddle\n")
for (n in 999:1001) cat(n, "arr:", ok(t(json_parse(nest(n, "1")))), " none:", ok(t(json_parse(nest(n,"1"), simplify="none"))),
   " obj-in:", ok(t(json_parse(nest(n-1, '{"a":1}')))), " validate:", json_validate(nest(n,"1")), 
   " ndjson:", ok(t(json_parse_ndjson(paste0("1\n", nest(n,"1"), "\n")))), "\n")
cat("== depth x df: array at depth n holding records, df vs list\n")
for (n in 998:1001) { d <- nest(n, '{"a":1}'); cat(n, "list:", ok(t(json_parse(d))), "df:", ok(t(json_parse(d, data_frame=TRUE))), "none+df:", ok(t(json_parse(d, simplify="none", data_frame=TRUE))), "\n") }
cat("== cell holding container: frame at depth n, cell array\n")
for (n in 997:1000) { d <- nest(n, '{"a":[1]}'); cat(n, "list:", ok(t(json_parse(d))), "df:", ok(t(json_parse(d, data_frame=TRUE))), "\n") }
for (n in 997:1000) { d <- nest(n, '{"a":[1]},{"a":"x"}'); cat(n, "mixed list:", ok(t(json_parse(d))), "df:", ok(t(json_parse(d, data_frame=TRUE))), "\n") }
for (n in 996:1000) { d <- nest(n, '{"a":[{"b":1}]},{"a":"x"}'); cat(n, "nested-df list:", ok(t(json_parse(d))), "df:", ok(t(json_parse(d, data_frame=TRUE))), "\n") }
for (n in 997:1000) { d <- nest(n, '{}'); cat(n, "empty rec list:", ok(t(json_parse(d))), "df:", ok(t(json_parse(d, data_frame=TRUE))), "\n") }
cat("== df value checks\n")
p <- function(j, ...) { r <- t(json_parse(j, data_frame=TRUE, ...)); cat(j, "\n"); str(r) }
p('[{"a":1,"b":"x"},{"b":null,"c":[1,2]},{"a":2.5,"c":{"k":1}}]')
p('[{"a":1},{"a":"x"}]'); p('[{"a":1},{"a":"x"}]', simplify="coerce"); p('[{"a":true},{"a":2},{}]'); p('[{"a":null},{}]')
p('[{},{}]'); p('[{}]'); p('[{"":1},{"":2}]'); p('[{"a":1},2]'); p('[[{"a":1}],[{"a":2}]]'); p('{"x":[{"a":[{"b":1},{"b":2}]}]}')
p('[{"a":1,"a":2}]'); p('[{"a":1,"\\u0061":2}]'); p('[{"a":1},{"b":1,"a":1,"b":2}]'); p('[{"a\\u0000":1}]'); p('[{"a":"x\\u0000"}]'); p('[{"a":"x\\u0000"},{"a":1}]')
p('[{"a":-2147483648},{"a":1}]'); p('[{"a":2147483647},{"a":null}]'); p('[{"a":1e400},{"a":"s"}]', simplify="coerce"); p('[{"a":100000},{"a":0.5},{"a":"s"},{"a":true},{}]', simplify="coerce")
p('[{"a":1}]', simplify="none")
cat("plain dup keys:\n"); str(json_parse('{"a":1,"a":2,"\\u0061":3}'))
cat("== budget straddle\n")
mk <- function(r, c) paste0("[", paste(rep(paste0("{", paste(sprintf('"k%d":1', seq_len(c)), collapse=","), "}"), r), collapse=","), "]")
for (b in c(11,12,13)) { options(zujson.max_df_cells=b); cat("budget", b, "3x4:", ok(t(json_parse(mk(3,4), data_frame=TRUE))), " 4x3:", ok(t(json_parse(mk(4,3), data_frame=TRUE))), " info:", zujson_info()$max_df_cells, "\n") }
options(zujson.max_df_cells=4); cat("two 2x2 frames with budget 4:", ok(t(json_parse('[[{"a":1,"b":1},{"a":1,"b":1}],[{"a":1,"b":1},{"a":1,"b":1}]]', data_frame=TRUE))), "\n")
cat("nested frame in cell, budget 4:", ok(t(json_parse('[{"a":[{"x":1,"y":2},{"x":1,"y":2}],"b":1},{"a":[{"x":1,"y":2},{"x":1,"y":2}],"b":"s"}]', data_frame=TRUE))), "\n")
options(zujson.max_df_cells=1); print(t(json_parse('[{"a":1}]', data_frame=TRUE))); print(t(json_parse('[{"a":1},{"a":1}]', data_frame=TRUE))); print(t(json_parse('[{},{}]', data_frame=TRUE))); print(t(json_parse('[{"a":1,"b":2}]', data_frame=TRUE)))
for (v in list(1.9, 0.99, 0, -1, NA, NaN, Inf, "5", TRUE, c(1,2), 1e300, 2^52, 2^53, 2^63, 2^64, .Machine$double.xmax, 2147483648, 5L, NA_integer_, NULL)) { options(zujson.max_df_cells=v); r <- t(json_parse('[{"a":1,"b":2},{"a":1,"b":2}]', data_frame=TRUE)); cat(format(deparse(v), width=24), if (ok(r)) "ok" else unclass(r), "| info:", format(t(zujson_info()$max_df_cells), digits=17), "| df=FALSE:", ok(t(json_parse('[1]'))), "\n") }
