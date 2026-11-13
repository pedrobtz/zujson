source("pre.R")
s <- strrep("a", 6e8)
x <- list(s, s, s, s)   # four records of 600 MB: each fits an R string, the body (2.4 GB) does not
r <- tryCatch(json_write_ndjson(x), error = function(e) e)
cat("json_write_ndjson:", paste(class(r), collapse="/"), "|", if (inherits(r, "condition")) conditionMessage(r) else nchar(r, "bytes"), "\n")
r <- tryCatch(json_write_ndjson_raw(x), error = function(e) e)
cat("json_write_ndjson_raw:", paste(class(r), collapse="/"), "|", if (inherits(r, "condition")) conditionMessage(r) else length(r), "\n")
cat("next call:", json_write_ndjson(list(1)), "\n")
