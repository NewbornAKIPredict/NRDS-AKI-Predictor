# Recompute GA / BW stratum statistics from the corrected Table 1 counts.
ne <- c(238, 374, 177, 83, 125)
ev <- c(45, 31, 23, 9, 10)
n <- ne + ev
lab <- c("<=28", "29-32", "33-34", "35-36", ">=37")
cat("=== GA 5 strata (Table 1 corrected) ===\n")
for (i in 1:5) {
  b <- binom.test(ev[i], n[i])
  w <- 1.959963984540054
  p <- ev[i] / n[i]; d <- 1 + w*w/n[i]
  cc <- (p + w*w/(2*n[i])) / d
  hh <- w*sqrt(p*(1-p)/n[i] + w*w/(4*n[i]*n[i])) / d
  cat(sprintf("  %-6s n=%4d ev=%3d rate=%5.1f%%  Wilson %.1f-%.1f  Exact %.1f-%.1f\n",
              lab[i], n[i], ev[i], 100*ev[i]/n[i],
              100*(cc-hh), 100*(cc+hh), 100*b$conf.int[1], 100*b$conf.int[2]))
}
cat(sprintf("  total n=%d events=%d\n", sum(n), sum(ev)))
cat(sprintf("  Fisher exact p = %.5g\n", fisher.test(cbind(ne, ev))$p.value))
cat(sprintf("  Chi-square   p = %.5g\n", chisq.test(cbind(ne, ev))$p.value))
cat(sprintf("  Cochran-Armitage trend p = %.6g\n",
            prop.trend.test(ev, n, score = 1:5)$p.value))

bne <- c(185, 297, 403, 94)
bev <- c(34, 22, 42, 19)
bn <- bne + bev
blab <- c("ELBW", "VLBW", "1500-2499", ">=2500")
cat("\n=== BW 4 strata ===\n")
for (i in 1:4) {
  b <- binom.test(bev[i], bn[i])
  w <- 1.959963984540054
  p <- bev[i] / bn[i]; d <- 1 + w*w/bn[i]
  cc <- (p + w*w/(2*bn[i])) / d
  hh <- w*sqrt(p*(1-p)/bn[i] + w*w/(4*bn[i]*bn[i])) / d
  cat(sprintf("  %-10s n=%4d ev=%3d rate=%5.1f%%  Wilson %.1f-%.1f  Exact %.1f-%.1f\n",
              blab[i], bn[i], bev[i], 100*bev[i]/bn[i],
              100*(cc-hh), 100*(cc+hh), 100*b$conf.int[1], 100*b$conf.int[2]))
}
cat(sprintf("  Fisher exact p = %.5g\n", fisher.test(cbind(bne, bev))$p.value))
cat(sprintf("  Cochran-Armitage trend p = %.6g\n",
            prop.trend.test(bev, bn, score = 1:4)$p.value))
