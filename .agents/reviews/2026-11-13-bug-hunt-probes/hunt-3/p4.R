source("pre.R")
nest <- function(n, leaf) { x <- leaf; for (i in seq_len(n)) x <- list(x); x }
nestn <- function(n, leaf) { x <- leaf; for (i in seq_len(n)) x <- list(a=x); x }
st <- function(x, ...) { r <- tryCatch({ j <- json_write(x, ...); p <- tryCatch({json_parse(j); "parse-ok"}, error=function(e) paste0("PARSE-FAIL:", class(e)[1])); 
   d <- max(cumsum(c(1,-1)[match(strsplit(gsub('"[^"]*"', '', j), "")[[1]], c("[","{","]","}"), nomatch=NA) |> (\(m) ifelse(m<=2,1,2))() |> na.omit()]))
   paste("write-ok jsondepth", d, p) }, error=function(e) class(e)[1]); r }
D <- zujson_info()$max_depth; cat("D =", D, "\n")
for (k in c(D-1, D, D+1)) {
  cat(k, "containers list(scalar):   ", st(nest(k, 1)), "\n")
  cat(k, "containers list(1:2):      ", st(nest(k-1, 1:2)), "\n")
  cat(k, "containers named:          ", st(nestn(k, 1)), "\n")
  cat(k, "containers c(a=1) leaf:    ", st(nest(k-1, c(a=1))), "\n")
  cat(k, "containers I(1) leaf:      ", st(nest(k-1, I(1))), "\n")
  cat(k, "auto_unbox=F scalar leaf:  ", st(nest(k-1, 1), auto_unbox=FALSE), "\n")
  cat(k, "df leaf (2 levels):        ", st(nest(k-2, data.frame(a=1))), "\n")
  cat(k, "df 0 rows leaf(1 level emitted):", st(nest(k-1, data.frame(a=integer(0)))), "\n")
  d <- data.frame(a=1); d$l <- list(1:2); cat(k, "df w/ list cell 1:2 (3 lv): ", st(nest(k-3, d)), "\n")
  d <- data.frame(a=1); d$l <- list(list()); cat(k, "df w/ list cell list() (3): ", st(nest(k-3, d)), "\n")
  d <- data.frame(a=1); d$l <- list(1); cat(k, "df w/ list cell scalar (2): ", st(nest(k-2, d)), "\n")
  d <- data.frame(a=1); d$l <- list(nest(k-3, 1)); cat(k, "df top, deep cell:          ", st(d), "\n")
  d <- data.frame(a=1); d$l <- list(nest(k-2, 1)); r <- tryCatch({j<-json_write_ndjson(d); p<-tryCatch({json_parse_ndjson(j);"parse-ok"}, error=function(e) class(e)[1]); paste("write-ok", p)}, error=function(e) class(e)[1])
  cat(k, "ndjson df row, deep cell:   ", r, "\n")
  r <- tryCatch({j<-json_write_ndjson(list(nest(k, 1))); p<-tryCatch({json_parse_ndjson(j);"parse-ok"}, error=function(e) class(e)[1]); paste("write-ok", p)}, error=function(e) class(e)[1])
  cat(k, "ndjson list record:         ", r, "\n")
  cat(k, "NULL leaf:                 ", st(nest(k, NULL)), "\n")
  cat(k, "empty list leaf:           ", st(nest(k-1, list())), "\n")
}
cat("very deep (1e5):", st(nest(1e5, 1)), "\n")
