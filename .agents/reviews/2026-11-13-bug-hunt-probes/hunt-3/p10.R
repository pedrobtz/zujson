source("pre.R")
cat("locale:", Sys.getlocale("LC_CTYPE"), " utf8:", l10n_info()$`UTF-8`, " latin1:", l10n_info()$`Latin-1`, "\n")
nat <- rawToChar(as.raw(c(0x63,0x61,0x66,0xe9)))   # native, unmarked: "caf\xe9"
u8 <- "café"; l1 <- nat; Encoding(l1) <- "latin1"
try_(charToRaw(json_write(nat))); try_(charToRaw(json_write(u8))); try_(charToRaw(json_write(l1)))
try_(charToRaw(json_write(setNames(1, nat)))); try_(charToRaw(json_write(factor(nat))))
try_(charToRaw(json_write_ndjson(list(nat))))
try_(json_write_raw("日本")); try_(charToRaw(json_write_ndjson(list("日本"))))
x <- json_write_ndjson(list("日本", u8)); cat("ndjson Encoding:", Encoding(x), " raw equal to per-record:", identical(charToRaw(x), c(json_write_raw("日本"), as.raw(10), json_write_raw(u8), as.raw(10))), "\n")
try_(identical(json_write_ndjson_raw(list("日本", u8)), c(json_write_raw("日本"), as.raw(10), json_write_raw(u8), as.raw(10))))
try_(json_parse(json_write(u8)) == u8)
d <- data.frame(a=1); d$b <- list(1,2)[1]; names(d)[1] <- u8
r <- tryCatch(json_write(structure(list(a=1:2, b=1:3), names=c("a", "日本"), class="data.frame")), error=function(e) e); cat(class(r)[1], "| msg enc:", Encoding(conditionMessage(r)), "| bytes:", paste(charToRaw(conditionMessage(r))[1:14], collapse=" "), "\n"); print(conditionMessage(r))
