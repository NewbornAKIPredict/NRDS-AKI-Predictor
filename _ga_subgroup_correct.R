# Recompute GA-stratified results using the VERIFIED coding:
#   GA code 0 = "Others" (unclassified/other GA, n=135, heterogeneous BW)
#   GA code 1 = <=28 weeks (60% ELBW)
#   GA code 2 = 29-32 weeks
#   GA code 3 = 33-34 weeks
#   GA code 4 = 35-36 weeks
suppressPackageStartupMessages(library(pROC))
d <- read.csv("NestedCV_All_Predictions.csv")
set.seed(2026)
boot_auc <- function(o, p, B = 1000) {
  v <- replicate(B, {
    i <- sample.int(length(o), length(o), replace = TRUE)
    if (length(unique(o[i])) < 2) return(NA_real_)
    as.numeric(roc(o[i], p[i], quiet = TRUE)$auc)
  })
  quantile(v[!is.na(v)], c(0.025, 0.975))
}
auc_pr <- function(o, p) {
  ord <- order(p, decreasing = TRUE); o <- o[ord]; p <- p[ord]
  tp <- cumsum(o); prec <- tp / seq_along(o); rec <- tp / sum(o)
  # stepwise integration over recall
  sum(diff(c(0, rec)) * prec)
}
row <- function(lab, idx) {
  o <- d$AKI_num[idx]; p <- d$XGB[idx]; a <- as.numeric(roc(o, p, quiet = TRUE)$auc)
  ci <- boot_auc(o, p)
  data.frame(Subgroup = lab, n = length(o), Events = sum(o),
             AUC = sprintf("%.4f", a), CI = sprintf("%.4f-%.4f", ci[1], ci[2]),
             AUC_PR = sprintf("%.4f", auc_pr(o, p)),
             Brier = sprintf("%.4f", mean((p - o)^2)))
}
L <- list(
  row("GA <=28 weeks",  d$GA_grp == 1),
  row("GA 29-32 weeks", d$GA_grp == 2),
  row("GA 33-34 weeks", d$GA_grp == 3),
  row("GA 35-36 weeks", d$GA_grp == 4),
  row("GA other / unclassified", d$GA_grp == 0),
  row("GA <32 weeks (codes 1+2)", d$GA_grp %in% c(1, 2)),
  row("GA >=32 weeks (codes 3+4)", d$GA_grp %in% c(3, 4)))
tab <- do.call(rbind, L)
r1 <- roc(d$AKI_num[d$GA_grp %in% c(1,2)], d$XGB[d$GA_grp %in% c(1,2)], quiet=TRUE)
r2 <- roc(d$AKI_num[d$GA_grp %in% c(3,4)], d$XGB[d$GA_grp %in% c(3,4)], quiet=TRUE)
p_del <- roc.test(r1, r2, method="delong")$p.value
cat(sprintf("DeLong p (<32 vs >=32, unknown excluded) = %.5g\n", p_del))
write.csv(tab, "revision_output/subgroup_GA_corrected.csv", row.names = FALSE)
print(tab)
cat("\n=== GA trend excluding unclassified (ordered codes 1-4) ===\n")
ne <- c(238,374,177,83); ev <- c(45,31,23,9); n <- ne+ev
cat(sprintf("Fisher p=%.5g  chi2 p=%.5g  trend p=%.6g\n",
  fisher.test(cbind(ne,ev))$p.value, chisq.test(cbind(ne,ev))$p.value,
  prop.trend.test(ev,n,score=1:4)$p.value))
cat("\n=== GA all 5 rows incl other (as in Table 1) ===\n")
ne5 <- c(238,374,177,83,125); ev5 <- c(45,31,23,9,10); n5<-ne5+ev5
cat(sprintf("Fisher p=%.5g  chi2 p=%.5g  trend(1..5) p=%.6g\n",
  fisher.test(cbind(ne5,ev5))$p.value, chisq.test(cbind(ne5,ev5))$p.value,
  prop.trend.test(ev5,n5,score=1:5)$p.value))
