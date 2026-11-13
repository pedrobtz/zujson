source("pre.R")
nest <- function(n, leaf) { x <- leaf; for (i in seq_len(n)) x <- list(x); x }
cls <- function(e) tryCatch({e; "ok"}, error=function(e) class(e)[1])
for (m in 997:999) { d <- data.frame(a=1); d$l <- list(nest(m, 1)); j <- cls(json_write(d)); cat("df top + cell of", m, "lists => total", m+2, ":", j, if (j=="ok") cls(json_parse(json_write(d))), "\n") }
for (m in 998:1000) { d <- data.frame(a=1); d$l <- list(nest(m, 1)); j <- cls(json_write_ndjson(d)); cat("ndjson row + cell of", m, "lists => total", m+1, ":", j, if (j=="ok") cls(json_parse_ndjson(json_write_ndjson(d))), "\n") }
for (m in 997:999) { d <- data.frame(a=1); d$l <- list(nest(m-2, data.frame(q=1))); j <- cls(json_write(d)); cat("df top + cell lists", m-2, "+ df => total", m+2, ":", j, if (j=="ok") cls(json_parse(json_write(d))), "\n") }
cat("--- sequences: interleave failures and successes\n")
big <- data.frame(a=1:20000, s=sprintf("row%d", 1:20000)); big$l <- rep(list(1), 20000); big$l[[19999]] <- sum
bigl <- c(rep(list(list(a=1,b="x")), 5000), list(sum))
by <- "a\xff"; Encoding(by) <- "bytes"; badu <- "a\xff"; Encoding(badu) <- "UTF-8"
ref <- json_write(list(a=1,b="x")); gc(); m0 <- NULL
rss <- function() as.numeric(system(paste("ps -o rss= -p", Sys.getpid()), intern=TRUE))/1024
for (i in 1:300) {
  stopifnot(cls(json_write(big)) == "zujson_unsupported_type", identical(json_write(list(a=1,b="x")), ref))
  stopifnot(cls(json_write_ndjson(big)) == "zujson_unsupported_type", identical(json_write_ndjson(list(list(a=1,b="x"))), paste0(ref,"\n")))
  stopifnot(cls(json_write_ndjson(bigl)) == "zujson_unsupported_type")
  stopifnot(cls(json_write(list(rep("ok",1000), by))) == "zujson_write_error", cls(json_write(list(rep("ok",1000), badu))) == "zujson_write_error")
  stopifnot(cls(json_write_raw(nest(1001, 1))) == "zujson_depth_error", cls(json_write(structure(1e9, class="Date"))) == "zujson_write_error")
  stopifnot(cls(json_parse("[1,2,")) == "zujson_parse_error", cls(json_parse('["\\u0000"]')) == "zujson_parse_error")
  if (i == 20) { gc(); m0 <- rss() }
}
gc(); cat("rss after 20 iters:", m0, "MB; after 300:", rss(), "MB\n")
# what was returned before error: nothing assigned
out <- "sentinel"; r <- tryCatch(out <- json_write_ndjson(bigl), error=function(e) conditionMessage(e)); cat("out still:", out, "| msg:", r, "\n")
r <- tryCatch(json_write(big), error=function(e) conditionMessage(e)); cat("msg:", r, "\n")
