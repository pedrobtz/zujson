.libPaths(c(file.path(Sys.getenv("W"), "lib"), .libPaths())); library(zujson)
t <- function(label, expr) {
  r <- tryCatch(expr, condition = function(e) paste0("<", paste(class(e), collapse="/"), "> ", conditionMessage(e)))
  cat(sprintf("%-30s %s\n", label, paste(format(if (is.raw(r)) rawToChar(r) else r), collapse=" | ")))
}
lt <- as.POSIXlt(c("2024-01-01 10:00:00","2024-06-02 11:30:00"), tz="UTC")
d <- data.frame(id=1:2); d$t <- lt
str(d); cat("nrow", nrow(d), "class col", class(d$t), "\n")
t("df POSIXlt col", json_write(d))
t("df POSIXlt ndjson", json_write_ndjson(d))
d1 <- data.frame(t = lt); t("df only POSIXlt col (data.frame())", json_write(d1)); cat(class(d1$t), "\n")
d2 <- data.frame(id=1:11); d2$t <- as.POSIXlt(Sys.time()+1:11, tz="UTC")
t("df 11 rows POSIXlt", json_write(d2))
t("list POSIXlt", json_write(list(t=lt)))
# matrix col / df col
d3 <- data.frame(id=1:2); d3$m <- matrix(1:4,2)
t("matrix col", json_write(d3))
d3b <- data.frame(id=1:2); d3b$m <- matrix(1:2,2)
t("matrix 1col col", json_write(d3b))
d4 <- data.frame(id=1:2); d4$d <- data.frame(p=1:2,q=c("a","b"))
t("df col", json_write(d4))
d4b <- data.frame(id=1:2); d4b$d <- data.frame(p=3:4)
t("df col 1 col", json_write(d4b))
d4c <- data.frame(id=1:2); d4c$d <- data.frame(p=3:4, q=5:6)
t("df col 2x2", json_write(d4c))
# first col decides nrow?
t("no rn, first col", json_write(structure(list(a=1:3,b=4:6), class="data.frame")))
t("rn says 2, cols 3", json_write(structure(list(a=1:3,b=4:6), class="data.frame", row.names=1:2)))
t("rn chr", json_write(structure(list(a=1:2), class="data.frame", row.names=c("x","y"))))
# Date / factor column with attributes
d5 <- data.frame(d=as.Date("2024-01-01")+0:1, f=factor(c("a","b")), p=as.POSIXct(c(0,60), tz="UTC", origin="1970-01-01"))
t("d5", json_write(d5))
# nested list col w/ named list & NULL
d6 <- data.frame(id=1:2); d6$l <- list(list(a=1), NULL)
t("d6", json_write(d6))
# df column I("x") len-1 vectors in list col
d7 <- data.frame(id=1:2); d7$l <- list(I(1), 2)
t("d7 I in list col", json_write(d7))
# difference: df vs list rows with auto_unbox FALSE
df <- data.frame(id=1:2, nm=c("a","b"))
rows <- lapply(1:2, function(i) as.list(df[i,]))
t("df noAU", json_write(df, auto_unbox=FALSE)); t("rows noAU", json_write(rows, auto_unbox=FALSE))
# named atomic vs list noAU
t("c(a=1,b=2) noAU", json_write(c(a=1,b=2), auto_unbox=FALSE)); t("list(a=1,b=2) noAU", json_write(list(a=1,b=2), auto_unbox=FALSE))
t("1:2 noAU", json_write(1:2, auto_unbox=FALSE)); t("list(1,2) noAU", json_write(list(1,2), auto_unbox=FALSE))
t("factor int levels in df", json_write(data.frame(f=structure(1:2, levels=1:2, class="factor"))))
t("Date lgl", json_write(structure(NA, class="Date")))
t("Date cplx", json_write(structure(1i, class="Date")))
t("factor on chr", json_write(structure(c("a","b"), levels=c("x","y"), class="factor")))
t("factor on list", json_write(structure(list(1L), levels=c("x","y"), class="factor")))
t("factor on lgl", json_write(structure(TRUE, levels=c("x","y"), class="factor")))
t("df class on env?", json_write(structure(list(a=sum), class="data.frame", row.names=1L)))
