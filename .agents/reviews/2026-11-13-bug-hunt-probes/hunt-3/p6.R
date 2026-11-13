source("pre.R")
cls <- function(e) tryCatch({e; "ok"}, error=function(e) class(e)[1])
rss <- function() as.numeric(system(paste("ps -o rss= -p", Sys.getpid()), intern=TRUE))/1024
g <- function() { gc(); gc(); x <- gc(); c(Ncells=x[1,1], Vcells=x[2,1], rss=rss()) }
big <- data.frame(a=1:20000, s=sprintf("row%d", 1:20000)); big$l <- rep(list(1), 20000); big$l[[19999]] <- sum
bigl <- c(rep(list(list(a=1,b="x")), 5000), list(sum))
ok <- rep(list(list(a=1,b="x")), 5000)
run <- function(f, n) { for (i in 1:20) f(); a <- g(); for (i in 1:n) f(); b <- g(); for (i in 1:n) f(); c <- g(); print(rbind(a,b,c)) }
cat("fail df\n"); run(function() cls(json_write(big)), 200)
cat("fail ndjson df\n"); run(function() cls(json_write_ndjson(big)), 200)
cat("fail ndjson list\n"); run(function() cls(json_write_ndjson(bigl)), 200)
cat("ok ndjson list\n"); run(function() json_write_ndjson(ok), 200)
cat("ok write\n"); run(function() json_write(ok), 200)
cat("ok write raw\n"); run(function() json_write_raw(big[1:2]), 200)
cat("fail parse\n"); js <- paste0("[", paste(rep('{"a":[1,2,3]}', 5000), collapse=","), ',"\\u0000"]'); run(function() cls(json_parse(js)), 200)
