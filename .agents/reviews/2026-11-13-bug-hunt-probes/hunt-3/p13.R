source("pre.R")
rss <- function() as.numeric(system(paste("ps -o rss= -p", Sys.getpid()), intern=TRUE))/1024
big <- rep(list(list(a=1, b="xyz", c=1:3)), 3e6)
bigdf <- data.frame(a=1:5e6, b=as.character(1:5e6))
t0 <- system.time(json_write_raw(big))[3]; cat("uninterrupted write takes", t0, "s\n"); gc(); m0 <- rss()
hit <- function(f, delay) { system(sprintf("(sleep %s; kill -INT %d) &", delay, Sys.getpid())); tryCatch({ f(); "completed" }, interrupt = function(i) "interrupt", error = function(e) paste("ERROR", class(e)[1])) }
for (i in 1:6) cat("write:", hit(function() json_write_raw(big), 0.3 + 0.1*i), "| next:", json_write(list(a=1)), "\n")
for (i in 1:4) cat("ndjson list:", hit(function() json_write_ndjson(big), 0.3 + 0.2*i), "| next:", json_write_ndjson(list(1)), "")
for (i in 1:4) cat("df:", hit(function() json_write_raw(bigdf), 0.2 + 0.2*i), "| ndjson df:", hit(function() json_write_ndjson(bigdf), 0.5), "| next:", json_write(1), "\n")
Sys.sleep(1); gc(); gc(); cat("rss before", m0, "after", rss(), "\n")
