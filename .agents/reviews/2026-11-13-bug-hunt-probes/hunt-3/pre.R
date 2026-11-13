W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(Sys.getenv("ZULIB", file.path(W, "lib")), .libPaths())); library(zujson)
try_ <- function(expr) {
  lab <- paste(deparse(substitute(expr)), collapse = " ")
  r <- withCallingHandlers(
    tryCatch(list(v = expr), error = function(e) list(e = e)),
    warning = function(w) { cat("  WARNING escaped:", conditionMessage(w), "\n"); invokeRestart("muffleWarning") })
  if (!is.null(r$e)) cat(sprintf("%-70s => ERR [%s] %s\n", substr(lab,1,70), paste(class(r$e), collapse="/"), conditionMessage(r$e)))
  else cat(sprintf("%-70s => %s\n", substr(lab,1,70), paste(format(r$v), collapse=" ")))
  invisible(r)
}
cat("--- time\n")
