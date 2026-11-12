suppressPackageStartupMessages({library(pROC)})
d <- read.csv("NestedCV_All_Predictions.csv")
cat("n=",nrow(d),"events=",sum(d$AKI_num),"\n")
map <- c("0"="GA >=37 weeks (others)", "1"="GA <=28 weeks", "2"="GA 29-32 weeks",
         "3"="GA 33-34 weeks", "4"="GA 35-36 weeks")
auc_ci <- function(o,p,B=1000,seed=2026){
  r <- roc(o,p,quiet=TRUE); a <- as.numeric(r$auc)
  set.seed(seed); v <- replicate(B,{i<-sample(seq_along(o),length(o),replace=TRUE)
    if(length(unique(o[i]))<2) return(NA); as.numeric(roc(o[i],p[i],quiet=TRUE)$auc)})
  v<-v[!is.na(v)]; c(a, quantile(v,0.025), quantile(v,0.975))
}
show <- function(lab, idx){
  o<-d$AKI_num[idx]; p<-d$XGB[idx]
  ci<-auc_ci(o,p)
  pr<-roc(o,p,quiet=TRUE)
  ap<-suppressWarnings(as.numeric(roc(o,p,quiet=TRUE)$auc))
  cat(sprintf("%-28s n=%4d ev=%3d  AUC=%.4f (%.4f-%.4f)  Brier=%.4f\n",
      lab,length(o),sum(o),ci[1],ci[2],ci[3],mean((p-o)^2)))
}
for (g in names(map)) show(map[[g]], d$GA_grp==g)
cat("\n-- dichotomised (corrected coding: 1,2 = <32w; 0,3,4 = >=32w) --\n")
show("GA <32 weeks (codes 1+2)", d$GA_grp %in% c(1,2))
show("GA >=32 weeks (codes 0,3,4)", d$GA_grp %in% c(0,3,4))
r1<-roc(d$AKI_num[d$GA_grp %in% c(1,2)], d$XGB[d$GA_grp %in% c(1,2)],quiet=TRUE)
r2<-roc(d$AKI_num[d$GA_grp %in% c(0,3,4)], d$XGB[d$GA_grp %in% c(0,3,4)],quiet=TRUE)
cat(sprintf("unpaired DeLong p (<32 vs >=32) = %.5g\n", roc.test(r1,r2,method="delong")$p.value))
cat("\n-- AUC-PR via PRROC-style trapezoid --\n")
apr <- function(o,p){ ord<-order(p,decreasing=TRUE); p<-p[ord]; o<-o[ord]
  tp<-cumsum(o); fp<-cumsum(1-o); prec<-tp/(tp+fp); rec<-tp/sum(o)
  sum(diff(c(0,rec))*prec[-1]+0.0) }
for (g in names(map)){i<-d$GA_grp==g; cat(sprintf("%-28s AUC-PR~%.4f\n",map[[g]],apr(d$AKI_num[i],d$XGB[i])))}
