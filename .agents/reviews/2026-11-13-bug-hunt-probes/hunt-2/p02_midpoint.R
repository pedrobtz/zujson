W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
mid <- "179769313486231580793728971405303415079934132710037826936173778980444968292764750946649017977587207096330286416692887910946555547851940402630657488671505820681908902000708383676273854845817711531764475730270069855571366959622842914819860834936475292719074168444365510704342711559699508093042880177904174497792"
dec <- function(s) { # s-1 as decimal string
  d <- as.integer(strsplit(s,"")[[1]]); i <- length(d); while (d[i]==0) { d[i] <- 9; i <- i-1 }; d[i] <- d[i]-1; paste(d, collapse="") }
below <- dec(mid)
for (t in list(c("mid-1",below), c("mid",mid), c("mid-1 .0", paste0(below,".0")), c("mid .0", paste0(mid,".0")),
               c("short below","1.7976931348623158079e308"), c("short above","1.7976931348623158080e308"),
               c("17 sig above", "17976931348623158080e292"), c("neg mid-1", paste0("-",below)))) {
  r <- json_parse(t[2]); cat(sprintf("%-14s %s  validate=%s jsonlite=%s\n", t[1], format(r,digits=17), json_validate(t[2]), format(jsonlite::fromJSON(paste0("[",t[2],"]")),digits=17)))
}
# array / df / coerce contexts
print(json_parse(paste0("[",below,",1]")))
print(json_parse(paste0('[{"a":',below,'},{"a":1e400}]'), data_frame=TRUE))
print(json_parse('[1e400,"a",-1e400, 123456789012345678901234567890, true, null]', simplify="coerce"))
# locale
Sys.setlocale("LC_NUMERIC","de_DE.UTF-8"); print(Sys.localeconv()["decimal_point"])
print(json_parse("[1.5e400, 1.5, 123456789012345678901.5]")); print(json_parse("123456789012345678901234567890.75"))
