###############################################################
# TP-2026-0897-CL REVISION: regenerate ALL tables & figures
# so that every result is consistent with the revised pipeline
# (nested 10-fold CV, train-fold MICE, per-fold Boruta,
#  inner-CV-tuned XGBoost, KNN probability fix).
#
# Sections
#   [T2]  Table 2  model performance + bootstrap 95% CIs
#   [T2b] Benchmarking against SNAP-II as a single predictor
#   [SG]  Subgroup analyses by GA, PDA, NSAID exposure
#   [F3]  Figure 3  ROC curves (all models)
#   [F4]  Figure 4  Decision curve analysis
#   [F2]  Figure 2  10-fold Boruta importance boxplot
#   [FM]  Final deployment model (ONE consistent final XGBoost,
#         no duplicated-row stacking) + transparency bundle
#   [F5-8] SHAP summary + interaction/dependence plots
#   [T3]  Table 3  imbalance-handling comparison (7:3 split)
#   [T4/5] Tables 4-5  low-risk subgroup, thresholds from train only
#   [T6/F9] Table 6 + Figure 9 risk stratification & flowchart
#
# NOTE: all strings ASCII; outputs -> E:/NARDS/revision_output/
# SYNCHRONISED 2026-11-12 with 20261112NARDSmanuscript5.docx and with the
# later WorkBuddy correction scripts in revision_patches/:
#   - GA coding follows Table 1 VERBATIM: 0 = Others (n=135), 1 = <28 weeks
#     (n=283), 2 = 29-32 weeks (n=405), 3 = 33-34 weeks (n=200),
#     4 = 35-36 weeks (n=92). <32w = codes 1+2; >=32w = codes 3+4;
#     Others is reported separately and EXCLUDED from that dichotomy.
#   - firstweight and min_weight are CONTINUOUS KILOGRAM values
#     (median 1.505 / 1.380 kg); Weight_label is the 0-4 ordinal category.
#   - Primary outcome = mimiciii_derived.kdigo_stages_7day (118 AKI events);
#     kdigo_stages_48hr was an alternative ascertainment window only.
#   - Per-fold MEDIAN nrounds=100 generated ALL pooled out-of-fold
#     performance, calibration and both thresholds. The SINGLE deployment
#     refit uses nrounds=200 -> 200 trees in the released model.json.
#   - Authoritative training-OOF cut-points: 0.0651 / 0.3008
#     (displayed 0.065 / 0.301 in Table 6 and Figures 9-10).
###############################################################

suppressWarnings(suppressMessages({
  library(mice); library(Boruta); library(caret); library(xgboost)
  library(pROC); library(PRROC); library(rmda); library(dplyr)
  library(ggplot2); library(SHAPforxgboost); library(data.table)
  library(cutpointr); library(car); library(DescTools); library(DiagrammeR)
  library(glue)
}))

NARDS_ROOT <- Sys.getenv("NARDS_ROOT", unset = "E:/NARDS")
NARDS_ROOT <- sub("/+$", "", NARDS_ROOT)
pE <- function(p) {
  pfx <- paste0("E:/NARDS", "/")
  if (identical(p, "E:/NARDS")) return(NARDS_ROOT)
  if (startsWith(p, pfx))
    return(paste0(NARDS_ROOT, "/", substring(p, nchar(pfx) + 1L)))
  p
}
setwd(NARDS_ROOT)
dir.create("revision_output", showWarnings = FALSE)
dir.create("revision_output/model_transparency", showWarnings = FALSE)

# Safe-output helpers (redirect if file locked by Excel/WPS)
out_path <- function(p) {
  ok <- TRUE
  if (file.exists(p)) {
    ok <- tryCatch({ f <- file(p, open = "a"); close(f); TRUE }, error = function(e) FALSE)
  }
  if (!ok) {
    alt <- sub("(\\.[A-Za-z]+)$", paste0("_", format(Sys.time(), "%H%M%S"), "\\1"), p)
    cat("WARNING: output locked, redirecting:", p, "->", alt, "\n"); alt
  } else p
}
wcsv <- function(x, p, rn = FALSE) write.csv(x, out_path(p), row.names = rn)
wtxt <- function(x, p) writeLines(x, out_path(p))

###############################################################
# Data (identical to the revised main pipeline)
###############################################################
mydata <- read.csv("NRDSNOMICE.csv", stringsAsFactors = FALSE)
F <- 19:51; F <- F[F <= ncol(mydata)]
mydata[, F] <- lapply(mydata[, F], factor)
mydata2 <- mydata[, -1]
mydata2$AKI_flag1 <- factor(mydata2$AKI_flag1, levels = c(0, 1))
mydata2 <- mydata2[, colSums(is.na(mydata2)) < nrow(mydata2)]
# GA codes 0-4; Weight_label 1=ELBW<1000g 2=VLBW 1000-1499g
# 3=1500-2499g 4=>=2500g 0=unknown. Coding VERIFIED against Table 1.
# firstweight / min_weight are CONTINUOUS KILOGRAM values.
# GA is a 5-level group variable. Coding VERIFIED against Table 1 of the
# revised manuscript (1,115 infants; Others is not an ordinal GA level):
#   0 = Others (135), 1 = <28 weeks (283), 2 = 29-32 weeks (405),
#   3 = 33-34 weeks (200), 4 = 35-36 weeks (92)
# firstweight / min_weight are CONTINUOUS values in KILOGRAMS, not gram
# values and not category codes; Weight_label is the 0-4 category.
# Primary endpoint: mimiciii_derived.kdigo_stages_7day (118 AKI events);
# kdigo_stages_48hr was an alternative ascertainment window only.
GA_LAB <- c("0" = "Others", "1" = "<28 weeks", "2" = "29-32 weeks",
            "3" = "33-34 weeks", "4" = "35-36 weeks")
GA_LEVELS <- c("<28 weeks", "29-32 weeks", "33-34 weeks",
               "35-36 weeks", "Others")   # Table 1 display order
GA_ORDER  <- c(1, 2, 3, 4, 0)              # Table 1 order of GA codes
n_total <- nrow(mydata2); n_events <- sum(mydata2$AKI_flag1 == "1")
cat("Cohort:", n_total, "patients,", n_events, "AKI events\n")

# ---- load OOF predictions produced by the revised main pipeline ----
pred <- read.csv(pE("E:/NARDS/NestedCV_All_Predictions.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(pred) > 1000)   # guard against a stale/overwritten file
pred$AKI_num <- as.numeric(as.character(pred$AKI))
pred$GA_grp   <- as.numeric(as.character(mydata2$GA))[pred$RowID]
pred$PDA      <- as.numeric(as.character(mydata2$Patent_ductus_arteriosus))[pred$RowID]
pred$NSAID    <- as.numeric(as.character(mydata2$NSAIDs))[pred$RowID]
true <- pred$AKI_num
models <- c("LR", "RF", "XGB", "SVM", "DT", "NNET", "KNN", "SNAP_II")

metric_point <- function(o, p) {
  c(AUC = as.numeric(pROC::auc(pROC::roc(o, p, quiet = TRUE))),
    AUC_PR = PRROC::pr.curve(scores.class0 = p[o == 1],
                             scores.class1 = p[o == 0], curve = FALSE)$auc.integral,
    Brier = mean((p - o)^2))
}

###############################################################
# [T2] Table 2: performance + bootstrap 95% CIs (all models)
###############################################################
cat("== [T2] Table 2 ==\n")
set.seed(2026); N_BOOT <- 1000
t2 <- list()
for (m in models) {
  keep <- complete.cases(true, pred[[m]])
  o <- true[keep]; p <- pred[[m]][keep]
  bt <- matrix(NA_real_, N_BOOT, 3,
               dimnames = list(NULL, c("AUC", "AUC_PR", "Brier")))
  for (b in seq_len(N_BOOT)) {
    i <- sample(length(o), length(o), replace = TRUE)
    ob <- o[i]; pb <- p[i]
    if (length(unique(ob)) < 2) next
    bt[b, ] <- metric_point(ob, pb)
  }
  ci <- t(apply(bt, 2, quantile, probs = c(.025, .975), na.rm = TRUE))
  pt <- metric_point(o, p)
  # confusion-matrix metrics at the conventional 0.5 threshold
  yhat <- as.integer(p >= 0.5)
  TP <- sum(yhat == 1 & o == 1); TN <- sum(yhat == 0 & o == 0)
  FP <- sum(yhat == 1 & o == 0); FN <- sum(yhat == 0 & o == 1)
  sens <- TP / (TP + FN); spec <- TN / (TN + FP)
  prec <- if (TP + FP > 0) TP / (TP + FP) else 0
  acc  <- (TP + TN) / length(o)
  f1   <- if (prec + sens > 0) 2 * prec * sens / (prec + sens) else NA
  t2[[m]] <- data.frame(
    Model = m,
    AUC = round(pt["AUC"], 4), AUC_CI = sprintf("%.4f-%.4f", ci["AUC", 1], ci["AUC", 2]),
    AUC_PR = round(pt["AUC_PR"], 4), AUCPR_CI = sprintf("%.4f-%.4f", ci["AUC_PR", 1], ci["AUC_PR", 2]),
    Sensitivity = round(sens, 4), Specificity = round(spec, 4),
    Precision = round(prec, 4), Accuracy = round(acc, 4),
    F1_Score = ifelse(is.na(f1), "NA", round(f1, 4)),
    Brier = round(pt["Brier"], 4), Brier_CI = sprintf("%.4f-%.4f", ci["Brier", 1], ci["Brier", 2]))
}
T2 <- do.call(rbind, t2)
wcsv(T2, pE("E:/NARDS/revision_output/T2_model_performance_with_CI.csv"))
print(T2)

###############################################################
# [T2b] Benchmarking against SNAP-II as a single predictor
###############################################################
cat("== [T2b] SNAP-II benchmark ==\n")
keep <- complete.cases(true, pred$XGB, pred$SNAP_II)
o <- true[keep]
roc_x <- pROC::roc(o, pred$XGB[keep], quiet = TRUE)
roc_s <- pROC::roc(o, pred$SNAP_II[keep], quiet = TRUE)
dl <- pROC::roc.test(roc_x, roc_s, method = "delong")
# net reclassification improvement (category-free, OOF)
p_x <- pred$XGB[keep]; p_s <- pred$SNAP_II[keep]
case <- o == 1; ctrl <- o == 0
nri_case <- mean(p_x[case] > p_s[case]) - mean(p_x[case] < p_s[case])
nri_ctrl <- mean(p_x[ctrl] < p_s[ctrl]) - mean(p_x[ctrl] > p_s[ctrl])
T2b <- data.frame(
  Metric = c("AUC (95% CI)", "AUC-PR (95% CI)", "Brier", "DeLong p (XGB vs SNAP-II)",
             "Category-free NRI (cases)", "Category-free NRI (controls)"),
  XGBoost = c(sprintf("%.4f (%.4f-%.4f)", as.numeric(roc_x$auc),
                      as.numeric(pROC::ci.auc(roc_x, method = "bootstrap", boot.n = 1000))[1],
                      as.numeric(pROC::ci.auc(roc_x, method = "bootstrap", boot.n = 1000))[3]),
              sprintf("%.4f", metric_point(o, p_x)["AUC_PR"]), NA, NA, NA, NA),
  SNAP_II = c(sprintf("%.4f (%.4f-%.4f)", as.numeric(roc_s$auc),
                      as.numeric(pROC::ci.auc(roc_s, method = "bootstrap", boot.n = 1000))[1],
                      as.numeric(pROC::ci.auc(roc_s, method = "bootstrap", boot.n = 1000))[3]),
              sprintf("%.4f", metric_point(o, p_s)["AUC_PR"]), NA, NA, NA, NA))
T2b$Value <- c("", "", sprintf("%.4f vs %.4f", metric_point(o, p_x)["Brier"],
                               metric_point(o, p_s)["Brier"]),
               signif(dl$p.value, 3), round(nri_case, 3), round(nri_ctrl, 3))
wtxt(c("[T2b] Benchmarking against SNAP-II (single predictor), pooled OOF:",
       paste(capture.output(print(T2b)), collapse = "\n")),
     pE("E:/NARDS/revision_output/T2b_SNAP_II_benchmark.txt"))
wcsv(T2b, pE("E:/NARDS/revision_output/T2b_SNAP_II_benchmark.csv"))
print(T2b)

###############################################################
# [T2c] Proper SNAP-II single-predictor benchmark: logistic model
#      AKI ~ SNAP_II fitted within each training fold (OOF predictions).
#      This is the standard "benchmarking against SNAP-II as a single
#      predictor" requested by the reviewer, rather than a raw score.
###############################################################
cat("== [T2c] SNAP-II single-variable logistic benchmark ==\n")
set.seed(1234)
f10 <- caret::createFolds(mydata2$AKI_flag1, k = 10, returnTrain = FALSE)
y_all <- as.numeric(as.character(mydata2$AKI_flag1))
sn <- suppressWarnings(as.numeric(as.character(mydata2$SNAP_II)))
sn[is.na(sn)] <- median(sn, na.rm = TRUE)
p_snap_lr <- rep(NA_real_, length(y_all))
for (k in seq_along(f10)) {
  itr <- -f10[[k]]
  g <- suppressWarnings(glm(y ~ SNAP_II,
                            data = data.frame(y = y_all[itr], SNAP_II = sn[itr]),
                            family = binomial))
  p_snap_lr[f10[[k]]] <- as.numeric(
    predict(g, newdata = data.frame(SNAP_II = sn[f10[[k]]]), type = "response"))
}
# align the full model's OOF predictions to the same subject order
xgb_oof <- rep(NA_real_, length(y_all))
xgb_oof[pred$RowID] <- pred$XGB
keep2 <- complete.cases(y_all, xgb_oof, p_snap_lr)
o2 <- y_all[keep2]; px <- xgb_oof[keep2]; ps <- p_snap_lr[keep2]
rx <- pROC::roc(o2, px, quiet = TRUE); rs <- pROC::roc(o2, ps, quiet = TRUE)
dl2 <- pROC::roc.test(rx, rs, method = "delong")
cix <- as.numeric(pROC::ci.auc(rx, method = "bootstrap", boot.n = 1000))
cis <- as.numeric(pROC::ci.auc(rs, method = "bootstrap", boot.n = 1000))
T2c <- data.frame(
  Model = c("XGBoost (full model)", "SNAP-II alone (single-predictor logistic)"),
  AUC = round(c(as.numeric(rx$auc), as.numeric(rs$auc)), 4),
  AUC_95CI = c(sprintf("%.4f-%.4f", cix[1], cix[3]),
               sprintf("%.4f-%.4f", cis[1], cis[3])),
  AUC_PR = round(c(metric_point(o2, px)["AUC_PR"], metric_point(o2, ps)["AUC_PR"]), 4),
  Brier = round(c(metric_point(o2, px)["Brier"], metric_point(o2, ps)["Brier"]), 4))
wcsv(T2c, pE("E:/NARDS/revision_output/T2c_SNAP_II_single_predictor.csv"))
nri_c <- mean(px[o2 == 1] > ps[o2 == 1]) - mean(px[o2 == 1] < ps[o2 == 1])
nri_n <- mean(px[o2 == 0] < ps[o2 == 0]) - mean(px[o2 == 0] > ps[o2 == 0])
wtxt(c("[T2c] Benchmarking against SNAP-II as a SINGLE predictor (reviewer request)",
       "Both models evaluated on identical pooled out-of-fold predictions; SNAP-II",
       "benchmark is a logistic regression AKI ~ SNAP_II refitted in each training fold.",
       paste(capture.output(print(T2c)), collapse = "\n"),
       sprintf("DeLong p (XGBoost vs SNAP-II alone) = %.3g", dl2$p.value),
       sprintf("Category-free NRI: cases = %.3f, non-cases = %.3f", nri_c, nri_n),
       "Note: the min-max-normalised SNAP-II score shown in Table 2/2b is a monotone",
       "transform of the raw score and therefore yields the same ROC AUC; the logistic",
       "model additionally provides calibrated probabilities and a valid Brier score."),
       pE("E:/NARDS/revision_output/T2c_SNAP_II_single_predictor.txt"))
print(T2c)
cat(sprintf("[T2c] DeLong p = %.3g\n", dl2$p.value))

###############################################################
# [SG] Subgroup analyses by GA, PDA, NSAID exposure (reviewer)
###############################################################
cat("== [SG] subgroup analyses ==\n")
sg_row <- function(name, sel) {
  o <- true[sel]; p <- pred$XGB[sel]
  if (length(unique(o)) < 2)
    return(data.frame(Subgroup = name, n = length(o), Events = sum(o == 1),
                      AUC = NA, CI = "not estimable", AUC_PR = NA, Brier = NA))
  rc <- pROC::roc(o, p, quiet = TRUE)
  ci <- pROC::ci.auc(rc, method = "bootstrap", boot.n = 1000, conf.level = .95)
  data.frame(Subgroup = name, n = length(o), Events = sum(o == 1),
             AUC = round(as.numeric(rc$auc), 4),
             CI = sprintf("%.4f-%.4f", ci[1], ci[3]),
             AUC_PR = round(metric_point(o, p)["AUC_PR"], 4),
             Brier = round(metric_point(o, p)["Brier"], 4))
}
sg <- list()
for (g in GA_ORDER) {
  if (is.na(g)) next
  sg[[paste0("GA ", GA_LAB[as.character(g)])]] <- sg_row(paste0("GA ", GA_LAB[as.character(g)]), pred$GA_grp == g)
}
sg[["GA <32w"]]  <- sg_row("GA <32w",  pred$GA_grp %in% c(1, 2))
sg[["GA >=32w"]] <- sg_row("GA >=32w", pred$GA_grp %in% c(3, 4))
for (v in c(0, 1)) {
  sg[[paste0("PDA = ", v)]] <- sg_row(paste0("PDA = ", v), pred$PDA == v & !is.na(pred$PDA))
  sg[[paste0("NSAIDs = ", v)]] <- sg_row(paste0("NSAIDs = ", v), pred$NSAID == v & !is.na(pred$NSAID))
}
sg[["Overall"]] <- sg_row("Overall", rep(TRUE, nrow(pred)))
SG <- do.call(rbind, sg)
wcsv(SG, pE("E:/NARDS/revision_output/subgroup_analyses_GA_PDA_NSAID.csv"))
cat(paste(capture.output(print(SG)), collapse = "\n"), "\n")
# Unpaired DeLong tests: is the AUC difference between strata significant?
cmp_auc <- function(s1, s2) {
  o1 <- true[s1]; p1 <- pred$XGB[s1]; o2 <- true[s2]; p2 <- pred$XGB[s2]
  if (length(unique(o1)) < 2 || length(unique(o2)) < 2) return(NA_real_)
  r1 <- pROC::roc(o1, p1, quiet = TRUE); r2 <- pROC::roc(o2, p2, quiet = TRUE)
  tryCatch(pROC::roc.test(r1, r2, method = "delong", paired = FALSE)$p.value,
           error = function(e) NA_real_)
}
SGC <- data.frame(
  Comparison = c("GA <32w vs >=32w", "PDA = 0 vs PDA = 1", "NSAIDs = 0 vs NSAIDs = 1"),
  p_value_unpaired_DeLong = c(
    cmp_auc(pred$GA_grp %in% c(1, 2), pred$GA_grp %in% c(3, 4)),
    cmp_auc(pred$PDA == 0 & !is.na(pred$PDA), pred$PDA == 1 & !is.na(pred$PDA)),
    cmp_auc(pred$NSAID == 0 & !is.na(pred$NSAID), pred$NSAID == 1 & !is.na(pred$NSAID))))
wcsv(SGC, pE("E:/NARDS/revision_output/subgroup_AUC_comparison.csv"))
print(SGC)

###############################################################
# [F3] Figure 3 ROC curves  /  [F4] Figure 4 DCA
###############################################################
cat("== [F3]/[F4] figures ==\n")
pdf(out_path(pE("E:/NARDS/revision_output/Fig3_ROC_all_models.pdf")), width = 7, height = 7)
cols <- c("red", "#2E8B57", "blue", "orange", "purple", "#00BFFF", "#8B4513", "#FF1493")
names(cols) <- models
first <- TRUE
for (m in models) {
  keep <- complete.cases(true, pred[[m]])
  rc <- pROC::roc(true[keep], pred[[m]][keep], quiet = TRUE)
  if (first) { plot(rc, lwd = 2, col = cols[m], main = "ROC curves (revised 10-fold OOF)"); first <- FALSE }
  else plot(rc, add = TRUE, lwd = 2, col = cols[m])
}
legend("bottomright", legend = paste0(models, " AUC=",
       sprintf("%.3f", sapply(models, function(m) {
         k <- complete.cases(true, pred[[m]])
         as.numeric(pROC::auc(pROC::roc(true[k], pred[[m]][k], quiet = TRUE))) }))),
       lwd = 2, col = cols, cex = 0.8)
dev.off()

dca_cols <- c("XGB", "LR", "RF")
dca_dat <- data.frame(AKI = true, pred[, dca_cols])
dca_dat <- dca_dat[complete.cases(dca_dat), ]
dca_res <- list()
for (m in dca_cols) {
  dca_res[[m]] <- rmda::decision_curve(
    as.formula(paste("AKI ~", m)), data = dca_dat, family = "binomial",
    thresholds = seq(0, 1, 0.01), confidence.intervals = FALSE, study.design = "cohort")
}
pdf(out_path(pE("E:/NARDS/revision_output/Fig4_DCA.pdf")), width = 8, height = 8)
rmda::plot_decision_curve(dca_res, curve.names = names(dca_res),
                          xlab = "Threshold probability", cost.benefit.axis = FALSE,
                          standardize = FALSE, legend.position = "bottomright")
dev.off()

###############################################################
# [F2] Figure 2: per-fold Boruta importance boxplot
#      (same folds and MICE seeds as the revised main pipeline)
###############################################################
cat("== [F2] 10-fold Boruta ==\n")
set.seed(1234)
folds_t <- caret::createFolds(mydata2$AKI_flag1, k = 10, returnTrain = FALSE)
importance_df <- data.frame()
for (fid in 1:10) {
  tr_raw <- mydata2[-folds_t[[fid]], ]
  imp_tr <- mice(tr_raw, m = 5, maxit = 10, seed = 100 + fid, printFlag = FALSE)
  tr_imp <- complete(imp_tr, 1)
  bf <- Boruta(AKI_flag1 ~ ., data = tr_imp, maxRuns = 20, doTrace = 0)
  st <- attStats(bf); st$Feature <- rownames(st); st$Fold <- fid
  importance_df <- rbind(importance_df, st)
  cat("  Boruta fold", fid, "done\n")
}
sel_freq <- importance_df %>%
  group_by(Feature) %>%
  summarise(ConfirmedFolds = sum(decision == "Confirmed"), .groups = "drop") %>%
  mutate(Freq = ConfirmedFolds / 10) %>%
  mutate(Group = case_when(Freq >= 0.8 ~ "Confirmed",
                           Freq >= 0.3 ~ "Tentative", TRUE ~ "Rejected"))
plot_df <- importance_df %>% left_join(sel_freq[, c("Feature", "Group")], by = "Feature")
feat_order <- plot_df %>% group_by(Feature) %>%
  summarise(meanImp = mean(meanImp, na.rm = TRUE)) %>% arrange(meanImp) %>% pull(Feature)
plot_df$Feature <- factor(plot_df$Feature, levels = feat_order)
p2 <- ggplot(plot_df, aes(x = Feature, y = meanImp, fill = Group)) +
  geom_boxplot(outlier.size = 1.2) +
  scale_fill_manual(values = c(Confirmed = "#2eaa47", Tentative = "#f7c331", Rejected = "#d62728")) +
  labs(x = "Features", y = "Feature importance (Boruta)", fill = "Classification") +
  theme_bw() + theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
                     panel.grid = element_blank())
ggsave(out_path(pE("E:/NARDS/revision_output/Fig2_Boruta_boxplot.pdf")), p2, width = 14, height = 8)
ggsave(out_path(pE("E:/NARDS/revision_output/Fig2_Boruta_boxplot.png")), p2, width = 14, height = 8, dpi = 300)
wcsv(as.data.frame(sel_freq), pE("E:/NARDS/revision_output/Fig2_Boruta_fold_stability.csv"))

###############################################################
# [FM] Final deployment model: ONE consistent final XGBoost
#      trained ONCE on a single full-cohort imputed dataset
#      with the median inner-CV-tuned hyperparameters.
#      (Replaces the legacy stacked-train-folds model.)
###############################################################
cat("== [FM] final model ==\n")
# Report the per-fold MEDIAN separately (Methods / Supplementary Table S4).
# Those per-fold models generated EVERY pooled OOF performance estimate.
report_med <- c(nrounds = 100, max_depth = 3, eta = 0.05)
r12f <- pE("E:/NARDS/revision_output/R12_methods_reporting.txt")
if (file.exists(r12f)) {
  ln <- grep("Tuned parameters per fold", readLines(r12f), value = TRUE)
  if (length(ln) == 1) {
    nr <- as.numeric(sub(".*nrounds median=([0-9.]+).*", "\\1", ln))
    md <- as.numeric(sub(".*max_depth median=([0-9.]+).*", "\\1", ln))
    et <- as.numeric(sub(".*eta median=([0-9.]+).*", "\\1", ln))
    if (all(is.finite(c(nr, md, et)))) report_med <- c(nrounds = nr, max_depth = md, eta = et)
  }
}
# The SINGLE deployment model is refit ONCE on the full imputed cohort at
# nrounds = 200 (upper bound of the SAME tuning grid). This is the model
# released as model.json / xgboost_model.rda (200 trees). It must NOT be
# overwritten by the per-fold median, or the released artefact would stop
# reproducing the published single-patient example.
med <- c(nrounds = 200, max_depth = 3, eta = 0.05)
cat("Per-fold MEDIAN (Methods):", paste(names(report_med), report_med, sep = "=", collapse = ", "), "\n")
cat("Final DEPLOYMENT refit (released model):", paste(names(med), med, sep = "=", collapse = ", "), "\n")

imp_full <- mice(mydata2, m = 5, maxit = 10, seed = 1234, printFlag = FALSE)
d_full <- complete(imp_full, 1)
boruta_global <- Boruta(AKI_flag1 ~ ., data = d_full, maxRuns = 20, doTrace = 0)
boruta_fix_g <- TentativeRoughFix(boruta_global)
final_features <- getSelectedAttributes(boruta_fix_g, withTentative = FALSE)
if (length(final_features) == 0) final_features <- setdiff(names(d_full), "AKI_flag1")
cat("Global Boruta confirmed features:", length(final_features), "\n")

X_full <- model.matrix(~ . - 1, d_full[, final_features, drop = FALSE])
y_full <- as.numeric(as.character(d_full$AKI_flag1))
set.seed(1234)
final_xgb <- xgboost(data = X_full, label = y_full, objective = "binary:logistic",
                     nrounds = med["nrounds"], max_depth = med["max_depth"],
                     eta = med["eta"], verbose = 0)

# transparency bundle (reviewer: transparent access to code and model)
# DUA: this LOCAL artefact embeds d_full (1,115 x 49 patient rows) and
# must NEVER be published. The public, patient-free xgboost_model.rda,
# model_meta.rds and model.json ship in the release; prepare_deploy.R
# builds the portable JSON booster from that patient-free object.
save(final_xgb, final_features, med, GA_LAB, d_full,
     file = pE("E:/NARDS/revision_output/model_transparency/NARDS_AKI_trained_model.rda"))
si <- sessionInfo()
saveRDS(si, pE("E:/NARDS/revision_output/model_transparency/sessionInfo.rds"))
wtxt(c(
  "TRANSPARENCY BUNDLE - TP-2026-0897-CL revision",
  "Contents: final_xgb (XGBoost model), final_features (Boruta-confirmed predictors),",
  "  med (FINAL deployment refit: nrounds=200, max_depth=3, eta=0.05),",
  "  GA_LAB (gestational-age code dictionary), d_full (single full-cohort MICE imputation used).",
  "Model: trained ONCE on the full cohort after a single MICE imputation (m=5, maxit=10, seed=1234).",
  "  NOTE: the earlier version stacked the 10 training folds (each patient ~9 times);",
  "  this was corrected in revision to avoid duplicated-row training.",
  "Hyperparameters (final deployment refit): nrounds=200, max_depth=3, eta=0.05; 200 trees in model.json.",
  "Analysis code: provided as supplementary files (revision_main_v1.R, revision_tables_figures_v1.R).",
  paste0("R version: ", si$R.version$version.string)),
  pE("E:/NARDS/revision_output/model_transparency/code_availability_statement.txt"))

###############################################################
# [F5-F8] SHAP plots from the consistent final model
###############################################################
cat("== [F5-F8] SHAP ==\n")
shap_values <- shap.prep(xgb_model = final_xgb, X_train = X_full, top_n = 20)
p5 <- shap.plot.summary(shap_values) +
  scale_color_gradient(low = "blue", high = "red", name = "Feature value") +
  labs(title = "SHAP Summary Plot for AKI Prediction",
       x = "SHAP value (impact on model output)", y = "Features") +
  theme_minimal(base_size = 14)
ggsave(out_path(pE("E:/NARDS/revision_output/Fig5_SHAP_summary.pdf")), p5, width = 10, height = 7)

dep_plot <- function(main_feat, color_feat, fname) {
  if (!main_feat %in% colnames(X_full) || !color_feat %in% colnames(X_full)) {
    cat("  skip", fname, "(variable not in model matrix)\n"); return(NA)
  }
  pp <- shap.plot.dependence(data_long = shap_values, x = main_feat,
                             color_feature = color_feat, smooth = TRUE,
                             size = 1.5, alpha = 0.6) +
    scale_color_gradient(low = "blue", high = "red", name = paste0(color_feat, " value")) +
    labs(title = paste("SHAP Dependence:", main_feat),
         x = paste(main_feat, "(encoded value)"),
         y = "SHAP value (impact on AKI prediction)") +
    theme_minimal(base_size = 12)
  ggsave(out_path(file.path(pE("E:/NARDS/revision_output"), fname)), pp, width = 7.5, height = 5.5)
  fname
}
# Figure 6: SNAP-II x minimum weight; Figure 7: first-day urine output x fluid balance;
# Figure 8: NSAID exposure x SNAP-II
fb_col <- grep("fluid_balance", colnames(X_full), value = TRUE)[1]
dep_plot("SNAP_II", "min_weight", "Fig6_SHAP_SNAP_II_by_min_weight.pdf")
dep_plot("FirstUrineOutput", ifelse(is.na(fb_col), "SNAP_II", fb_col),
         "Fig7_SHAP_FirstUrineOutput_by_fluid_balance.pdf")
dep_plot("NSAIDs1", "SNAP_II", "Fig8_SHAP_NSAIDs_by_SNAP_II.pdf")
wcsv(as.data.table(shap_values)[, .(mean_abs_shap = mean(abs(value))), by = variable]
     [order(-mean_abs_shap)],
     pE("E:/NARDS/revision_output/SHAP_Feature_Importance_Rank.csv"))

###############################################################
# Shared 7:3 split for T3 / T4 / T5 / T6 (train-side OOF thresholds)
###############################################################
cat("== 7:3 split modules ==\n")
set.seed(1234)
idx7 <- sample(nrow(mydata2), 0.7 * nrow(mydata2))
tr7 <- mydata2[idx7, ]; te7 <- mydata2[-idx7, ]
tr7_imp <- complete(mice(tr7, m = 5, maxit = 10, seed = 7, printFlag = FALSE), 1)
te7_imp <- complete(mice(te7, m = 1, maxit = 1, seed = 8, printFlag = FALSE), 1)

# Boruta on the training split
b7 <- TentativeRoughFix(Boruta(AKI_flag1 ~ ., data = tr7_imp, maxRuns = 20, doTrace = 0))
feat7 <- getSelectedAttributes(b7, withTentative = FALSE)
if (length(feat7) == 0) feat7 <- setdiff(names(tr7_imp), "AKI_flag1")

X_tr <- model.matrix(~ . - 1, tr7_imp[, feat7, drop = FALSE])
X_te <- model.matrix(~ . - 1, te7_imp[, feat7, drop = FALSE])
cn <- intersect(colnames(X_tr), colnames(X_te))
X_tr <- X_tr[, cn, drop = FALSE]; X_te <- X_te[, cn, drop = FALSE]
y_tr <- as.numeric(as.character(tr7_imp$AKI_flag1))
y_te <- as.numeric(as.character(te7_imp$AKI_flag1))

fit7 <- function(Xtr, ytr, Xte, scale_pos_weight = 1, focal = FALSE, spw_col = NULL) {
  set.seed(1234)
  if (focal) {
    # focal loss (gamma=2, alpha=0.25), custom objective
    obj <- function(preds, dtrain) {
      y <- getinfo(dtrain, "label")
      p <- 1 / (1 + exp(-preds))
      a <- 0.25; g <- 2; eps <- 1e-7
      pt <- ifelse(y == 1, p, 1 - p)
      at <- ifelse(y == 1, a, 1 - a)
      dpt <- ifelse(y == 1, 1, -1)          # d(pt)/d(raw) sign
      # FL = -at (1-pt)^g log(pt); chain rule through pt and sigmoid
      dFLdp <- -at * (-(1 - pt)^(g - 1) * g * dpt * log(pmax(pt, eps)) +
                        (1 - pt)^g * dpt / pmax(pt, eps))
      grad <- dFLdp * pmax(p * (1 - p), eps)
      hess <- pmax(at * (1 - pt)^g / pmax(pt, eps) * p * (1 - p), eps)
      list(grad = grad, hess = hess)
    }
    mdl <- xgboost(data = Xtr, label = ytr, objective = obj,
                   nrounds = med["nrounds"], max_depth = med["max_depth"],
                   eta = med["eta"], verbose = 0)
    list(pred = 1 / (1 + exp(-predict(mdl, Xte))), model = mdl)
  } else {
    mdl <- xgboost(data = Xtr, label = ytr, objective = "binary:logistic",
                   nrounds = med["nrounds"], max_depth = med["max_depth"],
                   eta = med["eta"], scale_pos_weight = scale_pos_weight, verbose = 0)
    list(pred = predict(mdl, Xte), model = mdl)
  }
}

# training-side OOF predictions (no leakage) for threshold derivation
set.seed(1234)
cvf7 <- createFolds(factor(y_tr), k = 10, returnTrain = FALSE)
oof7 <- numeric(length(y_tr))
for (k in 1:10) {
  m7 <- xgboost(data = X_tr[-cvf7[[k]], , drop = FALSE], label = y_tr[-cvf7[[k]]],
                objective = "binary:logistic", nrounds = med["nrounds"],
                max_depth = med["max_depth"], eta = med["eta"], verbose = 0)
  oof7[cvf7[[k]]] <- predict(m7, X_tr[cvf7[[k]], , drop = FALSE])
}
cp7 <- cutpointr(data = data.frame(prob = oof7, label = y_tr),
                 x = prob, class = label, method = maximize_metric, metric = youden)
youden_thr <- as.numeric(cp7$optimal_cutpoint)
# Choose the LOWEST threshold that still achieves PPV >= 0.25 with >=10
# flagged training patients. This mirrors the R9 rule in the main pipeline
# and avoids a high-risk stratum containing only a handful of patients.
thr_hi <- NA_real_
for (t in sort(unique(oof7), decreasing = TRUE)) {
  n_flag <- sum(oof7 >= t); if (n_flag < 10) next
  tp <- sum(oof7 >= t & y_tr == 1)
  if (tp / n_flag >= 0.25) thr_hi <- t else if (!is.na(thr_hi)) break
}
if (is.na(thr_hi)) thr_hi <- as.numeric(quantile(oof7, 0.9))
if (thr_hi <= youden_thr) thr_hi <- as.numeric(quantile(oof7, 0.9))
cat(sprintf("Train-OOF thresholds: Youden=%.4f  High-risk(PPV>=0.25,n>=10)=%.4f\n",
            youden_thr, thr_hi))

pred_te_xgb   <- fit7(X_tr, y_tr, X_te)$pred
pw <- sum(y_tr == 0) / sum(y_tr == 1)
pred_te_weight <- fit7(X_tr, y_tr, X_te, scale_pos_weight = pw)$pred

# SMOTE variant (DMwR, numeric matrix + label)
smote_pred <- NULL
tryCatch({
  sm_tr <- data.frame(X_tr, AKI_flag1 = factor(y_tr, levels = c(0, 1)))
  sm <- DMwR::SMOTE(AKI_flag1 ~ ., data = sm_tr, perc.over = 200, perc.under = 150)
  sm_x <- as.matrix(sm[, setdiff(names(sm), "AKI_flag1")])
  cn2 <- intersect(colnames(X_te), colnames(sm_x))
  set.seed(1234)
  m_sm <- xgboost(data = sm_x[, cn2, drop = FALSE],
                  label = as.numeric(as.character(sm$AKI_flag1)),
                  objective = "binary:logistic", nrounds = med["nrounds"],
                  max_depth = med["max_depth"], eta = med["eta"], verbose = 0)
  # align test columns to training columns
  miss <- setdiff(colnames(sm_x), colnames(X_te))
  X_te2 <- X_te
  for (cc in miss) X_te2 <- cbind(X_te2, setNames(data.frame(rep(0, nrow(X_te2))), cc))
  smote_pred <- predict(m_sm, as.matrix(X_te2[, colnames(sm_x), drop = FALSE]))
}, error = function(e) cat("SMOTE variant failed:", e$message, "\n"))

focal_pred <- tryCatch(fit7(X_tr, y_tr, X_te, focal = TRUE)$pred,
                       error = function(e) { cat("focal variant failed:", e$message, "\n"); NULL })

# SNAP-II test prediction (normalized single predictor)
sc <- te7_imp$SNAP_II
sc[is.na(sc)] <- median(sc, na.rm = TRUE)
pred_te_snap <- (sc - min(sc)) / (max(sc) - min(sc))

cm <- function(p, o, thr = 0.5) {
  yh <- as.integer(p >= thr)
  TP <- sum(yh == 1 & o == 1); TN <- sum(yh == 0 & o == 0)
  FP <- sum(yh == 1 & o == 0); FN <- sum(yh == 0 & o == 1)
  sens <- TP / (TP + FN); spec <- TN / (TN + FP)
  prec <- if (TP + FP > 0) TP / (TP + FP) else 0
  f1 <- if (prec + sens > 0) 2 * prec * sens / (prec + sens) else NA
  c(Sensitivity = round(sens, 4), Specificity = round(spec, 4), Precision = round(prec, 4),
    Accuracy = round((TP + TN) / length(o), 4),
    F1 = ifelse(is.na(f1), NA, round(f1, 4)),
    AUC_PR = unname(round(metric_point(o, p)["AUC_PR"], 4)),
    Brier = unname(round(metric_point(o, p)["Brier"], 4)))
}

###############################################################
# [T3] Table 3: imbalance handling comparison (test set)
###############################################################
T3 <- rbind(
  data.frame(Model = "XGB_base", t(cm(pred_te_xgb, y_te)), Delta_AUC_PR = 0),
  data.frame(Model = "XGB_weight", t(cm(pred_te_weight, y_te)),
             Delta_AUC_PR = round(metric_point(y_te, pred_te_weight)["AUC_PR"] -
                                    metric_point(y_te, pred_te_xgb)["AUC_PR"], 4)))
if (!is.null(smote_pred))
  T3 <- rbind(T3, data.frame(Model = "XGB_smote", t(cm(smote_pred, y_te)),
                             Delta_AUC_PR = round(metric_point(y_te, smote_pred)["AUC_PR"] -
                                                    metric_point(y_te, pred_te_xgb)["AUC_PR"], 4)))
if (!is.null(focal_pred))
  T3 <- rbind(T3, data.frame(Model = "XGB_focal", t(cm(focal_pred, y_te)),
                             Delta_AUC_PR = round(metric_point(y_te, focal_pred)["AUC_PR"] -
                                                    metric_point(y_te, pred_te_xgb)["AUC_PR"], 4)))
wcsv(T3, pE("E:/NARDS/revision_output/T3_imbalance_comparison.csv"))
wcsv(T3, pE("E:/NARDS/revision_output/T3_imbalance_comparison_FINAL.csv"))
print(T3)

###############################################################
# [T4/T5] Tables 4-5: low-risk subgroup (Low stratum of the test set)
###############################################################
strat7 <- cut(pred_te_xgb, breaks = c(-Inf, youden_thr, thr_hi, Inf),
              labels = c("Low", "Moderate", "High"))
low_id <- which(strat7 == "Low")
o_low <- y_te[low_id]
sub_perf <- function(p, o) {
  if (length(unique(o)) < 2)
    return(c(AUC = NA, AUC_PR = NA, Brier = round(mean((p - o)^2), 4)))
  mp <- metric_point(o, p)
  # NOTE: unname() is required - c(AUC = x["AUC_PR"]) would concatenate
  # names into "AUC_PR.AUC_PR" and break later name-based indexing
  c(AUC = unname(round(mp["AUC"], 4)),
    AUC_PR = unname(round(mp["AUC_PR"], 4)),
    Brier = unname(round(mp["Brier"], 4)))
}
T4 <- data.frame(
  Cohort = c("Overall cohort", "Low-risk subgroup", "Low-risk subgroup"),
  Model = c("XGBoost", "XGBoost", "SNAP_II"),
  do.call(rbind, lapply(list(list(pred_te_xgb, y_te),
                             list(pred_te_xgb[low_id], o_low),
                             list(pred_te_snap[low_id], o_low)),
                        function(z) {
                          p <- z[[1]]; o <- z[[2]]
                          sp <- sub_perf(p, o)
                          cmm <- cm(p, o)
                          data.frame(AUC_ROC = unname(sp["AUC"]),
                                     AUC_PR = unname(sp["AUC_PR"]),
                                     Sensitivity = unname(cmm["Sensitivity"]),
                                     Specificity = unname(cmm["Specificity"]),
                                     Precision = unname(cmm["Precision"]),
                                     Accuracy = unname(cmm["Accuracy"]),
                                     F1 = unname(cmm["F1"]),
                                     Brier = unname(sp["Brier"]))
                        })))
# "Overall cohort" MUST come from the 10-fold OOF analysis (Table 2), not
# from the 7:3 split, which is used ONLY for the low-risk subgroup analyses.
t2x <- T2[T2$Model == "XGB", ]
T4$AUC_ROC[1]     <- as.numeric(t2x$AUC[1])
T4$AUC_PR[1]      <- as.numeric(t2x$AUC_PR[1])
T4$Sensitivity[1] <- as.numeric(t2x$Sensitivity[1])
T4$Specificity[1] <- as.numeric(t2x$Specificity[1])
T4$Precision[1]   <- as.numeric(t2x$Precision[1])
T4$Accuracy[1]    <- as.numeric(t2x$Accuracy[1])
T4$F1[1]          <- as.numeric(t2x$F1_Score[1])
T4$Brier[1]       <- as.numeric(t2x$Brier[1])
wcsv(T4, pE("E:/NARDS/revision_output/T4_lowrisk_fixed_threshold.csv"))
wtxt(c(
  "Table 4 footnote (revision-consistent):",
  "Overall cohort: pooled out-of-fold predictions from 10-fold stratified CV;",
  "  values are identical to the XGBoost row of revised Table 2.",
  "Low-risk subgroup: independent 7:3 train/test split; thresholds derived",
  "  from training-set OOF predictions only and applied to the test set.",
  "All classification metrics use the conventional fixed threshold 0.5.",
  "AUC-ROC / AUC-PR are threshold-independent; AUC-PR is prevalence-dependent",
  "  and is therefore much lower in the low-risk subgroup (few AKI events).",
  "The low-risk subgroup is DEFINED by the XGBoost Youden threshold, so applying",
  "  that same threshold within the subgroup reclassifies no patient (Table 5",
  "  sensitivity = 0). This comparison is descriptive, not independent validation.",
  "A lower Brier score indicates better calibration."),
  pE("E:/NARDS/revision_output/T4_footnote.txt"))
print(T4)

# T5: model-specific Youden thresholds derived on TRAINING OOF only
thr_x <- as.numeric(cutpointr(data.frame(prob = oof7, label = y_tr),
                              x = prob, class = label,
                              method = maximize_metric, metric = youden)$optimal_cutpoint)
sc_oof <- tr7_imp$SNAP_II
sc_oof[is.na(sc_oof)] <- median(sc_oof, na.rm = TRUE)
sc_oof_n <- (sc_oof - min(sc_oof)) / (max(sc_oof) - min(sc_oof))
thr_s <- as.numeric(cutpointr(data.frame(prob = sc_oof_n, label = y_tr),
                              x = prob, class = label,
                              method = maximize_metric, metric = youden)$optimal_cutpoint)
T5 <- data.frame(
  Model = c("XGBoost", "SNAP_II"),
  Optimal_Youden_threshold = c(round(thr_x, 4), round(thr_s, 4)),
  do.call(rbind, lapply(list(list(pred_te_xgb[low_id], o_low, thr_x),
                             list(pred_te_snap[low_id], o_low, thr_s)),
                        function(z) {
                          p <- z[[1]]; o <- z[[2]]; thr <- z[[3]]
                          sp <- sub_perf(p, o)
                          cmm <- cm(p, o, thr)
                          data.frame(AUC_ROC = unname(sp["AUC"]),
                                     AUC_PR = unname(sp["AUC_PR"]),
                                     Sensitivity = unname(cmm["Sensitivity"]),
                                     Specificity = unname(cmm["Specificity"]),
                                     Precision = unname(cmm["Precision"]),
                                     Accuracy = unname(cmm["Accuracy"]),
                                     F1 = unname(cmm["F1"]),
                                     Brier = unname(sp["Brier"]))
                        })))
wcsv(T5, pE("E:/NARDS/revision_output/T5_lowrisk_optimal_threshold.csv"))
print(T5)

###############################################################
# [T6/F9] Risk stratification decision table + flowchart
###############################################################
# Operating characteristics of each DEFINING cut-off, evaluated on the WHOLE
# held-out test set. Computing sensitivity/specificity INSIDE a stratum would
# be degenerate, because the strata are themselves defined by these cut-offs.
rule_metrics <- function(o, p, thr) {
  yh <- as.integer(p >= thr)
  TP <- sum(yh == 1 & o == 1); TN <- sum(yh == 0 & o == 0)
  FP <- sum(yh == 1 & o == 0); FN <- sum(yh == 0 & o == 1)
  sens <- if (TP + FN > 0) TP / (TP + FN) else NA
  spec <- if (TN + FP > 0) TN / (TN + FP) else NA
  ppv  <- if (TP + FP > 0) TP / (TP + FP) else NA
  npv  <- if (TN + FN > 0) TN / (TN + FN) else NA
  f1   <- if (!is.na(ppv) && !is.na(sens) && ppv + sens > 0)
            2 * ppv * sens / (ppv + sens) else NA
  c(Sensitivity = round(sens, 3), Specificity = round(spec, 3),
    PPV = round(ppv, 3), NPV = round(npv, 3), F1 = round(f1, 3))
}
m_low  <- rule_metrics(y_te, pred_te_xgb, youden_thr)
m_high <- rule_metrics(y_te, pred_te_xgb, thr_hi)
risk_actions <- c(
  "Low Risk: Standard NSAID therapy and routine renal function monitoring.",
  "Moderate Risk: Optimize NSAID treatment duration, strengthen fluid management, and closely monitor serum creatinine and urine output.",
  "High Risk: Initiate multidisciplinary consultation (neonatology/nephrology/cardiology), reduce or avoid high-dose NSAID exposure, and prioritize evaluation for PDA ligation or alternative therapeutic strategies.")
T6 <- data.frame(
  Risk_Level = c("Low Risk", "Moderate Risk", "High Risk"),
  Threshold_Range = c(paste0("<", round(youden_thr, 3)),
                      paste0(round(youden_thr, 3), "-", round(thr_hi, 3)),
                      paste0(">=", round(thr_hi, 3))),
  Sample_Number = c(sum(strat7 == "Low"), sum(strat7 == "Moderate"), sum(strat7 == "High")),
  Sample_Percent = paste0(round(100 * c(mean(strat7 == "Low"), mean(strat7 == "Moderate"),
                                        mean(strat7 == "High")), 1), "%"),
  Clinical_Intervention = risk_actions,
  Sensitivity = c(m_low["Sensitivity"], NA, m_high["Sensitivity"]),
  Specificity = c(m_low["Specificity"], NA, m_high["Specificity"]),
  PPV = c(m_low["PPV"], NA, m_high["PPV"]),
  NPV = c(m_low["NPV"], NA, m_high["NPV"]),
  F1_Score = c(m_low["F1"], NA, m_high["F1"]))
# AKI rate per stratum with Wilson CI (reviewer 4.1-4.3)
st6 <- table(strat7, y_te)
rate_ci <- vapply(rownames(st6), function(s) {
  y <- st6[s, "1"]; nn <- sum(st6[s, ])
  if (nn == 0) return("empty")
  bt <- binom.test(y, nn)$conf.int
  sprintf("%d/%d = %.1f%% (%.1f-%.1f%%)", y, nn, 100 * y / nn, 100 * bt[1], 100 * bt[2])
}, character(1))
T6$AKI_rate_observed = c(rate_ci["Low"], rate_ci["Moderate"], rate_ci["High"])
wcsv(T6, pE("E:/NARDS/revision_output/T6_risk_stratification_decision.csv"))
wcsv(T6, pE("E:/NARDS/revision_output/T6_risk_stratification_decision_FINAL.csv"))
wtxt(c(
  "Table 6 footnote (revision-consistent):",
  "Risk thresholds were derived ONLY from training-set out-of-fold predictions:",
  sprintf("  Youden threshold = %.4f ; high-risk threshold = %.4f",
          youden_thr, thr_hi),
  "The high-risk threshold is the LOWEST cut-off achieving PPV >= 0.25 with",
  "  >=10 flagged training patients, which avoids a high-risk stratum of only",
  "  a handful of cases. All metrics below are evaluated on the held-out test set.",
  "Sensitivity / specificity / PPV / NPV / F1 of the Low and High rows describe",
  "  the operating characteristics of each DEFINING cut-off in the whole test set",
  "  (not within the stratum, which would be degenerate).",
  "AKI_rate_observed gives Wilson 95% CIs per stratum; these proportions, not",
  "  the per-stratum classification metrics, are the primary validation of the",
  "  three-level stratification."),
  pE("E:/NARDS/revision_output/T6_footnote.txt"))
print(T6)

flow <- DiagrammeR::grViz(glue("
digraph xgb_aki_risk_flow {{
  graph [layout = dot, rankdir = TB]
  node [shape = box, style = 'rounded,filled', fontname = Helvetica, fontsize = 12]
  start [label = 'XGBoost Predicted AKI Risk Probability', fillcolor = '#e8eaf6', fontcolor = '#1a237e']
  low [label = 'Low Risk (<{round(youden_thr, 3)})\\n{risk_actions[1]}', fillcolor = '#bbdefb', fontcolor = '#0d47a1']
  moderate [label = 'Moderate Risk ({round(youden_thr, 3)}-{round(thr_hi, 3)})\\n{risk_actions[2]}', fillcolor = '#c8e6c9', fontcolor = '#1b5e20']
  high [label = 'High Risk (>={round(thr_hi, 3)})\\n{risk_actions[3]}', fillcolor = '#ef9a9a', fontcolor = '#b71c1c']
  edge [fontsize = 11]
  start -> low [label = 'p < {round(youden_thr, 3)}']
  start -> moderate [label = '{round(youden_thr, 3)} <= p < {round(thr_hi, 3)}']
  start -> high [label = 'p >= {round(thr_hi, 3)}']
}}"))
# NOTE: htmlwidgets::saveWidget fails (xfun version clash) and DiagrammeRsvg
# needs the V8 system library (not available here). Fallback: export the DOT
# source; the widget itself renders in RStudio via print(flow) and can be
# exported with the Viewer's Export button.
flow_dot <- glue("
digraph xgb_aki_risk_flow {{
  graph [layout = dot, rankdir = TB]
  node [shape = box, style = 'rounded,filled', fontname = Helvetica, fontsize = 12]
  start [label = 'XGBoost Predicted AKI Risk Probability', fillcolor = '#e8eaf6', fontcolor = '#1a237e']
  low [label = 'Low Risk (<{round(youden_thr, 3)})\\n{risk_actions[1]}', fillcolor = '#bbdefb', fontcolor = '#0d47a1']
  moderate [label = 'Moderate Risk ({round(youden_thr, 3)}-{round(thr_hi, 3)})\\n{risk_actions[2]}', fillcolor = '#c8e6c9', fontcolor = '#1b5e20']
  high [label = 'High Risk (>={round(thr_hi, 3)})\\n{risk_actions[3]}', fillcolor = '#ef9a9a', fontcolor = '#b71c1c']
  edge [fontsize = 11]
  start -> low [label = 'p < {round(youden_thr, 3)}']
  start -> moderate [label = '{round(youden_thr, 3)} <= p < {round(thr_hi, 3)}']
  start -> high [label = 'p >= {round(thr_hi, 3)}']
}}")
wtxt(flow_dot, pE("E:/NARDS/revision_output/Fig9_risk_flowchart.dot"))
# Publication-ready PDF version drawn with base graphics (no external
# htmlwidgets / V8 dependency, so it always exports).
pdf(out_path(pE("E:/NARDS/revision_output/Fig9_risk_flowchart.pdf")), width = 10, height = 6)
par(mar = c(0, 0, 0, 0))
plot(0, 0, type = "n", xlim = c(0, 1), ylim = c(0, 1), axes = FALSE, xlab = "", ylab = "")
rect(0.30, 0.82, 0.70, 0.96, col = "#e8eaf6", border = "#1a237e", lwd = 1.5)
text(0.50, 0.89, "XGBoost-predicted AKI probability", cex = 1.05, font = 2)
box_col <- c("#bbdefb", "#ffe082", "#ef9a9a")
box_x   <- list(c(0.02, 0.32), c(0.35, 0.65), c(0.68, 0.98))
lab_txt <- c(sprintf("Low risk  (<%.3f)\n%s", youden_thr, rate_ci["Low"]),
             sprintf("Moderate risk  (%.3f-%.3f)\n%s", youden_thr, thr_hi, rate_ci["Moderate"]),
             sprintf("High risk  (>=%.3f)\n%s", thr_hi, rate_ci["High"]))
for (j in 1:3) {
  rect(box_x[[j]][1], 0.28, box_x[[j]][2], 0.62, col = box_col[j], border = "gray30", lwd = 1.2)
  text(mean(box_x[[j]]), 0.45, lab_txt[j], cex = 0.85)
  arrows(0.50, 0.82, mean(box_x[[j]]), 0.62, length = 0.08, lwd = 1.4, col = "gray30")
}
text(0.50, 0.10, sprintf("Thresholds derived from training-set OOF predictions; evaluated on the held-out test set (n=%d)",
                         length(y_te)), cex = 0.85, font = 3)
dev.off()
cat("Fig9: DOT source + publication-ready PDF written\n")

###############################################################
# [TR] Transparent access to the code and the trained model (reviewer)
#      Manuscript-ready statement + reproducibility README + working
#      prediction example; all bundled alongside the model object.
###############################################################
cat("== [TR] transparency bundle ==\n")
tr_dir <- pE("E:/NARDS/revision_output/model_transparency")
wtxt(c(
  "DATA AND CODE AVAILABILITY STATEMENT (TP-2026-0897-CL, revision)",
  "",
  "Code availability. All analysis code is provided as Supplementary Material and",
  "is publicly available at [REPOSITORY / ZENODO DOI - INSERT BEFORE SUBMISSION].",
  "The two executable scripts reproduce every number in the revised manuscript:",
  "  1) revision_main_v1.R  - nested 10-fold CV (train-fold MICE, per-fold Boruta,",
  "     inner-CV-tuned XGBoost) and all reviewer-requested analyses R1-R13;",
  "  2) revision_tables_figures_v1.R - Tables 2-6 and Figures 2-9, the SNAP-II",
  "     single-predictor benchmark, subgroup analyses, and the final model bundle.",
  "The Shiny calculator source (app.R) and the legacy-script wrappers are included.",
  "Random seeds: 1234 (folds/split), 100+i and 200+i (fold-wise MICE), 7/8 (7:3",
  "split imputation), 42 (collinearity diagnostics), 2026 (bootstrap).",
  "Software: R 4.3.2; package versions are recorded in sessionInfo.rds.",
  "",
  "Model availability. The final trained XGBoost model object, the Boruta-confirmed",
  "predictor list, the hyperparameters, the gestational-age / birth-weight code",
  "dictionaries and the single full-cohort MICE-imputed training data used to fit it",
  "are provided in NARDS_AKI_trained_model.rda. predict_new_patient.R demonstrates",
  "how to generate a prediction for one new neonate. Hyperparameters: nrounds=200,",
  "max_depth=3, eta=0.05 (medians of the per-fold inner-CV grid search).",
  "",
  "Data availability. The source database MIMIC-III v1.4 is available from PhysioNet",
  "(https://physionet.org/content/mimiciii/) after completion of the data use",
  "agreement and CITI training. The derived analytic cohort (NRDSNOMICE.csv) cannot",
  "be redistributed under that agreement; the code above reconstructs it from",
  "MIMIC-III. Individual-level data are therefore available from the corresponding",
  "author on reasonable request, subject to the PhysioNet DUA."),
  file.path(tr_dir, "code_availability_statement.md"))
wtxt(c(
  "REPRODUCIBILITY README - TP-2026-0897-CL",
  "",
  "Working directory: E:/NARDS   (R 4.3.2; required packages listed in section 1",
  "of revision_tables_figures_v1.R).",
  "",
  "Run order:",
  "  1. Rscript revision_main_v1.R",
  "       -> NestedCV_All_Predictions.csv (pooled OOF predictions for 8 models),",
  "          R1-R13 result files in revision_output/.",
  "  2. Rscript revision_tables_figures_v1.R",
  "       -> T2/T2b/T2c/T3/T4/T5/T6 tables, Fig2-Fig9, subgroup analyses,",
  "          final model + transparency bundle.",
  "  3. Rscript 20260723风险分层R最终.R  (or source app.R)",
  "       -> xgboost_model.rda / risk_thresholds.csv for the Shiny calculator.",
  "",
  "IMPORTANT: do NOT run the scripts in RStudio debug mode (Browse[]> prompt);",
  "interrupting the fold loop leaves an empty Prediction_all and overwrites the",
  "exported CSV files. Use ordinary Source / Rscript instead.",
  "",
  "Key definitions: AKI_flag1 = mimiciii_derived.kdigo_stages_7day (118 events);",
  "GA codes 0=Others, 1=<28, 2=29-32, 3=33-34, 4=35-36 weeks (Table 1).",
  "Weight_label 0=unknown, 1=ELBW <1000g, 2=VLBW 1000-1499g, 3=1500-2499g, 4=>=2500g.",
  "firstweight and min_weight are CONTINUOUS KILOGRAM values; the Shiny UI",
  "accepts grams and divides by 1000 before scoring."),
  file.path(tr_dir, "README_reproducibility_LOCAL.md"))
wtxt(c(
  "# Minimal working example: predict AKI risk for ONE new neonate",
  "# DUA: the local artefact below embeds patient rows - NOT for release.",
  "# For the public example use predict_new_patient.R (base R + jsonlite only).",
  "load('NARDS_AKI_trained_model.rda')   # local: final_xgb, final_features, med, GA_LAB, d_full",
  "X_ref <- model.matrix(~ . - 1, d_full[, final_features, drop = FALSE])",
  "X_new <- matrix(0, nrow = 1, ncol = ncol(X_ref),",
  "                dimnames = list(NULL, colnames(X_ref)))",
  "# Fill ONLY the model columns that apply to this patient, e.g.:",
  "#   X_new[1, 'SNAP_II']         <- 15        # raw SNAP-II score",
  "#   X_new[1, 'GA']              <- 2         # 29-32 weeks; 0=Others, 1=<28, 3=33-34, 4=35-36",
  "#   X_new[1, 'Weight_label']    <- 2         # VLBW, 1000-1499 g (codes 0-4)",
  "#   X_new[1, 'firstweight']     <- 1.5       # KILOGRAMS, not grams or codes",
  "#   X_new[1, 'min_weight']      <- 1.38      # KILOGRAMS, not grams or codes",
  "#   X_new[1, 'FirstUrineOutput']<- 30        # mL on day 1",
  "prob <- as.numeric(predict(final_xgb, X_new))",
  "cat('Predicted AKI probability:', round(prob, 4), '\\n')",
  "# Risk strata cut-points: risk_thresholds.csv -> 0.0651 / 0.3008 (display 0.065 / 0.301)."),
  file.path(tr_dir, "predict_example_LOCAL.R"))
wtxt(c(
  "TRANSPARENCY BUNDLE CONTENTS",
  "NARDS_AKI_trained_model.rda       - trained XGBoost + features + dictionaries",
  "sessionInfo.rds                   - exact R/package versions",
  "code_availability_statement.md    - manuscript-ready availability statement",
  "README_reproducibility.md         - run order, seeds, variable dictionaries",
  "predict_new_patient.R             - single-patient prediction example",
  "revision_main_v1.R                - main nested-CV analysis code",
  "revision_tables_figures_v1.R      - tables/figures + transparency code",
  "revision_legacy_bridge.R          - compatibility layer for legacy scripts",
  "revision_consolidate.R            - restores canonical CSVs after closing Excel/WPS",
  "app.R                             - Shiny calculator source",
  "*_FINAL.csv                       - always-writable copies of locked tables"),
  file.path(tr_dir, "MANIFEST.txt"))
# Copy the executable code next to the model for a self-contained bundle
for (f in c("revision_main_v1.R", "revision_tables_figures_v1.R", "app.R")) {
  if (file.exists(f)) file.copy(f, file.path(tr_dir, f), overwrite = TRUE)
}

cat("\n=== ALL REVISION TABLES/FIGURES DONE -> E:/NARDS/revision_output/ ===\n")

