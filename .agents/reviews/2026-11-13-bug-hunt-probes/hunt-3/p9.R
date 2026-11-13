source("pre.R")
set.seed(1)
days <- c(-719528:-719000, sample(-719528:2932896, 3e5), 2932500:2932896, -1:1, 11016:11020)
z <- json_parse(json_write(structure(as.double(days), class="Date")))
py <- 'import sys,datetime
e=datetime.date(1970,1,1).toordinal(); bad=0; n=0
for l in open(sys.argv[1]):
    d,s=l.split(); d=int(d); n+=1
    if d+e<1:
        continue
    if datetime.date.fromordinal(d+e).isoformat()!=s: bad+=1
print("dates checked",n,"bad",bad)
'
f <- tempfile(); writeLines(paste(days, z), f); pf <- tempfile(fileext=".py"); writeLines(py, pf); system2("python3", c("-I", pf, f))
# year 0000 (python has no year 0): compare with R's own formatting for y0
d0 <- -719528:-719163; cat("year 0 agree with R format:", identical(json_parse(json_write(structure(as.double(d0), class="Date"))), format(structure(d0, class="Date"), "%Y-%m-%d") |> (\(s) sprintf("%04d%s", as.integer(sub("-.*","",s)), sub("^[0-9]+","",s)))()), "\n")
secs <- c(sample(-62167219200:253402300799, 3e5), -62167219200, 253402300799, -86401:86401) 
frac <- secs + runif(length(secs))  # flooring: fraction must not change the second
z1 <- json_parse(json_write(structure(as.double(secs), class=c("POSIXct","POSIXt"))))
z2 <- json_parse(json_write(structure(frac, class=c("POSIXct","POSIXt"))))
ok <- floor(frac) == secs & frac <= 253402300799.99
cat("fraction floors to same second:", all(z1[ok] == z2[ok]), "n", sum(ok), "\n")
py2 <- 'import sys,datetime
bad=0;n=0;ex=[]
for l in open(sys.argv[1]):
    d,s=l.split(); d=int(d)
    if d < -62135596800: continue
    n+=1
    t=(datetime.datetime(1970,1,1)+datetime.timedelta(seconds=d)).strftime("%Y-%m-%dT%H:%M:%SZ")
    t=t.rjust(20,"0")
    if t!=s:
        bad+=1; ex.append((d,s,t))
print("times checked",n,"bad",bad,ex[:3])
'
writeLines(paste(sprintf("%.0f", secs), z1), f); writeLines(py2, pf); system2("python3", c("-I", pf, f))
# values just below a whole second / whole day: nextafter down
nb <- function(x) { x - abs(x) * .Machine$double.eps / 2 - ifelse(x == 0, 5e-324, 0) }
b <- c(0, 86400, -86400, 1e9, 1641600000, 86400*19000, 86400*c(1:20000), -86400*(1:20000)); bb <- nb(b); bb <- bb[bb < b[seq_along(bb)]]
zz <- json_parse(json_write(structure(bb, class=c("POSIXct","POSIXt"))))
ex <- json_parse(json_write(structure(floor(bb), class=c("POSIXct","POSIXt"))))
cat("just-below-boundary: n", length(bb), "differs from floor():", sum(zz != ex), "\n"); print(head(data.frame(secs=sprintf("%.17g", bb), got=zz, floor=ex)[zz != ex,], 8))
cat("hour field 24 anywhere:", sum(grepl("T24", zz)), "\n")
for (v in c(-5e-324, -1e-300, -1e-13, -7e-12, -8e-12, -1e-11, -1e-9)) cat(sprintf("%g -> %s\n", v, json_write(structure(v, class=c("POSIXct","POSIXt")))))
cat("realistic: ", json_write(as.POSIXct("1970-01-01", tz="UTC") + (0.3 - 0.1 - 0.2)), sprintf("%.3g", 0.3-0.1-0.2), "\n")
