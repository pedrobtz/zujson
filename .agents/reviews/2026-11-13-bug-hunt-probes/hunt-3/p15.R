# Injected-failure copy (hunt-3/inj): zu_own() fails after the native allocation exists but before R owns it.
W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W, "hunt-3/inj/lib"), .libPaths())); library(zujson)
rss <- function() { gc(); gc(); round(as.numeric(system(paste("ps -o rss= -p", Sys.getpid()), intern=TRUE))/1024) }
s <- strrep("a", 1e8); js <- paste0('"', s, '"')
for (kind in c(2, 1, 0)) {
  Sys.setenv(ZU_FAIL_OWN = kind); m0 <- rss()
  for (i in 1:8) r <- tryCatch(if (kind == 0) json_parse(js) else json_write_raw(s), error = function(e) conditionMessage(e))
  Sys.unsetenv("ZU_FAIL_OWN"); cat(sprintf("kind %d (%s): %s | rss %d -> %d MB after 8 failed calls\n", kind, c("yyjson_doc","yyjson_mut_doc","output buffer")[kind+1], r, m0, rss()))
}
