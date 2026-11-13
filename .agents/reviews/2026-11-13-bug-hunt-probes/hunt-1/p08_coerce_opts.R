.libPaths(c(file.path(Sys.getenv("W"), "lib"), .libPaths())); library(zujson)
j <- '[1.5,"a",100000,1e5,0.1,123456.789012345,1234567.1,1e15,2147483648,1e-5,0.30000000000000004]'
vals <- c(1.5,100000,1e5,0.1,123456.789012345,1234567.1,1e15,2147483648,1e-5,0.30000000000000004)
show <- function(lbl) { g <- json_parse(j, simplify="coerce")[-2]; a <- as.character(vals); cv <- c(vals, "a")[seq_along(vals)]
  cat(sprintf("%-22s zujson: %s\n%-22s as.chr: %s\n%-22s c(x,'a'): %s\n", lbl, paste(g, collapse=" "), "", paste(a, collapse=" "), "", paste(cv, collapse=" "))) }
show("default")
options(OutDec=","); show("OutDec=,"); options(OutDec=".")
options(scipen=-5); show("scipen=-5"); options(scipen=0)
options(scipen=100); show("scipen=100"); options(scipen=0)
options(digits=3); show("digits=3"); options(digits=7)
options(digits=22); show("digits=22"); options(digits=7)
cat(R.version.string, "\n")
# does it also affect data frame columns and ints?
options(OutDec=",", scipen=100)
print(json_parse('[{"a":1.5},{"a":"x"},{"a":100000}]', simplify="coerce", data_frame=TRUE))
print(json_parse('[12, "a", true, null]', simplify="coerce"))
# and the writer is unaffected?
print(json_write(c(1.5, 1e5, 1e-10, 1e20)))
print(json_parse("[1.5, 2,5]"))
