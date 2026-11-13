.libPaths(c(file.path(Sys.getenv("W"), "lib"), .libPaths())); library(zujson)
t <- function(label, expr) {
  r <- tryCatch(expr, condition = function(e) paste0("<", paste(class(e), collapse="/"), "> ", conditionMessage(e)))
  cat(sprintf("%-34s %s\n", label, if (is.character(r) && length(r)==1 && startsWith(r,"<")) r else paste(deparse(r, control=c("keepNA","keepInteger","niceNames","showAttributes")), collapse="")))
}
p <- json_parse
cat("--- coerce order\n")
t("[100000,1.5,'a']", p('[100000,1.5,"a"]', simplify="coerce")); t("[100000,'a',1.5]", p('[100000,"a",1.5]', simplify="coerce")); t("['a',100000,1.5]", p('["a",100000,1.5]', simplify="coerce"))
t("[100000,'a']", p('[100000,"a"]', simplify="coerce")); t("[true,1.5,'a']", p('[true,1.5,"a"]', simplify="coerce"))
t("[1.0,'a'] vs [1,'a']", c(p('[1.0,"a"]', simplify="coerce")[1], p('[1,"a"]', simplify="coerce")[1]))
t("[2147483648,1,'a']", p('[2147483648,1,"a"]', simplify="coerce"))
t("df coerce col", p('[{"a":100000},{"a":1.5},{"a":"x"}]', simplify="coerce", data_frame=TRUE)$a)
t("df coerce col2", p('[{"a":100000},{"a":"x"}]', simplify="coerce", data_frame=TRUE)$a)
cat("--- routes\n")
docs <- c('{"a":[1,2,{"b":null}],"c":"é\\n","d":1e309,"e":[1,"x"],"f":[{"k":1},{"k":2}]}', '[1,2,3]', '"x"', 'null', '[]', '{}', '3.5', '[{"a":1},{"b":"y"}]')
f <- tempfile(fileext=".json")
for (dj in docs) for (s in list(TRUE,"coerce","none")) for (dfm in c(FALSE,TRUE)) {
  a <- p(dj, simplify=s, data_frame=dfm); b <- json_parse_raw(charToRaw(enc2utf8(dj)), simplify=s, data_frame=dfm); writeBin(charToRaw(enc2utf8(dj)), f); c_ <- json_parse_file(f, simplify=s, data_frame=dfm); d <- json_parse_ndjson(dj, simplify=s, data_frame=dfm); d2 <- json_parse_ndjson(charToRaw(enc2utf8(dj)), simplify=s, data_frame=dfm)
  ok <- identical(a,b) && identical(a,c_) && identical(list(a), d) && identical(d, d2) && identical(p(charToRaw(enc2utf8(dj)), simplify=s, data_frame=dfm), a)
  if (!ok) cat("ROUTE MISMATCH", dj, format(s), dfm, "\n")
}
cat("routes done\n")
# write routes
vals <- list(list(a=1,b="é\n",c=NULL,d=NA,e=1:3,f=list()), 1:3, "x", NULL, data.frame(a=1:2,b=c("x","y")), c(a=1.5), as.Date("2024-01-01"), list(list(1), list(a=2)))
for (v in vals) for (au in c(TRUE,FALSE)) {
  a <- json_write(v, auto_unbox=au); b <- rawToChar(json_write_raw(v, auto_unbox=au)); Encoding(b) <- "UTF-8"
  if (!identical(a,b)) cat("WRITE ROUTE MISMATCH\n")
  if (is.list(v)) { nd <- json_write_ndjson(v, auto_unbox=au); ndr <- rawToChar(json_write_ndjson_raw(v, auto_unbox=au)); Encoding(ndr) <- "UTF-8"
    per <- if (is.data.frame(v)) NULL else if (length(v)) paste0(paste(vapply(unname(v), json_write, "", auto_unbox=au), collapse="\n"), "\n") else ""
    if (!identical(nd, ndr)) cat("NDJSON raw MISMATCH\n")
    if (!is.null(per) && !identical(nd, per)) cat("NDJSON per-record MISMATCH:", nd, "vs", per, "\n")
    if (is.data.frame(v)) { whole <- json_write(v, auto_unbox=au); rec <- json_parse_ndjson(nd); if (!identical(json_write(rec), whole)) cat("DF ndjson vs write mismatch\n") }
  }
}
cat("write routes done\n")
t("pretty raw == pretty", identical(rawToChar(json_write_raw(list(a=1:2), pretty=TRUE)), json_write(list(a=1:2), pretty=TRUE)))
t("pretty top scalar", json_write(1, pretty=TRUE)); t("pretty empty", json_write(list(), pretty=TRUE)); t("pretty df", json_write(data.frame(a=1), pretty=TRUE))
cat("--- ndjson parse\n")
n <- json_parse_ndjson
t("basic", n('{"a":1}\n{"a":2}\n')); t("no trailing nl", n('1\n2')); t("blank lines", n('\n\n1\n\n2\n\n')); t("crlf", n('1\r\n2\r\n')); t("cr only", n('1\r2')); t("ws lines", n(' \n\t\n1\n  \n')); t("lone \\r line", n('1\n\r\n2'))
t("leading ws", n('  1  \n 2\t\n')); t("two on line", n('1 2\n')); t("concat", n('{"a":1}{"a":2}\n')); t("bad line 3", n('1\n2\n{\n4')); t("bad after blank", n('1\n\n\n{'))
t("BOM", n('﻿1\n2')); t("BOM line 2", n('1\n﻿2')); t("null rec", n('null\nnull')); t("pretty rec", n('{\n"a":1\n}'))
t("crlf blank", n('1\r\n\r\n2')); t("nul", n(as.raw(c(0x31,0x0a,0x00,0x0a,0x32)))); t("df per record", n('[{"a":1}]\n{"a":1}', data_frame=TRUE)); t("unicode ls", n('"a b"\n1'))
t("vt/ff ws", n("1\n\f\n2")); t("nbsp line", n("1\n \n2"))
t("depth err line", tryCatch(n(paste0("1\n", strrep("[",1001), strrep("]",1001))), error=function(e) class(e)[1]))
t("string with \\n escape", n('"a\\nb"\n"c"'))
t("rt records", identical(n(json_write_ndjson(list(list(a=1L), list(b="x")))), list(list(a=1L), list(b="x"))))
cat("--- option / info\n")
i <- zujson_info(); t("info", i)
big <- paste0("[", paste0('{"k', 1:20, '":1}', collapse=","), "]")  # 20x20=400 cells
for (o in list(399, 400, 401, 400.5, 399.9, 1, 0, 0.5, -1, NA, NA_real_, Inf, -Inf, NaN, "400", TRUE, c(1,2), integer(), NULL, 400L, 2^31, 2^53, 2^62, 2^63, 1e300, .Machine$double.xmax, list(400), factor("a"), 1.9, 20, 39, 40)) {
  options(zujson.max_df_cells = o)
  r <- tryCatch({x <- p(big, data_frame=TRUE); paste("ok", paste(dim(x), collapse="x"))}, condition=function(e) class(e)[1])
  inf <- tryCatch(format(zujson_info()$max_df_cells, digits=22), condition=function(e) class(e)[1])
  r0 <- tryCatch({p(big, data_frame=FALSE); "ok"}, condition=function(e) class(e)[1])
  cat(sprintf("opt=%-22s parse=%-22s info=%-26s df=FALSE:%s\n", paste(deparse(o), collapse=""), r, inf, r0))
}
options(zujson.max_df_cells = 4)
t("2x2 at 4", dim(p('[{"a":1,"b":2},{"a":1,"b":2}]', data_frame=TRUE))); t("2x3 at 4", p('[{"a":1,"b":2,"c":1},{"a":1,"b":2}]', data_frame=TRUE)); t("3x2 at 4", p('[{"a":1,"b":2},{"a":1,"b":2},{"a":1}]', data_frame=TRUE))
t("5 rows 0 cols at 4", dim(p('[{},{},{},{},{}]', data_frame=TRUE))); t("5x1 at 4", p('[{"a":1},{},{},{},{}]', data_frame=TRUE)); t("5x1 late key at 4", p('[{},{},{},{},{"a":1}]', data_frame=TRUE))
t("nested frames each 2x2 at 4", class(p('[[{"a":1,"b":2},{"a":1,"b":2}],[{"a":1,"b":2},{"a":1,"b":2}]]', data_frame=TRUE)[[2]]))
t("ndjson at 4", json_parse_ndjson('[{"a":1,"b":2,"c":1},{"a":1,"b":2}]', data_frame=TRUE))
t("simplify none ignores cap", p('[{"a":1,"b":2,"c":1},{"a":1,"b":2}]', data_frame=TRUE, simplify="none"))
options(zujson.max_df_cells = "x"); t("bad opt + df=FALSE", p("[1]")); t("bad opt + df=TRUE on scalar", p("1", data_frame=TRUE)); t("bad opt info", zujson_info()); t("bad opt + none", p("[1]", simplify="none", data_frame=TRUE))
options(zujson.max_df_cells = NULL); t("info after reset", zujson_info()$max_df_cells)
t("info names", names(zujson_info())); t("pkg ver", zujson_info()$zujson == as.character(packageVersion("zujson")))
