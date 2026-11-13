.libPaths(c(file.path(Sys.getenv("W"), "lib"), .libPaths())); library(zujson)
cat("locale:", Sys.getlocale("LC_CTYPE"), "\n")
d <- file.path(tempdir(), "zj"); dir.create(d, showWarnings=FALSE)
pu <- file.path(d, rawToChar(as.raw(c(0x63,0xc3,0xa9,0x2e,0x6a,0x73,0x6f,0x6e)))); writeBin(charToRaw("[1]"), pu)
cat("unmarked: exists", file.exists(pu), " readBin ok:", rawToChar(readBin(pu, "raw", 10)), "\n")
r <- tryCatch(json_parse_file(pu), error=function(e) paste(class(e)[1], conditionMessage(e))); print(r)
pm <- pu; Encoding(pm) <- "UTF-8"
cat("utf8-marked: exists", suppressWarnings(file.exists(pm)), "\n")
r <- withCallingHandlers(tryCatch(json_parse_file(pm), error=function(e) paste(class(e)[1], conditionMessage(e))), warning=function(w) {cat("WARNING:", conditionMessage(w), "\n"); invokeRestart("muffleWarning")}); print(r)
