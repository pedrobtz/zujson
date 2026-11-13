source("san_pre.R"); print(json_write(list(a=1, b=c(2^62, -2^63, 2^63)))); print(json_write(structure(-1e-20, class=c("POSIXct","POSIXt"))))
