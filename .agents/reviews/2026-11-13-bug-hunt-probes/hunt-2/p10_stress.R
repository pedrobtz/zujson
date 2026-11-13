args <- commandArgs(TRUE); lib <- args[1]; torture <- length(args) > 1
.libPaths(c(lib, .libPaths())); library(zujson)
W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
t <- function(e) tryCatch(e, error=function(e) { stopifnot(inherits(e, "zujson_error")); "E" }, warning=function(w) stop("warning escaped: ", conditionMessage(w)))
nest <- function(n, inner) paste0(strrep("[", n), inner, strrep("]", n))
good <- '[{"a":1,"b":"x","c":[1,2,{"d":null}]},{"b":"y","e":1e400,"f":[{"g":1},{"h":"\\u00e9"}]}]'
want <- list(json_parse(good), json_parse(good, "coerce", TRUE), json_parse(good, "none"))
docs <- list(good, '[1,"a",2.5,null,true]', '[{"a":1,"a":2}]', '[{"a":"x\\u0000"},{"a":1}]', '{"k\\u0000":1}', nest(1001,"1"), nest(999,'{"a":[1]}'), nest(1000, '{"a":1}'),
  '[{"a":1},{"b":2},{"c":3}]', '[1,', '', '[{"a":[{"x":1},{"x":"\\u0000"}]},{"a":1}]', '["a","b\\u0000"]', '[1,"a\\u0000"]', '[{"a":1,"b":[1,2]},{"a":"s","b":{"q":[{"z":1,"z":2}]}}]',
  '18446744073709551616', '[1e999,"x",true,null,2]', '[[],[{}],{}]', '[{}]', as.raw(c(0x5b,0x22,0xff,0x22,0x5d)), as.raw(c(0xef,0xbb,0xbf,0x5b,0x5d)), '[{"":1},{"":null}]')
run <- function() {
  for (d in docs) for (s in c("preserve","coerce","none")) for (df in c(FALSE,TRUE)) {
    t(json_parse(d, s, df)); t(json_validate(d))
    nd <- if (is.raw(d)) c(d, as.raw(0x0a), d) else paste0(d, "\r\n\n", d, "\n"); t(json_parse_ndjson(nd, s, df))
    stopifnot(identical(json_parse(good), want[[1]]))
  }
  options(zujson.max_df_cells = 2); for (d in docs) { t(json_parse(d, "preserve", TRUE)); t(json_parse(d, "coerce", TRUE)) }; options(zujson.max_df_cells = NULL)
  stopifnot(identical(json_parse(good, "coerce", TRUE), want[[2]]), identical(json_parse(good, "none"), want[[3]]))
}
if (torture) { gctorture2(1); run(); gctorture2(0); cat("gctorture ok\n") } else {
  for (i in 1:30) run()
  # truncations and single-byte mutations of a good doc
  r <- charToRaw(good); set.seed(42)
  for (i in seq_along(r)) { t(json_parse(r[seq_len(i-1)], "coerce", TRUE)); t(json_parse_ndjson(r[seq_len(i-1)], "preserve", TRUE)) }
  for (i in 1:20000) { m <- r; k <- sample(length(m), sample(1:3,1)); m[k] <- as.raw(sample(c(0:255, utf8ToInt('[]{}",:\\0n')), length(k), TRUE)); for (s in c("preserve","coerce")) { t(json_parse(m, s, TRUE)); t(json_parse_ndjson(m, s, TRUE)) } }
  # big shapes: long atomic, wide df, key-index growth sizes
  for (n in c(1,2,3,4,5,7,8,9,15,16,17,31,32,33,63,64,65,1023,1024,1025)) {
    j <- paste0("[{", paste(sprintf('"k%d":%d', seq_len(n), seq_len(n)), collapse=","), "},{", paste(sprintf('"q%d":%d', seq_len(n), seq_len(n)), collapse=","), "}]")
    x <- json_parse(j, data_frame=TRUE); stopifnot(ncol(x) == 2*n, nrow(x) == 2, identical(names(x), c(paste0("k",seq_len(n)), paste0("q",seq_len(n)))), identical(unlist(x[1,seq_len(n)], use.names=FALSE), seq_len(n)), all(is.na(x[1,n+seq_len(n)])), identical(unlist(x[2,n+seq_len(n)], use.names=FALSE), seq_len(n)))
    for (b in c(2*n*2-1, 2*n*2, 2*n, 2*n+1, 1)) { options(zujson.max_df_cells=b); r1 <- t(json_parse(j, data_frame=TRUE)); stopifnot(identical(r1,"E") == (b < 4*n)) }; options(zujson.max_df_cells=NULL)
  }
  x <- json_parse(paste0("[", paste(1:200000, collapse=","), "]")); stopifnot(identical(x, 1:200000))
  gc(); cat("stress ok\n")
}
