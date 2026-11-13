.libPaths(c(file.path(Sys.getenv("W"), "lib"), .libPaths())); library(zujson)
t <- function(label, expr) {
  r <- tryCatch(expr, condition = function(e) paste0("<", paste(class(e), collapse="/"), "> ", conditionMessage(e)))
  cat(sprintf("%-34s %s\n", label, if (is.character(r) && length(r)==1 && startsWith(r,"<")) r else paste(deparse(r, control=c("keepNA","keepInteger","niceNames","showAttributes")), collapse="")))
}
p <- json_parse
t("null value keeps key", p('{"a":null,"b":1}'))
t("null value none", p('{"a":null}', simplify="none"))
t("df key esc vs literal", names(p('[{"\\u00e9":1},{"é":2}]', data_frame=TRUE)))
t("df key esc a", p('[{"\\u0061":1},{"a":2}]', data_frame=TRUE))
t("df key NFC vs NFD", names(p('[{"é":1},{"é":2}]', data_frame=TRUE)))
t("df bool/str coerce", p('[{"a":true},{"a":"x"},{"a":null}]', data_frame=TRUE, simplify="coerce")$a)
t("df int min", p('[{"a":-2147483648},{"a":1}]', data_frame=TRUE)$a)
t("df 1e309", p('[{"a":1e309},{"a":1}]', data_frame=TRUE)$a)
t("df all missing col", p('[{"a":null},{"b":null}]', data_frame=TRUE))
t("df key 'row.names' rt", json_write(p('[{"row.names":5,"names":1}]', data_frame=TRUE)))
t("df dup key case", names(p('[{"a":1,"A":2}]', data_frame=TRUE)))
t("df many rows same", dim(p(paste0("[", paste(rep('{"a":1,"b":"x"}', 1e4), collapse=","), "]"), data_frame=TRUE)))
t("df top-level obj of arrays", class(p('{"a":[{"x":1}]}', data_frame=TRUE)$a))
t("df dup key w/ null", p('[{"a":null,"a":null}]', data_frame=TRUE))
t("df dup key diff escape", p('[{"a":1,"\\u0061":2}]', data_frame=TRUE))
t("non-df dup key diff escape", p('{"a":1,"\\u0061":2}'))
t("df empty key + write", json_write(p('[{"":1}]', data_frame=TRUE)))
t("obj empty key write", json_write(p('{"":1}')))
t("obj empty key rt 2", json_write(p('{"":1,"a":2}')))
t("dbl rt -> int", p(json_write(c(1,2))))
t("df rt", {d <- data.frame(i=1:2, x=c(1.5,NA), s=c("a",NA), l=c(TRUE,NA)); identical(p(json_write(d), data_frame=TRUE), d)})
t("df rt all-NA col", str(p(json_write(data.frame(x=c(NA_real_,NA_real_), s=NA_character_)), data_frame=TRUE)))
# validate vs parse differential over mutated docs, and str vs raw
set.seed(42)
seeds <- c('{"a":[1,2.5,"x",null,true,false],"b":{"c":"\\u00e9\\n","d":-1e-3}}', '[{"id":1,"v":[1,2]},{"id":2,"v":null}]', '"str\\\\ing"', '[1e309,-0,0.0,12345678901234567890]', '  [ ]  ', '{"k":"\\ud83d\\ude00"}')
alphabet <- c(strsplit('{}[]",:\\ \n\t0123456789.eE+-truefalsnu', "")[[1]], "é", "\x01")
n <- 0; bad <- 0
for (i in 1:20000) {
  s <- sample(seeds, 1); ch <- strsplit(s, "")[[1]]
  k <- sample(1:3, 1)
  for (m in 1:k) { pos <- sample(length(ch), 1); op <- sample(3, 1); if (op==1) ch <- ch[-pos] else if (op==2) ch[pos] <- sample(alphabet,1) else ch <- append(ch, sample(alphabet,1), pos) }
  j <- paste(ch, collapse=""); if (!nzchar(j)) next; Encoding(j) <- "UTF-8"; n <- n+1
  v <- json_validate(j); vr <- json_validate(charToRaw(j))
  a <- tryCatch(list(ok=TRUE, val=p(j)), error=function(e) list(ok=FALSE, val=class(e)))
  b <- tryCatch(list(ok=TRUE, val=json_parse_raw(charToRaw(j))), error=function(e) list(ok=FALSE, val=class(e)))
  if (!a$ok && !inherits(structure(list(), class=a$val), "zujson_error")) { bad <- bad+1; cat("NON-ZUJSON ERROR:", j, "\n") }
  if (!identical(a, b) || v != vr || (v != a$ok && !identical(a$val[1], "zujson_depth_error") && !grepl("u0000", j))) { bad <- bad+1; cat("DIFF:", encodeString(j), v, vr, a$ok, b$ok, "\n") }
  if (a$ok) { # semantic round trip
    w <- tryCatch(json_write(a$val), error=function(e) e)
    if (inherits(w, "error")) { bad <- bad+1; cat("WRITE FAIL of parsed:", encodeString(j), conditionMessage(w), "\n") }
    else { r2 <- p(w); w2 <- json_write(r2); if (!identical(w, w2)) { bad <- bad+1; cat("UNSTABLE RT:", encodeString(j), w, w2, "\n") } }
    # data_frame & none & coerce must not raise non-zujson
    for (args in list(list(data_frame=TRUE), list(simplify="none"), list(simplify="coerce", data_frame=TRUE))) { r <- tryCatch(do.call(p, c(list(j), args)), error=function(e) e); if (inherits(r, "error") && !inherits(r, "zujson_error")) { bad <- bad+1; cat("NONZU", j, "\n") }
      if (!inherits(r, "error")) { w3 <- tryCatch(json_write(r), error=function(e) e); if (inherits(w3, "error") && !grepl("must all be named", conditionMessage(w3))) { bad <- bad+1; cat("WRITE FAIL (", names(args), "):", encodeString(j), conditionMessage(w3), "\n") } } }
    nd <- tryCatch(json_parse_ndjson(gsub("[\n]", " ", j)), error=function(e) e); if (inherits(nd, "error") || !identical(nd, list(a$val))) if (!grepl("^\\s*$", j)) { bad <- bad+1; cat("NDJSON DIFF:", encodeString(j), "\n") }
  }
}
cat("fuzz cases:", n, "bad:", bad, "\n")
