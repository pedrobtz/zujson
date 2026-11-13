W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
for (s in 13:15) for (k in c("ctl","col")) { f <- sprintf("%s/hunt-2/%s%d.json", W, k, s)
  t0 <- system.time(x <- json_parse_file(f))[["elapsed"]]; t1 <- system.time(y <- json_parse_file(f, data_frame=TRUE))[["elapsed"]]
  cat(sprintf("%s 2^%d keys, %7d bytes: list %.3fs  data_frame %.3fs  (cols %d)\n", k, s, file.size(f), t0, t1, ncol(y))) }
