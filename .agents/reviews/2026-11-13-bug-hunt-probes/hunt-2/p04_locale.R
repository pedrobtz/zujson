W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
cat("locale:", Sys.getlocale("LC_CTYPE"), "\n")
t <- function(e) tryCatch(e, error=function(e) paste("ERR", paste(class(e),collapse="/"), conditionMessage(e)), warning=function(w) paste("WARN", conditionMessage(w)))
raw_doc <- as.raw(c(0x5b,0x22,0xc3,0xa9,0x22,0x5d))       # ["é"] UTF-8 bytes
s <- rawToChar(raw_doc)                                    # unknown encoding
cat("Encoding(s):", Encoding(s), "\n")
r1 <- t(json_parse(raw_doc)); r2 <- t(json_parse(s))
cat("raw :", r1, charToRaw(r1) |> paste(collapse=" "), Encoding(r1), "\n")
cat("str :", r2, charToRaw(r2) |> paste(collapse=" "), Encoding(r2), "\n")
cat("validate raw/str:", json_validate(raw_doc), t(json_validate(s)), "\n")
cat("ndjson str:", unlist(t(json_parse_ndjson(s))), "\n")
bad <- rawToChar(as.raw(c(0x5b,0x22,0xe9,0x22,0x5d)))      # ["\xe9"] invalid utf8
cat("invalid-utf8 str:", t(json_parse(bad)), "| validate:", t(json_validate(bad)), "| raw:", t(json_parse(charToRaw(bad))), "\n")
s8 <- s; Encoding(s8) <- "UTF-8"; cat("marked utf8:", t(json_parse(s8)), "\n")
l1 <- rawToChar(as.raw(c(0x5b,0x22,0xe9,0x22,0x5d))); Encoding(l1) <- "latin1"; r <- t(json_parse(l1)); cat("latin1:", r, paste(charToRaw(r),collapse=" "), "\n")
# file path
d <- tempfile(); dir.create(d); f <- file.path(d, "a.json"); writeBin(raw_doc, f); cat("file:", paste(charToRaw(t(json_parse_file(f))), collapse=" "), "\n")
