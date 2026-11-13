W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
set.seed(2); res <- list()
for (nd in c(20,25,40,80,160,300)) { bad <- 0; mx <- 0
  for (i in 1:5000) { tok <- paste0(sample(1:9,1), paste(sample(0:9, nd-1, TRUE), collapse=""))
    a <- json_parse(tok); b <- json_parse(paste0(tok, ".0"))
    if (a != b) { bad <- bad+1; u <- abs(a-b)/(2^(floor(log2(b))-52)); mx <- max(mx,u) } }
  cat(nd, "digits: wrong", bad, "/5000, max ulp", mx, "\n") }
# in a vector: one element raw-path, other real-path, same value
tok <- "7908650058519908757503158852011"
x <- json_parse(sprintf("[%s, %s.0]", tok, tok)); print(x[1]==x[2]); cat(sprintf("%a %a\n", x[1], x[2]))
print(as.numeric(tok) == x[1]); print(jsonlite::fromJSON(sprintf("[%s]",tok)) == x[2])
