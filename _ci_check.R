z <- qnorm(0.975)
wil <- function(x,n){p<-x/n; d<-1+z*z/n; c<-(p+z*z/(2*n))/d; h<-z*sqrt(p*(1-p)/n+z*z/(4*n*n))/d; 100*c(c-h,c+h)}
ex <- function(x,n){ 100*binom.test(x,n)$conf.int }
items <- list(
 c("GA<=28",45,283), c("GA29-32",31,405), c("GA33-34",23,200), c("GA35-36",9,92), c("GA>=37",10,135),
 c("T12 low",5,221), c("T12 mod",9,82), c("T12 high",19,32),
 c("T13 low",21,723), c("T13 mod",38,286), c("T13 high",59,106),
 c("BW ELBW",34,219), c("BW VLBW",22,319), c("BW1500",42,445), c("BW2500",19,113), c("BW unknown",1,19))
for (it in items){ nm<-it[1]; x<-as.numeric(it[2]); n<-as.numeric(it[3]); w<-wil(x,n); e<-ex(x,n)
 cat(sprintf("%-12s %4d/%-4d rate=%5.1f%%  Wilson %5.1f-%5.1f  Exact %5.1f-%5.1f\n", nm,x,n,100*x/n,w[1],w[2],e[1],e[2])) }
