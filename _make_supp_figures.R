# Supplementary figures S2 and S3 for TP-2026-0897-CL revised manuscript.
# Pure base R graphics; no extra packages required. ASCII only (Windows GBK safe).
ROOT <- "E:/NARDS/revision_output"
OUT  <- file.path(ROOT, "figures_for_manuscript")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ---------------- S2: Boruta fold-wise selection stability ----------------
d <- read.csv(file.path(ROOT, "Fig2_Boruta_fold_stability.csv"),
              stringsAsFactors = FALSE)
cat("[S2] candidate predictors:", nrow(d),
    "| nonzero folds:", sum(d$ConfirmedFolds > 0), "\n")
d <- d[order(d$ConfirmedFolds, d$Feature), ]
col <- rep("#D9D9D9", nrow(d))
col[d$Group == "Tentative"] <- "#FDBE85"
col[d$Group == "Confirmed"] <- "#2C7FB8"
lab <- gsub("_", " ", d$Feature)
lab <- ifelse(nchar(lab) > 32, paste0(substr(lab, 1, 32), "..."), lab)

f2 <- file.path(OUT, "S2_Boruta_fold_stability.png")
png(f2, width = 2400, height = 2800, res = 200)
par(mar = c(4.6, 19, 3.8, 1.6), mgp = c(2.6, 0.6, 0))
bp <- barplot(d$ConfirmedFolds, names.arg = lab, horiz = TRUE, las = 1,
              col = col, border = "grey45", xlim = c(0, 10.6),
              cex.names = 0.66, axes = FALSE, space = 0.28)
axis(1, at = 0:10, cex.axis = 0.9)
abline(v = c(5.5, 10), lty = 2, col = "grey55")
mtext("Number of the 10 training folds in which the feature was confirmed",
      side = 1, line = 3.0, cex = 1.0)
title(main = "Supplementary Figure S2. Boruta feature-selection stability across the 10 training folds",
      line = 1.8, cex.main = 1.18, adj = 0)
mtext(sprintf("48 candidate predictors entered fold-wise Boruta; %d were confirmed in at least one fold, %d in all 10 folds",
              sum(d$ConfirmedFolds > 0), sum(d$ConfirmedFolds == 10)),
      side = 3, line = 0.35, cex = 0.85, adj = 0, col = "grey30")
legend("bottomright",
       legend = c("Confirmed", "Tentative", "Rejected"),
       fill = c("#2C7FB8", "#FDBE85", "#D9D9D9"),
       border = "grey45", cex = 0.95, bg = "white", title = "Final Boruta decision")
dev.off()
cat("[S2] saved:", f2, "\n")

# ---------------- S3: forest plot of subgroup AUCs ----------------
s <- read.csv(file.path(ROOT, "subgroup_analyses_GA_PDA_NSAID.csv"),
              stringsAsFactors = FALSE)
pp <- strsplit(as.character(s$CI), "-")
lo <- as.numeric(sapply(pp, "[", 1))
hi <- as.numeric(sapply(pp, "[", 2))
stopifnot(all(!is.na(lo)), all(!is.na(hi)))
grp <- ifelse(grepl("^GA", s$Subgroup), "#2C7FB8",
       ifelse(grepl("^PDA", s$Subgroup), "#E08214",
       ifelse(grepl("^NSAID", s$Subgroup), "#41AB5D", "#252525")))
y <- rev(seq_len(nrow(s)))

f3 <- file.path(OUT, "S3_subgroup_AUC_forest.png")
png(f3, width = 2500, height = 1500, res = 200)
par(mar = c(4.6, 8.5, 4.2, 15), mgp = c(2.6, 0.6, 0))
plot(NA, xlim = c(0.40, 1.00), ylim = c(0.3, nrow(s) + 1.0),
     axes = FALSE, xlab = "", ylab = "")
abline(v = 0.5,   lty = 3, col = "grey65", lwd = 1.2)
abline(v = 0.8572, lty = 2, col = "#737373", lwd = 1.2)
segments(lo, y, hi, y, col = grp, lwd = 2.4)
points(s$AUC, y, pch = 18, cex = 1.7, col = grp)
axis(1, at = seq(0.4, 1.0, 0.1), cex.axis = 0.92)
axis(2, at = y, labels = s$Subgroup, las = 1, cex.axis = 0.92, tick = FALSE)
mtext("AUC (bootstrap 95% CI)", side = 1, line = 2.9, cex = 1.05)
text(rep(1.015, nrow(s)), y,
     sprintf("%.4f (%.4f-%.4f)  n=%d", s$AUC, lo, hi, s$n),
     adj = 0, cex = 0.80, xpd = TRUE)
text(1.015, nrow(s) + 0.85, "AUC (95% CI)   n", adj = 0, cex = 0.86,
     xpd = TRUE, font = 2)
title(main = "Supplementary Figure S3. Subgroup discrimination of the revised XGBoost model",
      line = 2.0, cex.main = 1.18, adj = 0)
mtext("Dashed line = overall AUC 0.8572; dotted line = chance (0.50). Unpaired DeLong p: GA <32w vs >=32w = 0.013; PDA = 0.0048; NSAID = 2.3x10-5",
      side = 3, line = 0.35, cex = 0.82, adj = 0, col = "grey30")
legend("bottomleft",
       legend = c("Gestational age", "PDA", "NSAID exposure", "Overall"),
       fill = c("#2C7FB8", "#E08214", "#41AB5D", "#252525"),
       border = NA, cex = 0.88, bg = "white", horiz = TRUE)
dev.off()
cat("[S3] saved:", f3, "\n")
cat("DONE\n")
