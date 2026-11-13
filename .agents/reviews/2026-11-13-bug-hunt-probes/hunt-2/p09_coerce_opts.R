W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
cat(R.version.string, "\n")
j <- '[123456.7, 0.5, 100000, 1e15, 1e-5, "a"]'; nums <- c(123456.7, 0.5, 100000, 1e15, 1e-5)
show <- function(lbl) { z <- json_parse(j, simplify="coerce"); d <- json_parse(sub("^\\[","[{\"v\":", gsub(", ", "},{\"v\":", sub("\\]$","}]", j))), simplify="coerce", data_frame=TRUE)$v
  cat(sprintf("%-22s zujson: %s\n%-22s df col: %s\n%-22s as.character: %s\n%-22s c(nums,'a'): %s\n", lbl, paste(z, collapse=" | "), "", paste(d, collapse=" | "), "", paste(as.character(nums), collapse=" | "), "", paste(c(nums,"a"), collapse=" | "))) }
show("default")
options(OutDec=","); show("OutDec=','"); options(OutDec=".")
options(scipen=-5); show("scipen=-5"); options(scipen=100); show("scipen=100"); options(scipen=0)
options(digits=3); show("digits=3"); options(digits=7)
# round trip consequence: the coerced text is no longer a number R can read back
options(OutDec=","); x <- json_parse('[1.5, "a"]', simplify="coerce"); print(x); print(suppressWarnings(as.numeric(x[1]))); print(json_write(x))
