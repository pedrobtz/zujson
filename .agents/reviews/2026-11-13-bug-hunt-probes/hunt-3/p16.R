source("pre.R")
cls <- function(e) tryCatch({e; "ok"}, error=function(e) class(e)[1])
lk <- function() { gc(); gc(); suppressWarnings(grep("leaks for", system(sprintf("leaks %d 2>/dev/null", Sys.getpid()), intern=TRUE), value=TRUE)) }
nest <- function(n, leaf) { x <- leaf; for (i in seq_len(n)) x <- list(x); x }
big <- data.frame(a=1:20000, s=sprintf("row%d", 1:20000)); big$l <- rep(list(1), 20000); big$l[[19999]] <- sum
bigl <- c(rep(list(list(a=1,b=strrep("x",1e4))), 2000), list(sum))
badu <- "a\xff"; Encoding(badu) <- "UTF-8"; by <- badu; Encoding(by) <- "bytes"
js <- paste0("[", paste(rep('{"a":[1,2,3]}', 5000), collapse=","), ',"\\u0000"]')
cat("baseline:", lk(), "\n")
res <- character()
for (i in 1:30) res <- c(res, cls(json_write(big)), cls(json_write_ndjson(big)), cls(json_write_ndjson(bigl)), cls(json_write_raw(list(strrep("y", 1e6), badu))), cls(json_write(list(strrep("y", 1e6), by))),
  cls(json_write_ndjson(list(1, strrep("y", 1e6), badu))), cls(json_write(nest(1001, 1))), cls(json_write(list(strrep("y",1e6), structure(1e10, class="Date")))), cls(json_write(list(strrep("y",1e6), structure(NA, class="Date")))),
  cls(json_write(list(strrep("y",1e6), structure(1L, class="factor", levels=1:2)))), cls(json_write(list(strrep("y",1e6), structure(list(a=NULL), class="data.frame")))), cls(json_parse(js)), cls(json_parse_ndjson(paste0(strrep('{"a":1}\n', 1000), '"\\u0000"'))), json_write(1))
print(table(res)); cat("after 30 rounds of failures:", lk(), "\n")
# mapping invariance for a few second-case inputs
try_(json_write(list(a=1)[0])); try_(json_write(c(a=1)[0])); try_(json_write(I(NULL))); try_(json_write(data.frame(a=1), auto_unbox=FALSE)); try_(json_write(list(list(a=1)), auto_unbox=FALSE))
try_(json_write(data.frame(a=1, a=2, check.names=FALSE))); try_(json_parse(json_write(data.frame(a=1, a=2, check.names=FALSE))))
try_(json_write(structure(1:2, class=c("IDate","Date")))); try_(json_write(1:3 + 0L, pretty=TRUE)); try_(json_write(list(), pretty=TRUE)); try_(json_write("x", pretty=TRUE))
d <- data.frame(g=factor(c("a","b"))); attr(d$g, "levels") <- NULL; try_(json_write(d))
try_(json_write_ndjson(data.frame(f=structure(1:2, class="factor", levels=1:2))))
