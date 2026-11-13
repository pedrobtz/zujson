W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
f <- file.path(W, "hunt-2/col15.json"); system(sprintf("(sleep 0.5; kill -INT %d) &", Sys.getpid()))
t0 <- Sys.time(); r <- tryCatch({ json_parse_file(f, data_frame=TRUE); Sys.sleep(2); "completed" }, interrupt=function(i) "interrupt"); cat(r, "after", round(as.numeric(Sys.time()-t0),2), "s (SIGINT sent at 0.5 s)\n")
# same keys spread over many records (NDJSON-like array of single-key records): rows x cols must fit the budget, so use 2 records
