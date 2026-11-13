W <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zujson/9d8fe22c-5204-4620-9ce4-e537ce57bd23/scratchpad/hunt"
.libPaths(c(file.path(W,"lib"), .libPaths())); library(zujson)
t <- function(e) tryCatch(e, error=function(e) paste("ERR", paste(class(e)[1:2],collapse="/"), conditionMessage(e)), warning=function(w) paste("WARN", conditionMessage(w)))
R <- function(...) as.raw(unlist(lapply(list(...), function(x) if (is.character(x)) utf8ToInt(x) else x)))
show <- function(lbl, x, ...) { r <- t(json_parse_ndjson(x, ...)); cat(sprintf("%-34s ", lbl)); if (is.character(r) && length(r)==1 && startsWith(r,"ERR")) cat(r, "\n") else cat(deparse(r, width.cutoff=200), "\n") }
show("basic", "1\n2\n"); show("no trailing nl", "1\n2"); show("crlf", "1\r\n2\r\n"); show("blank lines", "\n\n1\n\n \t\n2\n\n"); show("empty", ""); show("only blanks", "\n \r\n\t\n")
show("lone CR sep", "1\r2\r3"); show("CR CR LF", "1\r\r\n2"); show("last line CR", "1\n2\r"); show("only CR", "\r"); show("leading ws", "  1  \n\t2\t\n")
show("two values one line", "1 2\n3"); show("concat objs", '{"a":1}{"a":2}\n'); show("err line 3", "1\n\n[1,\n4"); show("err line w/ crlf", "1\r\n\r\n\r\n{bad}\r\n")
show("BOM first", R(0xef,0xbb,0xbf,"1\n2\n")); show("BOM on line 2", R("1\n",0xef,0xbb,0xbf,"2\n")); show("BOM only line", R("1\n",0xef,0xbb,0xbf,"\n2\n")); show("BOM then blank first", R(0xef,0xbb,0xbf,"\n1\n"))
show("NUL in line", R("1\n", 0x00, "\n2")); show("NUL after value", R("1", 0x00, "\n2")); show("NUL only", R(0x00)); show("VT line", R("1\n", 0x0b, "\n2")); show("FF line", R("1\n",0x0c,"\n"))
show("nbsp line", R("1\n", 0xc2,0xa0, "\n2")); show("U+2028 inside string", R('"a', 0xe2,0x80,0xa8, 'b"\n2')); show("NEL", R("1", 0xc2, 0x85, "2"))
show("escaped nl in string", '"a\\nb"\n"c"'); show("raw nl in string", '"a\nb"\n"c"'); show("str w/ CR raw", R('"a', 0x0d, 'b"\n'))
show("df per line", '[{"a":1},{"a":2}]\n{"a":1}\n', data_frame=TRUE); show("none", "[1,2]\n[]\n", simplify="none"); show("coerce", '[1,"a"]\n', simplify="coerce")
show("null lines", "null\nnull\n"); show("raw empty", raw(0)); show("nul string", "1\n\"\\u0000\"\n")
# equivalence: each record alone vs as line
docs <- c('{"a":[1,2,{"b":null}]}', '[1e400,-0,1.0]', '"\\ud83d\\ude00"', 'true', '[]', '{}', '[[],[{}]]', '123456789012345678901234567890')
a <- lapply(docs, json_parse); b <- json_parse_ndjson(paste(docs, collapse="\r\n")); c2 <- json_parse_ndjson(charToRaw(paste0(paste(docs, collapse="\n"), "\n")))
cat("line == single doc:", identical(a,b), identical(a,c2), "\n")
# line numbers on large input, error at a known line
n <- 5000; body <- rep("1", n); body[4321] <- "[1,,2]"; cat(t(json_parse_ndjson(paste(body, collapse="\n"))), "\n"); cat(t(json_parse_ndjson(paste(body, collapse="\r\n"))), "\n"); cat(t(json_parse_ndjson(paste(body, collapse="\n\n"))), "\n")
# error byte positions single doc
for (d in list("[1,,2]", " [1,,2]", R(0xef,0xbb,0xbf,"[1,,2]"), "[1, 2", '{"a":tru}', '["\\x"]', R('["', 0xff, '"]'), "", " ", "[1]x", R("[1]",0x00), R("[1,",0x00,"2]"), R('["a',0x00,'b"]'))) cat(sprintf("%-22s", paste(deparse(if (is.raw(d)) rawToChar(d[d!=0]) else d), collapse="")), t(json_parse(d)), "| validate", json_validate(d), "\n")
