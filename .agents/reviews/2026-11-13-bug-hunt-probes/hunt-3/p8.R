source("pre.R")
set.seed(42)
bits <- function(n) { r <- matrix(as.raw(sample(0:255, 8*n, TRUE)), nrow=8); readBin(as.vector(r), "double", n=n, size=8) }
x <- c(bits(200000), 2^(0:1023), -2^(0:1023), 2^-(1:1074), 2^63*(1+c(-1,1)*2^-52), -2^63*(1+c(-1,1)*2^-52), 2^53+(-3:3), -(2^53)+(-3:3), 10^(-320:308), round(runif(1000,-1e18,1e18)), runif(1000)*1e16, c(0.5,1.5,-0.5)+2^52, .Machine$integer.max+(-1:1), -.Machine$integer.max-(0:2))
x <- x[is.finite(x)]
tmp <- tempfile(fileext=".json"); writeBin(json_write_raw(x), tmp)
hexf <- tempfile(); writeLines(sprintf("%a", x), hexf)
py <- 'import json,sys
v=json.load(open(sys.argv[1],"rb")); h=[float.fromhex(l) for l in open(sys.argv[2])]
assert len(v)==len(h),(len(v),len(h))
bad=[(i,a,b) for i,(a,b) in enumerate(zip(v,h)) if float(a)!=b]
ints=sum(isinstance(a,int) for a in v)
wrongint=[(a,b) for a,b in zip(v,h) if isinstance(a,int) and (a!=int(b) or not b.is_integer())]
nonint=[(a,b) for a,b in zip(v,h) if isinstance(a,float) and b.is_integer() and -2**63<=b<2**63]
print("n",len(v),"mismatch",len(bad),bad[:5],"ints",ints,"wrongint",len(wrongint),"whole-in-range-not-int",len(nonint),nonint[:3])
'
pyf <- tempfile(fileext=".py"); writeLines(py, pyf); system2("python3", c("-I", pyf, tmp, hexf))
# round-trip through own parser and jsonlite
back <- json_parse(json_write(x)); cat("own roundtrip identical (as double):", identical(as.double(back), x), "\n")
jl <- jsonlite::fromJSON(json_write(x)); cat("jsonlite equal:", isTRUE(all.equal(as.double(jl), x, tolerance=0)), "\n")
# int vs double storage
i <- c(0L, 1L, -1L, .Machine$integer.max, -.Machine$integer.max, NA)
cat("int vs dbl same:", identical(json_write(i), json_write(as.double(i))), identical(json_write(list(a=5L)), json_write(list(a=5))), "\n")
# hostile session
r0 <- json_write(list(1e5, 1e15, 0.1, 123456.7, 1e-5, 100000L, as.Date("2020-02-29"), as.POSIXct(1e9+0.9, tz="Asia/Tokyo")))
op <- options(OutDec=",", scipen=-5, digits=3); r1 <- json_write(list(1e5, 1e15, 0.1, 123456.7, 1e-5, 100000L, as.Date("2020-02-29"), as.POSIXct(1e9+0.9, tz="Asia/Tokyo"))); options(op)
cat(r0, "\nhostile same:", identical(r0, r1), "\n")
# count bytes
s <- c("a", "é", "\U0001F600", "\t", " "); cat("bytes raw == nchar(bytes):", length(json_write_raw(s)) == nchar(json_write(s), "bytes"), Encoding(json_write(s)), Encoding(json_write_ndjson(list(s))), "\n")
# strings fuzz vs python: all BMP + astral sample
cp <- c(1:0xD7FF, 0xE000:0xFFFF, sample(0x10000:0x10FFFF, 5000)); ss <- intToUtf8(cp, multiple=TRUE)
writeBin(json_write_raw(list(k=ss)), tmp); cpf <- tempfile(); writeLines(as.character(cp), cpf)
py2 <- 'import json,sys
v=json.load(open(sys.argv[1],"rb"))["k"]; c=[int(l) for l in open(sys.argv[2])]
print("strings n",len(v),"mismatch",sum(1 for a,b in zip(v,c) if a!=chr(b)), len(v)==len(c))
'
writeLines(py2, pyf); system2("python3", c("-I", pyf, tmp, cpf))
cat("own string roundtrip:", identical(json_parse(json_write(ss)), ss), " as keys:", identical(names(json_parse(json_write(setNames(seq_along(ss), ss)))), ss), "\n")
