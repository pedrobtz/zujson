W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
rss <- function() as.numeric(system(paste("ps -o rss= -p", Sys.getpid()), intern=TRUE))/1024
cat("== interrupt during parse (SIGINT from a child)\n")
big <- paste0("[", paste(rep('{"a":[1,"x",{"b":null}],"c":"s"}', 400000), collapse=","), "]"); cat("bytes:", nchar(big), "\n")
print(system.time(json_parse(big)))
for (mode in list(list("preserve",FALSE), list("preserve",TRUE), list("nd",FALSE))) for (delay in c(0.05, 0.15, 0.3)) {
  system(sprintf("(sleep %s; kill -INT %d) &", delay, Sys.getpid()))
  r <- tryCatch({ if (mode[[1]]=="nd") json_parse_ndjson(paste(rep(big, 1), collapse="\n")) else json_parse(big, mode[[1]], mode[[2]]); Sys.sleep(1); "completed" }, interrupt=function(i) "interrupt", error=function(e) paste("ERR", class(e)[1]))
  tryCatch(Sys.sleep(0.4), interrupt=function(i) NULL)
  cat(mode[[1]], mode[[2]], delay, "->", r, "| next call ok:", identical(json_parse('[{"a":1}]', data_frame=TRUE), data.frame(a=1L)), "\n")
}
gc(); r0 <- rss()
cat("== leak growth: 200 interrupted/complete big parses then errors\n")
errdocs <- list(paste0("[", paste(rep('{"a":[1,"x"],"c":"s"}', 20000), collapse=","), ',{"z":"\\u0000"}]'),   # fails at the very end of df build
                paste0("[", paste(sprintf('{"k%d":1}', 1:3000), collapse=","), "]"))                              # limit error w/ budget
options(zujson.max_df_cells = 1e6)
for (rep in 1:3) { for (i in 1:150) { for (d in errdocs) { tryCatch(json_parse(d, data_frame=TRUE), zujson_error=function(e) NULL); tryCatch(json_parse_ndjson(d, data_frame=TRUE), zujson_error=function(e) NULL) }; tryCatch(json_parse(errdocs[[1]]), zujson_error=function(e) NULL) }; gc(); cat("round", rep, "rss MB:", round(rss()), "\n") }
cat("== 3 sec of interrupts mid-parse, rss\n")
for (rep in 1:3) { for (i in 1:8) { system(sprintf("(sleep 0.1; kill -INT %d) &", Sys.getpid())); tryCatch({json_parse(big); Sys.sleep(1)}, interrupt=function(i) NULL) }; gc(); cat("round", rep, "rss MB:", round(rss()), "\n") }
