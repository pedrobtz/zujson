W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
sh <- function(tok, ...) { r <- tryCatch(json_parse(tok, ...), error=function(e) paste("ERR", class(e)[1], conditionMessage(e))); cat(sprintf("%-45s -> %s %s\n", tok, typeof(r), paste(format(r, digits=17), collapse=" "))) ; invisible(r)}
for (t in c("1","1.0","1e0","10e-1","-0","-0.0","0","[-0,1]","2147483647","2147483648","-2147483647","-2147483648","-2147483649",
  "[1,2147483648]","[-2147483648]","[-2147483648,null]","9223372036854775807","9223372036854775808","18446744073709551615","18446744073709551616","-9223372036854775808","-9223372036854775809",
  "1e308","1.7976931348623157e308","1.7976931348623158e308","1.7976931348623159e308","1e309","-1e309","[1e309,1]","[1e309,\"a\"]","4.9e-324","2e-324","3e-324","1e-400","-1e-400",
  "123456789012345678901234567890","123456789012345678901234567890.0","1.23456789012345678901234567890e29",
  "0.1","1E2","1e+2","[true,2]","[true,null]","[null]","[]","[1,null,2.5]","01","1.","-",".5","+1","NaN","Infinity","-Infinity","1e","0x10"))
  sh(t)
# differential: big integer raw path vs real path
set.seed(1)
bad <- 0
for (i in 1:20000) {
  nd <- sample(20:40,1); tok <- paste0(sample(1:9,1), paste(sample(0:9, nd-1, TRUE), collapse=""))
  a <- json_parse(tok); b <- json_parse(paste0(tok, ".0")); 
  if (!identical(a,b)) { bad <- bad+1; if (bad <= 5) cat("DIFF", tok, format(a,digits=17), format(b,digits=17), sprintf("%a %a", a, b), "\n") }
}
cat("bigint raw vs .0 diffs:", bad, "of 20000\n")
bad <- 0
for (i in 1:20000) {
  tok <- paste0(sample(1:9,1), ".", paste(sample(0:9, sample(1:25,1), TRUE), collapse=""), "e", sample(308:330,1))
  a <- json_parse(tok); b <- as.numeric(jsonlite::fromJSON(paste0("[",tok,"]")))
  # independent: is it > DBL_MAX midpoint? use Rmpfr-free check via string compare
  if (!identical(a, b)) { bad <- bad+1; if (bad <= 5) cat("DIFF", tok, format(a,digits=17), format(b,digits=17), "\n") }
}
cat("near-overflow vs jsonlite diffs:", bad, "\n")
