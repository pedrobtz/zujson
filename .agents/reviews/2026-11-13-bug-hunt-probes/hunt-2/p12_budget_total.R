W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
frame <- function(n) paste0("[", paste(sprintf('{"%d":1}', seq_len(n)), collapse=","), "]")
cat("default budget:", zujson_info()$max_df_cells, "\n")
one <- frame(2000)                                   # 2000 x 2000 = 4e6 cells, under 5e7
for (k in c(1, 10, 40)) { body <- paste0("[", paste(rep(one, k), collapse=","), "]")
  tm <- system.time(x <- json_parse(body, data_frame=TRUE))[["elapsed"]]
  cat(sprintf("%2d frames: body %7d bytes -> %.0f cells, object.size %.0f MB, %.1fs\n", k, nchar(body), sum(vapply(x, function(d) as.numeric(nrow(d))*ncol(d), 0)), as.numeric(object.size(x))/2^20, tm)); rm(x); gc(FALSE) }
# the same total in ONE frame is refused
r <- tryCatch(json_parse(frame(7100), data_frame=TRUE), error=function(e) conditionMessage(e)); cat("single 7100x7100 frame:", if (is.character(r)) r else "accepted", "\n")
# ndjson: one frame per line
nd <- paste(rep(one, 10), collapse="\n"); x <- json_parse_ndjson(nd, data_frame=TRUE); cat("ndjson 10 lines:", sum(vapply(x, function(d) as.numeric(nrow(d))*ncol(d), 0)), "cells\n")
