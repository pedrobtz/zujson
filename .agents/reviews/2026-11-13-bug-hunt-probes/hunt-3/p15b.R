# As p15.R, but counted by macOS leaks(1) rather than RSS.
W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W, "hunt-3/inj/lib"), .libPaths())); library(zujson)
lk <- function() { gc(); gc(); grep("leaks for", system(sprintf("leaks %d 2>/dev/null", Sys.getpid()), intern=TRUE), value=TRUE) }
s <- strrep("a", 1e7); js <- paste0('"', s, '"')
cat("baseline:", lk(), "\n")
for (i in 1:5) tryCatch(json_write_raw(s), error=function(e) NULL); cat("5 ok writes:", lk(), "\n")
for (kind in c(2, 1, 0)) {
  Sys.setenv(ZU_FAIL_OWN = kind)
  for (i in 1:5) tryCatch(if (kind == 0) json_parse(js) else json_write_raw(s), error = function(e) NULL)
  Sys.unsetenv("ZU_FAIL_OWN"); cat("after 5 failures in zu_own kind", kind, ":", lk(), "\n")
}
