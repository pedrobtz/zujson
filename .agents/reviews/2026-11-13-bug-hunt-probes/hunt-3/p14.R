source("pre.R")
cls <- function(e) tryCatch({e; "ok"}, error=function(e) paste(class(e), collapse="/"))
# R allocation failure while yyjson's output buffer / document is held
x <- rep(list(strrep("a", 1e6)), 300)   # 300 MB of output; CHARSXP shared so input is 1 MB
mem.maxVSize(400)                        # MB: the RAWSXP / CHARSXP result cannot be allocated twice
keep <- list()
for (i in 1:6) { r <- tryCatch({ keep[[length(keep)+1]] <- json_write_raw(x); "ok" }, error=function(e) paste(class(e), collapse="/")); cat("raw:", r, "\n") }
keep <- NULL; gc()
for (i in 1:3) { r <- tryCatch({ keep[[length(keep)+1]] <- json_write(c(x, i)); "ok" }, error=function(e) paste(class(e), collapse="/")); cat("chr:", r, "\n") }
keep <- NULL; invisible(gc()); mem.maxVSize(Inf)
cat("next:", json_write(list(a=1)), " rss MB:", as.numeric(system(paste("ps -o rss= -p", Sys.getpid()), intern=TRUE))/1024, "\n")
