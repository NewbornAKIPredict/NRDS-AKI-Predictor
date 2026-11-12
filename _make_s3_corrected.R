# Regenerate Supplementary Figure S3 using the five GA categories of Table 1:
# < 28, 29-32, 33-34, 35-36 weeks and Others.
# Source: revision_output/subgroup_GA_corrected.csv (recomputed from the pooled
# 10-fold out-of-fold XGBoost predictions) + unchanged PDA / NSAID / overall rows.
ROOT <- "E:/NARDS/revision_output"
OUT  <- file.path(ROOT, "figures_for_manuscript")

g <- read.csv(file.path(ROOT, "subgroup_GA_corrected.csv"), stringsAsFactors = FALSE)
o <- read.csv(file.path(ROOT, "subgroup_analyses_GA_PDA_NSAID.csv"),
              stringsAsFactors = FALSE)
keep <- o[grepl("^(PDA|NSAIDs|Overall)", o$Subgroup), ]
names(keep) <- names(g)

# order: five Table 1 GA categories, <32w, >=32w, then PDA/NSAID/overall
g2 <- g[c(1,2,3,4,5,6,7), ]
s <- rbind(g2, keep)
s$Subgroup <- c("GA < 28 weeks", "GA 29-32 weeks", "GA 33-34 weeks",
                "GA 35-36 weeks", "GA Others",
                "GA <32 weeks", "GA >=32 weeks",
                "No PDA", "No NSAID exposure", "PDA present",
                "NSAID exposure", "Overall cohort")
write.csv(s, file.path(ROOT, "subgroup_analyses_CORRECTED.csv"), row.names = FALSE)

pp <- strsplit(as.character(s$CI), "-")
lo <- as.numeric(sapply(pp, "[", 1)); hi <- as.numeric(sapply(pp, "[", 2))
stopifnot(all(!is.na(lo)), all(!is.na(hi)))
grp <- ifelse(grepl("^GA", s$Subgroup), "#2C7FB8",
       ifelse(grepl("^PDA|PDA present", s$Subgroup), "#E08214",
       ifelse(grepl("NSAID", s$Subgroup), "#41AB5D", "#252525")))
y <- rev(seq_len(nrow(s)))

f3 <- file.path(OUT, "S3_subgroup_AUC_forest.png")
png(f3, width = 2500, height = 1500, res = 200)
par(mar = c(4.6, 8.5, 4.2, 15), mgp = c(2.6, 0.6, 0))
plot(NA, xlim = c(0.40, 1.00), ylim = c(0.3, nrow(s) + 1.0),
     axes = FALSE, xlab = "", ylab = "")
abline(v = 0.5,    lty = 3, col = "grey65", lwd = 1.2)
abline(v = 0.8572, lty = 2, col = "#737373", lwd = 1.2)
segments(lo, y, hi, y, col = grp, lwd = 2.4)
points(as.numeric(s$AUC), y, pch = 18, cex = 1.7, col = grp)
axis(1, at = seq(0.4, 1.0, 0.1), cex.axis = 0.92)
axis(2, at = y, labels = s$Subgroup, las = 1, cex.axis = 0.92, tick = FALSE)
mtext("AUC (bootstrap 95% CI)", side = 1, line = 2.9, cex = 1.05)
text(rep(1.015, nrow(s)), y,
     sprintf("%.4f (%.4f-%.4f)  n=%d", as.numeric(s$AUC), lo, hi, s$n),
     adj = 0, cex = 0.80, xpd = TRUE)
text(1.015, nrow(s) + 0.85, "AUC (95% CI)   n", adj = 0, cex = 0.86,
     xpd = TRUE, font = 2)
title(main = "Supplementary Figure S3. Subgroup discrimination of the revised XGBoost model",
      line = 2.0, cex.main = 1.18, adj = 0)
mtext("Dashed line = overall AUC 0.8572; dotted line = chance (0.50). Unpaired DeLong p: GA <32w vs >=32w = 0.315; PDA = 0.0048; NSAID = 2.3x10-5",
      side = 3, line = 0.35, cex = 0.82, adj = 0, col = "grey30")
legend("bottomleft",
       legend = c("Gestational age", "PDA", "NSAID exposure", "Overall"),
       fill = c("#2C7FB8", "#E08214", "#41AB5D", "#252525"),
       border = NA, cex = 0.88, bg = "white", horiz = TRUE)
dev.off()
cat("[S3 corrected] saved:", f3, "\n")
cat("DONE\n")
