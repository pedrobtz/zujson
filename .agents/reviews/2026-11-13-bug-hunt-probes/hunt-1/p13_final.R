.libPaths(c(file.path(Sys.getenv("W"), "lib"), .libPaths())); library(zujson)
t <- function(label, expr) { r <- tryCatch(expr, condition = function(e) paste0("<", paste(class(e), collapse="/"), "> ", conditionMessage(e))); cat(sprintf("%-30s %s\n", label, paste(format(r), collapse=" | "))) }
by <- '["\xe9"]'; Encoding(by) <- "bytes"
t("parse bytes", json_parse(by)); t("validate bytes", json_validate(by)); t("ndjson bytes", json_parse_ndjson(by)); t("file bytes", json_parse_file(by))
# POSIXlt column, minimal
d <- data.frame(id = 1:11); d$t <- as.POSIXlt(as.POSIXct("2024-01-01 00:00:00", tz = "UTC") + 0:10)
cat("nrow:", nrow(d), " class:", class(d$t)[1], " length(unclass):", length(unclass(d$t)), "\n")
w <- json_write(d); cat(substr(w, 1, 160), "\n")
t("ndjson first line", strsplit(json_write_ndjson(d), "\n")[[1]][1])
d3 <- data.frame(id = 1:3); d3$t <- as.POSIXlt(as.POSIXct("2024-01-01", tz = "UTC") + 0:2); t("3-row POSIXlt col", json_write(d3))
t("same via as.POSIXct", json_write(transform(d3, t = as.POSIXct(t))))
if (requireNamespace("bit64", quietly=TRUE)) t("integer64", json_write(bit64::as.integer64(c(1,2,2^40)))) else cat("no bit64\n")
t("difftime col", json_write(data.frame(d=as.difftime(c(1,2), units="hours"))))
t("ITime-like hms", json_write(structure(3600, class=c("hms","difftime"), units="secs")))
# warn=2
options(warn=2)
t("warn2 write", json_write(list(a=1.5, d=Sys.Date()[0], f=factor("a")))); t("warn2 parse", json_parse('[1e309, 12345678901234567890, "x"]', simplify="coerce")); t("warn2 df", dim(json_parse('[{"a":1},{"b":2}]', data_frame=TRUE))); t("warn2 file", json_parse_file(tempfile()))
t("warn2 file ok", {f <- tempfile(); writeLines("[1]", f); json_parse_file(f)})
