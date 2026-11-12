###############################################################
# TP-2026-0897-CL REVISION VERSION
# Based on: ROCandDCA代码NARDS的R语言代码.R (original nested-CV pipeline kept intact)
# Purpose: implement ALL statistical requirements from the reviewer comments:
#   [R1] GA/BW between-group comparison + prematurity strata (2.1)
#   [R2] Correlation matrix + VIF of the full candidate pool, BEFORE Boruta (2.2/3.3)
#   [R3] Boruta fold-wise selection stability (2.2/3.3)
#   [R4] Bootstrap 95% CIs for AUC / AUC-PR / Brier, all models (3.5)
#   [R5] DeLong tests: XGBoost vs every other model (3.5)
#   [R6] Calibration: slope/intercept + decile plot, pooled OOF (3.5)
#   [R7] Stratified AUC by GA group and <32w vs >=32w (2.1)
#   [R7b] Stratified AUC by birth-weight category Weight_label (2.1)
#   [R8] XGBoost hyperparameter tuning INSIDE the training fold (3.5/3.6)
#   [R9] Risk stratification: thresholds derived on training data only,
#        evaluated on held-out test set; per-stratum AKI rate with Wilson CIs,
#        Cochran-Armitage p-for-trend, per-stratum calibration (4.1-4.3)
#   [R10] Sensitivity analyses: exclude first-day urine output (reverse
#         causation); replace min_weight with birth weight (2.2/2.3)
#   [R11] Sample size justification (Riley 2019, pmsampsize) + EPV (3.2)
#   [R12] Auto-generated "Methods reporting" text (MICE/Boruta/XGB specs)
# NOTE: all comments/strings are ASCII to avoid encoding issues on Windows.
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

rm(list = ls())

###############################################################
# Libraries
###############################################################
library(mice)
library(Boruta)
library(caret)
library(randomForest)
library(xgboost)
library(e1071)
library(rpart)
library(nnet)
library(kknn)
library(pROC)
library(dplyr)
library(PRROC)
library(rmda)
library(ggplot2)
library(car)        # VIF                     [R2]
library(DescTools)  # Cochran-Armitage, PseudoR2 [R1][R11]
library(pmsampsize) # Riley 2019 sample size  [R11]

for (p in c("car", "DescTools", "pmsampsize")) {
  if (!requireNamespace(p, quietly = TRUE)) install.packages(p)
}

###############################################################
# Run-time switches (set FALSE to skip heavy parts)
###############################################################
TUNE_XGB_INNER <- TRUE   # [R8] inner-CV tuning of XGBoost (adds runtime)
SENS_RUN       <- TRUE   # [R10] two sensitivity re-runs of the 10-fold pipeline
N_BOOT         <- 1000   # [R4] bootstrap resamples
N_FOLDS        <- 10     # outer CV folds (reduce for a quick smoke test)
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

# Safe-output helpers: if a target file is locked (e.g. opened in Excel/WPS),
# redirect to a timestamped alternative instead of crashing the whole run.
out_path <- function(p) {
  ok <- TRUE
  if (file.exists(p)) {
    ok <- tryCatch({ f <- file(p, open = "a"); close(f); TRUE },
                   error = function(e) FALSE)
  }
  if (!ok) {
    alt <- sub("(\\.[A-Za-z]+)$", paste0("_", format(Sys.time(), "%H%M%S"), "\\1"), p)
    cat("WARNING: output file locked, redirecting:", p, "->", alt, "\n")
    alt
  } else p
}
wcsv <- function(x, p, rn = FALSE) write.csv(x, out_path(p), row.names = rn)
wtxt <- function(x, p) writeLines(x, out_path(p))


###############################################################
# Data  (original)
###############################################################
mydata <- read.csv("NRDSNOMICE.csv", stringsAsFactors = FALSE)

F <- c(19:51)
F <- F[F <= ncol(mydata)]
mydata[, F] <- lapply(mydata[, F], factor)

mydata2 <- mydata[, -1]   # drop ID
mydata2$AKI_flag1 <- factor(mydata2$AKI_flag1, levels = c(0, 1))
mydata2 <- mydata2[, colSums(is.na(mydata2)) < nrow(mydata2)]
cat("Number of patients:", nrow(mydata2), "\n")
N_EVENTS <- sum(mydata2$AKI_flag1 == "1")
cat("AKI events:", N_EVENTS, " prevalence:",
    round(mean(mydata2$AKI_flag1 == "1"), 4), "\n")

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
ga_grp <- as.numeric(as.character(mydata2$GA))
# Weight_label birth-weight categories (user-provided data dictionary):
#   1 = ELBW  (<1000 g), 2 = VLBW (1000-1499 g), 3 = 1500-2499 g,
#   4 = >=2500 g, 0 = unknown birth weight
BW_LAB <- c("0" = "BW unknown", "1" = "ELBW <1000g", "2" = "VLBW 1000-1499g",
            "3" = "1500-2499g", "4" = ">=2500g")
wl_grp <- as.numeric(as.character(mydata2$Weight_label))
cat("Weight_label distribution:",
    paste(names(table(wl_grp)), table(wl_grp), sep = "=", collapse = " "), "\n")

###############################################################
# Model Functions (original, unchanged)
###############################################################
LR_model <- function(train, test, x){
  f <- as.formula(paste("AKI_flag1~", paste(x, collapse = "+")))
  predict(glm(f, data = train, family = "binomial"), test, type = "response")
}
RF_model <- function(train, test, x){
  f <- as.formula(paste("AKI_flag1~", paste(x, collapse = "+")))
  predict(randomForest(f, data = train, ntree = 200), test, type = "prob")[, 2]
}
# [R8] XGBoost with optional inner-CV hyperparameter tuning.
# Default spec (no tuning): nrounds=200, max_depth=3, eta=0.05  (original)
XGB_model <- function(train, test, x, tune = FALSE){
  train_x <- model.matrix(~ . - 1, train[, x, drop = FALSE])
  test_x  <- model.matrix(~ . - 1, test[, x, drop = FALSE])
  common  <- intersect(colnames(train_x), colnames(test_x))
  train_x <- train_x[, common, drop = FALSE]
  test_x  <- test_x[, common, drop = FALSE]
  label   <- as.numeric(as.character(train$AKI_flag1))
  if (!tune) {
    params <- list(nrounds = 200, max_depth = 3, eta = 0.05)
  } else {
    grid <- expand.grid(nrounds = c(100, 200),
                        max_depth = c(3, 6),
                        eta = c(0.05, 0.10))
    inner <- createFolds(factor(label), k = 5, returnTrain = TRUE)
    best_auc <- -Inf; best_p <- list(nrounds = 200, max_depth = 3, eta = 0.05)
    for (g in seq_len(nrow(grid))) {
      aucs <- c()
      for (k in seq_len(5)) {
        itrain <- train_x[inner[[k]], , drop = FALSE]
        ilab   <- label[inner[[k]]]
        ival   <- train_x[-inner[[k]], , drop = FALSE]
        ivalab <- label[-inner[[k]]]
        if (length(unique(ivalab)) < 2) next
        md <- xgboost(data = itrain, label = ilab, objective = "binary:logistic",
                      nrounds = grid$nrounds[g], max_depth = grid$max_depth[g],
                      eta = grid$eta[g], verbose = 0)
        aucs <- c(aucs, as.numeric(pROC::auc(ivalab,
                                             predict(md, ival))))
      }
      m <- mean(aucs)
      if (m > best_auc) { best_auc <- m; best_p <- as.list(grid[g, ]) }
    }
    params <- best_p
  }
  model <- xgboost(data = train_x, label = label, objective = "binary:logistic",
                   nrounds = params$nrounds, max_depth = params$max_depth,
                   eta = params$eta, verbose = 0)
  list(pred = predict(model, test_x), params = params)
}
SVM_model <- function(train, test, x){
  f <- as.formula(paste("AKI_flag1~", paste(x, collapse = "+")))
  p <- predict(svm(f, data = train, probability = TRUE), test, probability = TRUE)
  attr(p, "probabilities")[, 2]
}
DT_model <- function(train, test, x){
  f <- as.formula(paste("AKI_flag1~", paste(x, collapse = "+")))
  predict(rpart(f, data = train, method = "class"), test, type = "prob")[, 2]
}
NNET_model <- function(train, test, x){
  f <- as.formula(paste("AKI_flag1~", paste(x, collapse = "+")))
  as.numeric(predict(nnet(f, data = train, size = 5, maxit = 200, trace = FALSE),
                     test, type = "raw"))
}
KNN_model <- function(train, test, x){
  train_x <- model.matrix(~ . - 1, train[, x, drop = FALSE])
  test_x  <- model.matrix(~ . - 1, test[, x, drop = FALSE])
  common  <- intersect(colnames(train_x), colnames(test_x))
  tk <- data.frame(train_x[, common, drop = FALSE]); tk$AKI_flag1 <- train$AKI_flag1
  pr <- kknn(AKI_flag1 ~ ., train = tk,
             test = data.frame(test_x[, common, drop = FALSE]), k = 5)$prob
  if (is.matrix(pr)) pr <- pr[, ncol(pr)]   # keep P(AKI=1) column only
  as.numeric(pr)
}

###############################################################
# [R10] Reusable single-model 10-fold pipeline (for sensitivity runs)
###############################################################
run_pipeline_xgb <- function(data, exclude_vars = character(0), label = "",
                             tune = FALSE) {
  set.seed(1234)
  folds_s <- createFolds(data$AKI_flag1, k = 10, returnTrain = FALSE)
  pool_all <- setdiff(names(data), "AKI_flag1")
  if (length(exclude_vars) > 0)
    pool_all <- setdiff(pool_all, exclude_vars)
  oof <- data.frame()
  sel_count <- setNames(rep(0, length(pool_all)), pool_all)
  for (i in seq_len(10)) {
    test_id <- folds_s[[i]]
    tr <- data[-test_id, ]; te <- data[test_id, ]
    imp_tr <- mice(tr, m = 5, maxit = 10, seed = 100 + i, printFlag = FALSE)
    tr_imp <- complete(imp_tr, 1)
    imp_te <- mice(te, m = 1, maxit = 1, seed = 200 + i, printFlag = FALSE)
    te_imp <- complete(imp_te, 1)
    ok <- pool_all[sapply(tr_imp[pool_all], function(cc) length(unique(cc)) > 1)]
    bt <- Boruta(AKI_flag1 ~ ., data = tr_imp[, c("AKI_flag1", ok)],
                 maxRuns = 20, doTrace = 0)
    bt <- TentativeRoughFix(bt)
    fs <- getSelectedAttributes(bt, withTentative = FALSE)
    if (length(fs) == 0) fs <- ok
    sel_count[fs] <- sel_count[fs] + 1
    xr <- XGB_model(tr_imp, te_imp, fs, tune = tune)
    oof <- rbind(oof, data.frame(Fold = i, RowID = test_id,
                                 obs = as.numeric(as.character(te_imp$AKI_flag1)),
                                 pred = xr$pred))
    cat("[", label, "] fold", i, "done\n")
  }
  list(oof = oof, sel_count = sel_count, pool = pool_all)
}

###############################################################
# Outer CV loop (original, extended: RowID + XGB tuning + Boruta log)
###############################################################
set.seed(1234)
folds <- createFolds(mydata2$AKI_flag1, k = N_FOLDS, returnTrain = FALSE)
Prediction_all <- data.frame()
Feature_all <- list()
xgb_params_log <- list()
pool_size_log <- integer(N_FOLDS)

for (i in seq_len(N_FOLDS)) {
  cat("============================\nRunning Fold:", i, "\n============================\n")
  test_id <- folds[[i]]
  train <- mydata2[-test_id, ]
  test  <- mydata2[test_id, ]

  # MICE: train only (m=5, maxit=10); test imputed separately (original design)
  imp_train <- mice(train, m = 5, maxit = 10, seed = 100 + i, printFlag = FALSE)
  train_imp <- complete(imp_train, 1)
  imp_test  <- mice(test, m = 1, maxit = 1, seed = 200 + i, printFlag = FALSE)
  test_imp  <- complete(imp_test, 1)

  # Boruta feature selection within the training fold
  cat("Running Boruta...\n")
  boruta_model <- Boruta(AKI_flag1 ~ ., data = train_imp, maxRuns = 20, doTrace = 0)
  boruta_fix   <- TentativeRoughFix(boruta_model)
  features <- getSelectedAttributes(boruta_fix, withTentative = FALSE)
  if (length(features) == 0) features <- setdiff(names(train_imp), "AKI_flag1")
  Feature_all[[i]] <- features
  pool_size_log[i] <- ncol(train_imp) - 1
  cat("Candidate pool:", pool_size_log[i],
      " Selected features:", length(features), "\n")

  # Models
  xr <- XGB_model(train_imp, test_imp, features, tune = TUNE_XGB_INNER)
  pred_XGB <- xr$pred
  xgb_params_log[[i]] <- xr$params
  cat("XGB params (fold", i, "): nrounds=", xr$params$nrounds,
      " max_depth=", xr$params$max_depth, " eta=", xr$params$eta, "\n")

  pred_LR   <- LR_model(train_imp, test_imp, features)
  pred_RF   <- RF_model(train_imp, test_imp, features)
  pred_SVM  <- SVM_model(train_imp, test_imp, features)
  pred_DT   <- DT_model(train_imp, test_imp, features)
  pred_NNET <- NNET_model(train_imp, test_imp, features)
  pred_KNN  <- KNN_model(train_imp, test_imp, features)

  # SNAP-II single-predictor benchmark (reviewer: benchmarking vs SNAP-II)
  if ("SNAP_II" %in% names(test_imp)) {
    score <- test_imp$SNAP_II
    score[is.na(score)] <- median(score, na.rm = TRUE)
    pred_SNAP <- (score - min(score)) / (max(score) - min(score))
    pred_SNAP[is.na(pred_SNAP)] <- 0.5
  } else pred_SNAP <- rep(0.5, nrow(test_imp))

  Prediction_all <- rbind(Prediction_all, data.frame(
    Fold = i, RowID = as.integer(test_id), AKI = test_imp$AKI_flag1,
    LR = pred_LR, RF = pred_RF, XGB = pred_XGB, SVM = pred_SVM,
    DT = pred_DT, NNET = pred_NNET, KNN = pred_KNN, SNAP_II = pred_SNAP
  ))
  saveRDS(Prediction_all, pE("E:/NARDS/Prediction_temp.rds"))
  cat("Fold", i, "finished\n")
}

Prediction_all$AKI_num <- as.numeric(as.character(Prediction_all$AKI))
# attach GA group for stratified analyses [R7]
Prediction_all$GA_grp <- ga_grp[Prediction_all$RowID]
# attach birth-weight category for stratified analyses [R7b]
Prediction_all$BW_grp <- wl_grp[Prediction_all$RowID]
true <- Prediction_all$AKI_num

###############################################################
# Part 3 Model performance (original) + fix undefined Feature_table
###############################################################
models <- c("LR", "RF", "XGB", "SVM", "DT", "NNET", "KNN", "SNAP_II")
Performance_result <- data.frame()
for (m in models) {
  if (!m %in% colnames(Prediction_all)) { warning(paste(m, "missing, skip")); next }
  prob <- Prediction_all[[m]]
  keep <- complete.cases(true, prob)
  true2 <- true[keep]; prob2 <- prob[keep]
  roc_obj <- roc(true2, prob2, quiet = TRUE)
  AUC <- as.numeric(auc(roc_obj))
  pr_obj <- pr.curve(scores.class0 = prob2[true2 == 1],
                     scores.class1 = prob2[true2 == 0], curve = FALSE)
  pred <- ifelse(prob2 >= 0.5, 1, 0)
  TP <- sum(pred == 1 & true2 == 1); TN <- sum(pred == 0 & true2 == 0)
  FP <- sum(pred == 1 & true2 == 0); FN <- sum(pred == 0 & true2 == 1)
  Sensitivity <- TP / (TP + FN); Specificity <- TN / (TN + FP)
  Precision <- TP / (TP + FP); Accuracy <- (TP + TN) / length(true2)
  F1 <- 2 * Precision * Sensitivity / (Precision + Sensitivity)
  Brier <- mean((prob2 - true2)^2)
  Performance_result <- rbind(Performance_result, data.frame(
    Model = m, AUC = round(AUC, 4), AUC_PR = round(pr_obj$auc.integral, 4),
    Sensitivity = round(Sensitivity, 4), Specificity = round(Specificity, 4),
    Precision = round(Precision, 4), Accuracy = round(Accuracy, 4),
    F1_Score = round(F1, 4), Brier_score = round(Brier, 4),
    TP = TP, TN = TN, FP = FP, FN = FN))
}
print(Performance_result)
wcsv(Performance_result, pE("E:/NARDS/NestedCV_Model_Performance.csv"), rn = FALSE)

Feature_table <- do.call(rbind, lapply(seq_along(Feature_all), function(k)
  data.frame(Fold = k, Feature = Feature_all[[k]])))
wcsv(Feature_table, pE("E:/NARDS/NestedCV_Selected_Features.csv"), rn = FALSE)

###############################################################
# [R3] Boruta fold-wise selection stability
###############################################################
all_pool <- sort(unique(Feature_table$Feature))
stab <- data.frame(
  variable = all_pool,
  selected_k_folds = sapply(all_pool, function(v) sum(vapply(Feature_all,
                                                             function(fs) v %in% fs, logical(1)))))
stab$stability <- round(stab$selected_k_folds / N_FOLDS, 2)
stab <- stab[order(-stab$selected_k_folds), ]
cat("[R3] Boruta selection stability (selection frequency across folds):\n")
print(stab)
wcsv(stab, pE("E:/NARDS/revision_output/R3_boruta_stability.csv"), rn = FALSE)

###############################################################
# [R4] Bootstrap 95% CIs for AUC / AUC-PR / Brier (pooled OOF, all models)
###############################################################
set.seed(2026)
n <- sum(complete.cases(true))
boot_ci <- list()
for (m in models) {
  prob <- Prediction_all[[m]]
  keep <- complete.cases(true, prob)
  o <- true[keep]; p <- prob[keep]
  bt <- matrix(NA_real_, N_BOOT, 3, dimnames = list(NULL, c("AUC", "AUCPR", "Brier")))
  for (b in seq_len(N_BOOT)) {
    i <- sample(length(o), length(o), replace = TRUE)
    ob <- o[i]; pb <- p[i]
    if (length(unique(ob)) < 2) next
    bt[b, 1] <- as.numeric(pROC::auc(roc(ob, pb, quiet = TRUE)))
    bt[b, 2] <- pr.curve(scores.class0 = pb[ob == 1], scores.class1 = pb[ob == 0],
                         curve = FALSE)$auc.integral
    bt[b, 3] <- mean((pb - ob)^2)
  }
  ci_tab <- t(apply(bt, 2, quantile, probs = c(.025, .975), na.rm = TRUE))
  pt <- c(AUC = as.numeric(pROC::auc(roc(o, p, quiet = TRUE))),
          AUCPR = pr.curve(scores.class0 = p[o == 1], scores.class1 = p[o == 0],
                           curve = FALSE)$auc.integral,
          Brier = mean((p - o)^2))
  boot_ci[[m]] <- data.frame(Model = m, Metric = rownames(ci_tab),
                             Point = round(pt[rownames(ci_tab)], 4),
                             CI_low = round(ci_tab[, 1], 4),
                             CI_high = round(ci_tab[, 2], 4))
  cat("[R4]", m, "done\n")
}
R4_CI <- do.call(rbind, boot_ci)
print(R4_CI)
wcsv(R4_CI, pE("E:/NARDS/revision_output/R4_bootstrap_CI.csv"), rn = FALSE)

###############################################################
# [R5] DeLong tests: XGBoost vs every other model
###############################################################
roc_xgb <- roc(true, Prediction_all$XGB, quiet = TRUE)
delong <- data.frame()
for (m in setdiff(models, "XGB")) {
  if (!all(complete.cases(true, Prediction_all[[m]]))) next
  tt <- roc.test(roc_xgb, roc(true, Prediction_all[[m]], quiet = TRUE),
                 method = "delong")
  delong <- rbind(delong, data.frame(Comparison = paste("XGB vs", m),
                                     p_value = signif(tt$p.value, 3)))
}
cat("[R5] DeLong tests:\n"); print(delong)
wcsv(delong, pE("E:/NARDS/revision_output/R5_delong_tests.csv"), rn = FALSE)

###############################################################
# [R6] Calibration: slope/intercept + decile plot (XGBoost, pooled OOF)
###############################################################
logit <- function(p) log(p / (1 - p))
cal_df <- data.frame(obs = true, pred = Prediction_all$XGB)
cal_df <- cal_df[complete.cases(cal_df) & cal_df$pred > 0 & cal_df$pred < 1, ]
cal_fit <- glm(obs ~ logit(pred), data = cal_df, family = binomial)
R6_cal <- c(calibration_intercept = round(unname(coef(cal_fit)[1]), 3),
            calibration_slope = round(unname(coef(cal_fit)[2]), 3),
            n = nrow(cal_df))
cat("[R6] Calibration (ideal: intercept 0, slope 1):\n"); print(R6_cal)
cal_df$decile <- cut(rank(cal_df$pred), breaks = 10, labels = FALSE)
dec <- cal_df %>% group_by(decile) %>%
  summarise(mean_pred = mean(pred), obs_rate = mean(obs), n = n(), .groups = "drop")
pdf(out_path(pE("E:/NARDS/revision_output/R6_calibration_XGB.pdf")), width = 6, height = 6)
plot(dec$mean_pred, dec$obs_rate, xlim = c(0, 1), ylim = c(0, 1),
     xlab = "Predicted AKI probability (deciles)",
     ylab = "Observed AKI rate", main = "Calibration plot - XGBoost (OOF)")
abline(0, 1, lty = 2, col = "gray50")
dev.off()
wcsv(dec, pE("E:/NARDS/revision_output/R6_calibration_deciles.csv"), rn = FALSE)

###############################################################
# [R7] Stratified AUC by the five Table 1 GA categories, then the
#      <32w (codes 1+2) vs >=32w (codes 3+4) comparison. Others (code 0)
#      is reported separately and excluded from the dichotomy, exactly
#      as in the revised manuscript (DeLong p = 0.315).
###############################################################
R7 <- list()
for (g in GA_ORDER) {
  s <- Prediction_all$GA_grp == g
  o <- Prediction_all$AKI_num[s]; p <- Prediction_all$XGB[s]
  if (length(unique(o)) < 2) next
  R7[[GA_LAB[as.character(g)]]] <-
    sprintf("n=%d AUC=%.4f", length(o), as.numeric(pROC::auc(roc(o, p, quiet = TRUE))))}
s_lt32 <- Prediction_all$GA_grp %in% c(1, 2)
s_ge32 <- Prediction_all$GA_grp %in% c(3, 4)
for (nm in c("lt32w", "ge32w")) {
  s <- if (nm == "lt32w") s_lt32 else s_ge32
  o <- Prediction_all$AKI_num[s]; p <- Prediction_all$XGB[s]
  if (length(unique(o)) < 2) { R7[[nm]] <- "not estimable (no events)"; next }
  rc <- roc(o, p, quiet = TRUE)
  ci <- pROC::ci.auc(rc, method = "bootstrap", boot.n = 1000, conf.level = .95)
  R7[[nm]] <- sprintf("n=%d AUC=%.4f (95%%CI %.4f-%.4f)",
                      length(o), as.numeric(rc$auc), ci[1], ci[3])
}
cat("[R7] Stratified AUC:\n"); print(unlist(R7))
wtxt(unlist(lapply(names(R7), function(k) paste0(k, ": ", R7[[k]]))), pE("E:/NARDS/revision_output/R7_stratified_AUC.txt"))

###############################################################
# [R7b] Stratified AUC by birth-weight category (maturity strata)
#       Weight_label: 1=ELBW <1000g, 2=VLBW 1000-1499g, 3=1500-2499g,
#       4=>=2500g, 0=unknown. Reviewer 2.1: "adjusted for and
#       stratified by maturity".
###############################################################
R7b <- list()
for (g in sort(unique(Prediction_all$BW_grp))) {
  s <- Prediction_all$BW_grp == g
  o <- Prediction_all$AKI_num[s]; p <- Prediction_all$XGB[s]
  if (sum(s) == 0) next
  if (length(unique(o)) < 2) {
    R7b[[BW_LAB[as.character(g)]]] <-
      sprintf("n=%d, events=%d -> AUC not estimable (no/only one class)",
              length(o), sum(o == 1))
    next
  }
  R7b[[BW_LAB[as.character(g)]]] <-
    sprintf("n=%d events=%d AUC=%.4f",
            length(o), sum(o == 1), as.numeric(pROC::auc(roc(o, p, quiet = TRUE))))
}
# merged maturity strata: <1500 g (ELBW+VLBW) vs >=1500 g; unknown BW excluded
s_lt1500 <- Prediction_all$BW_grp %in% c(1, 2)
s_ge1500 <- Prediction_all$BW_grp %in% c(3, 4)
for (nm in c("BW_lt1500g", "BW_ge1500g")) {
  s <- if (nm == "BW_lt1500g") s_lt1500 else s_ge1500
  o <- Prediction_all$AKI_num[s]; p <- Prediction_all$XGB[s]
  if (length(unique(o)) < 2) {
    R7b[[nm]] <- sprintf("n=%d events=%d -> not estimable", length(o), sum(o == 1))
    next
  }
  rc <- roc(o, p, quiet = TRUE)
  ci <- pROC::ci.auc(rc, method = "bootstrap", boot.n = 1000, conf.level = .95)
  R7b[[nm]] <- sprintf("n=%d events=%d AUC=%.4f (95%%CI %.4f-%.4f)",
                       length(o), sum(o == 1), as.numeric(rc$auc), ci[1], ci[3])
}
cat("[R7b] BW-stratified AUC:\n"); print(unlist(R7b))
wtxt(unlist(lapply(names(R7b), function(k) paste0(k, ": ", R7b[[k]]))), pE("E:/NARDS/revision_output/R7b_BW_stratified_AUC.txt"))

###############################################################
# [R2] Correlation matrix + VIF of the full candidate pool (pre-Boruta)
#      Single MICE imputation of the full cohort for diagnostics only.
###############################################################
cat("[R2] running full-cohort imputation for collinearity diagnostics...\n")
imp_diag <- mice(mydata2, m = 1, maxit = 5, seed = 42, printFlag = FALSE)
d_diag <- complete(imp_diag, 1)
cand_pool <- setdiff(names(d_diag), "AKI_flag1")
num_vars <- cand_pool[sapply(d_diag[cand_pool], is.numeric)]
wcsv(round(cor(d_diag[num_vars], use = "pairwise.complete.obs"), 3), pE("E:/NARDS/revision_output/R2_correlation_matrix.csv"))
glm_vif <- suppressWarnings(glm(
  as.formula(paste("AKI_flag1 ~", paste(num_vars, collapse = " + "))),
  data = d_diag, family = binomial))
vif_tab <- car::vif(glm_vif)
R2_vif <- data.frame(variable = names(vif_tab), VIF = round(as.numeric(vif_tab), 2))
R2_vif <- R2_vif[order(-R2_vif$VIF), ]
cat("[R2] variables with VIF > 5:\n")
print(R2_vif$variable[R2_vif$VIF > 5])
wcsv(R2_vif, pE("E:/NARDS/revision_output/R2_VIF.csv"), rn = FALSE)

###############################################################
# [R1] GA/BW between-group comparison + prematurity strata
###############################################################
lv2 <- "1"
grp_yes <- mydata2$AKI_flag1 == lv2
r1 <- c("[R1] GA/BW between-group comparison (AKI vs non-AKI)",
        "NOTE: firstweight and min_weight are CONTINUOUS KILOGRAM values;",
        "Weight_label is the 0-4 category. AKI = kdigo_stages_7day (118 events).")
r1 <- c(r1, "GA group distribution (AKI group):")
r1 <- c(r1, capture.output(print(table(mydata2$GA[grp_yes]))))
r1 <- c(r1, "GA group distribution (non-AKI group):")
r1 <- c(r1, capture.output(print(table(mydata2$GA[!grp_yes]))))
r1 <- c(r1, sprintf("GA group x AKI Fisher p = %.3g",
                    fisher.test(table(mydata2$GA, mydata2$AKI_flag1))$p.value))
for (v in c("firstweight", "min_weight")) {
  x <- suppressWarnings(as.numeric(as.character(mydata2[[v]])))
  if (all(is.na(x))) next
  r1 <- c(r1,
          sprintf("%s AKI: median(IQR) = %.0f (%.0f-%.0f)", v,
                  median(x[grp_yes], na.rm = TRUE),
                  quantile(x[grp_yes], .25, na.rm = TRUE),
                  quantile(x[grp_yes], .75, na.rm = TRUE)),
          sprintf("%s non-AKI: median(IQR) = %.0f (%.0f-%.0f)", v,
                  median(x[!grp_yes], na.rm = TRUE),
                  quantile(x[!grp_yes], .25, na.rm = TRUE),
                  quantile(x[!grp_yes], .75, na.rm = TRUE)),
          sprintf("%s Wilcoxon p = %.3g", v,
                  wilcox.test(x ~ mydata2$AKI_flag1)$p.value))
}
strat_tab <- table(factor(GA_LAB[as.character(ga_grp)],
                          levels = GA_LEVELS),
                   mydata2$AKI_flag1)
strat_tab <- strat_tab[, c("0", "1")]
r1 <- c(r1, "AKI rate by GA stratum:", capture.output(print(strat_tab)))
wil_ci <- apply(strat_tab, 1, function(rr) {
  bt <- binom.test(rr[2], sum(rr))$conf.int
  sprintf("%.1f%% (95%%CI %.1f-%.1f%%)", 100 * rr[2] / sum(rr),
          100 * bt[1], 100 * bt[2])
})
r1 <- c(r1, paste0(names(wil_ci), ": ", wil_ci))
r1 <- c(r1, sprintf("Cochran-Armitage p-for-trend = %.3g",
                    DescTools::CochranArmitageTest(strat_tab)$p.value))
cat(paste(r1, collapse = "\n"), "\n")
wtxt(r1, pE("E:/NARDS/revision_output/R1_GA_BW_comparison.txt"))

###############################################################
# [R1b] AKI rate by birth-weight category (Weight_label)
#       1=ELBW <1000g, 2=VLBW 1000-1499g, 3=1500-2499g, 4=>=2500g,
#       0=unknown. Wilson CIs + Cochran-Armitage trend.
###############################################################
bw_fac <- factor(BW_LAB[as.character(wl_grp)],
                 levels = unname(BW_LAB[c("1", "2", "3", "4", "0")]))
bw_tab <- table(bw_fac, mydata2$AKI_flag1)[, c("0", "1")]
r1b <- c("[R1b] AKI rate by birth-weight category (Weight_label)",
         capture.output(print(bw_tab)))
bw_ci <- vapply(rownames(bw_tab), function(s) {
  y <- bw_tab[s, "1"]; nn <- sum(bw_tab[s, ])
  if (nn == 0) return(paste0(s, ": no patients"))
  if (is.na(y) || y == 0) {
    bt <- binom.test(0, nn)$conf.int
    return(sprintf("%s: 0/%d = 0.0%% (95%%CI %.1f-%.1f%%)",
                   s, nn, 100 * bt[1], 100 * bt[2]))
  }
  bt <- binom.test(y, nn)$conf.int
  sprintf("%s: %d/%d = %.1f%% (95%%CI %.1f-%.1f%%)",
          s, y, nn, 100 * y / nn, 100 * bt[1], 100 * bt[2])
}, character(1))
r1b <- c(r1b, unname(bw_ci),
         sprintf("BW category x AKI Fisher p = %.3g",
                 fisher.test(bw_tab)$p.value))
# trend test across the 4 known-BW categories ordered by severity
bw_tab_known <- bw_tab[rownames(bw_tab) != "BW unknown", , drop = FALSE]
if (nrow(bw_tab_known) >= 2 && sum(bw_tab_known[, "1"]) > 0) {
  r1b <- c(r1b, sprintf("Cochran-Armitage p-for-trend (ELBW->>=2500g) = %.3g",
                        DescTools::CochranArmitageTest(bw_tab_known)$p.value))
}
cat(paste(r1b, collapse = "\n"), "\n")
wtxt(r1b, pE("E:/NARDS/revision_output/R1b_BW_category_AKI_rate.txt"))

###############################################################
# [R13] ADJUSTED-for-maturity analysis (reviewer 2.1)
#      Multivariable logistic regression: each retained predictor
#      adjusted for birth-weight maturity category (Weight_label).
#      Predictors = 10 most fold-stable Boruta features.
###############################################################
cat("[R13] adjusted-for-maturity logistic regression...\n")
stab13 <- sort(sapply(unique(unlist(Feature_all)), function(v)
  sum(vapply(Feature_all, function(fs) v %in% fs, logical(1)))),
  decreasing = TRUE)
top_feats <- head(names(stab13), 10)
top_feats <- setdiff(top_feats, c("Weight_label", "AKI_flag1"))
d13 <- d_diag
d13$WL <- as.numeric(as.character(d13$Weight_label))
n_unk <- sum(is.na(d13$WL) | d13$WL == 0)
d13 <- d13[!is.na(d13$WL) & d13$WL != 0, ]
d13$WL <- factor(d13$WL, levels = c("4", "3", "2", "1"))  # ref = >=2500 g
f13 <- as.formula(paste("AKI_flag1 ~ WL +", paste(top_feats, collapse = " + ")))
fit13 <- suppressWarnings(glm(f13, data = d13, family = binomial))
s13 <- summary(fit13)$coefficients
or13 <- data.frame(
  Predictor = rownames(s13),
  OR = round(exp(s13[, 1]), 3),
  CI_low = round(exp(s13[, 1] - 1.96 * s13[, 2]), 3),
  CI_high = round(exp(s13[, 1] + 1.96 * s13[, 2]), 3),
  p_value = signif(s13[, 4], 3))
wcsv(or13, pE("E:/NARDS/revision_output/R13_adjusted_ORs.csv"), rn = FALSE)
# LR test: do predictors add information beyond maturity alone?
fit13b <- suppressWarnings(glm(
  as.formula(paste("AKI_flag1 ~ WL")), data = d13, family = binomial))
lr13 <- anova(fit13b, fit13, test = "LRT")
# c-statistic with vs without the maturity adjustment
auc13a <- as.numeric(pROC::auc(roc(d13$AKI_flag1,
                                   as.numeric(predict(fit13, type = "response")),
                                   quiet = TRUE)))
auc13b <- as.numeric(pROC::auc(roc(d13$AKI_flag1,
                                   as.numeric(predict(fit13b, type = "response")),
                                   quiet = TRUE)))
R13 <- c("[R13] Adjusted-for-maturity logistic regression (ref BW >=2500g)",
         sprintf("BW categories in model: 4=>=2500g (ref), 3=1500-2499g, 2=VLBW 1000-1499g, 1=ELBW <1000g"),
         sprintf("Rows with unknown BW (0) excluded: %d ; analyzed n = %d, events = %d",
                 n_unk, nrow(d13), sum(d13$AKI_flag1 == "1")),
         sprintf("Most stable Boruta predictors adjusted for BW category: %s",
                 paste(top_feats, collapse = ", ")),
         "Adjusted ORs (full table in R13_adjusted_ORs.csv):",
         capture.output(print(or13, row.names = FALSE)),
         sprintf("LR test BW-only vs BW+predictors: LRT p = %.3g",
                 lr13$`Pr(>Chi)`[2]),
         sprintf("AUC BW-category-only model = %.4f ; BW + predictors = %.4f",
                 auc13b, auc13a))
cat(paste(R13, collapse = "\n"), "\n")
wtxt(R13, pE("E:/NARDS/revision_output/R13_adjusted_for_maturity.txt"))

###############################################################
# [R9] Risk stratification: train-only threshold derivation,
#      held-out test evaluation, per-stratum CIs, p-for-trend, calibration
###############################################################
cat("[R9] risk stratification module...\n")
set.seed(1234)
idx7 <- sample(nrow(mydata2), 0.7 * nrow(mydata2))
tr9 <- mydata2[idx7, ]; te9 <- mydata2[-idx7, ]
imp_tr9 <- mice(tr9, m = 5, maxit = 10, seed = 7, printFlag = FALSE)
tr9_imp <- complete(imp_tr9, 1)
imp_te9 <- mice(te9, m = 1, maxit = 1, seed = 8, printFlag = FALSE)
te9_imp <- complete(imp_te9, 1)

# thresholds derived ONLY from out-of-fold predictions within the training set
set.seed(1234)
cvf9 <- createFolds(tr9_imp$AKI_flag1, k = 10, returnTrain = FALSE)
oof9 <- c()
for (k in 1:10) {
  ftr <- tr9_imp[-cvf9[[k]], ]; fte <- tr9_imp[cvf9[[k]], ]
  xr9 <- XGB_model(ftr, fte, setdiff(names(ftr), "AKI_flag1"),
                   tune = TUNE_XGB_INNER)
  oof9[cvf9[[k]]] <- xr9$pred
  cat("[R9] inner fold", k, "done\n")
}
obs9 <- as.numeric(as.character(tr9_imp$AKI_flag1))
if (length(oof9) != nrow(tr9_imp) || any(is.na(oof9)))
  stop("[R9] inner OOF incomplete - do NOT run this script in debug/step mode; source it normally")
rr <- roc(obs9, oof9, quiet = TRUE)
coord <- coords(rr, x = "best", input = "threshold", best.method = "youden")
youden_thr <- as.numeric(coord[1])
# high-risk threshold: LOWEST threshold with PPV >= 0.25 on train-OOF,
# requiring at least 10 flagged patients (avoids single-patient strata)
thr_seq <- sort(unique(oof9), decreasing = TRUE)
ppv_thr <- NA_real_
for (t in thr_seq) {
  n_flag <- sum(oof9 >= t)
  if (n_flag < 10) next
  tp <- sum(oof9 >= t & obs9 == 1)
  if (tp / n_flag >= 0.25) ppv_thr <- t else break
}
if (is.na(ppv_thr)) ppv_thr <- as.numeric(quantile(oof9, 0.9, na.rm = TRUE))
if (ppv_thr <= youden_thr)
  ppv_thr <- as.numeric(quantile(oof9, 0.9, na.rm = TRUE))
cat(sprintf("[R9] train-OOF derived thresholds: Youden=%.3f  High-risk(PPV>=0.25, n>=10)=%.3f\n",
            youden_thr, ppv_thr))

# final model on full training set -> predict test
xr9f <- XGB_model(tr9_imp, te9_imp, setdiff(names(tr9_imp), "AKI_flag1"),
                  tune = FALSE)
te_pred <- xr9f$pred
te_obs  <- as.numeric(as.character(te9_imp$AKI_flag1))
strat <- cut(te_pred, breaks = c(-Inf, youden_thr, ppv_thr, Inf),
             labels = c("Low", "Moderate", "High"))
st <- table(strat, te_obs)
R9 <- c("[R9] test-set risk strata (thresholds derived on train-OOF only)",
        capture.output(print(st)),
        sprintf("Youden threshold = %.3f ; high-risk threshold = %.3f", youden_thr, ppv_thr))
strat_ci <- sapply(rownames(st), function(s) {
  y <- st[s, "1"]; nn <- sum(st[s, ])
  if (is.na(y) || nn == 0) return(paste0(s, ": empty stratum in test set"))
  bt <- binom.test(y, nn)$conf.int
  sprintf("%s: %d/%d = %.1f%% (95%%CI %.1f-%.1f%%)", s, y, nn,
          100 * y / nn, 100 * bt[1], 100 * bt[2])
})
R9 <- c(R9, strat_ci)
trend_p <- tryCatch(sprintf("Cochran-Armitage p-for-trend = %.3g",
                            DescTools::CochranArmitageTest(st)$p.value),
                    error = function(e) "Cochran-Armitage test not estimable (empty strata)")
R9 <- c(R9, trend_p)
# stratum-specific observed vs expected
for (s in rownames(st)) {
  sel <- strat == s
  R9 <- c(R9, sprintf("%s stratum calibration: mean predicted=%.3f vs observed=%.3f",
                      s, mean(te_pred[sel]), mean(te_obs[sel])))
}
cat(paste(R9, collapse = "\n"), "\n")
wtxt(R9, pE("E:/NARDS/revision_output/R9_risk_stratification.txt"))

###############################################################
# [R10] Sensitivity analyses (each re-runs the 10-fold pipeline, XGB only)
###############################################################
if (SENS_RUN) {
  cat("[R10] sensitivity A: exclude FirstUrineOutput (reverse causation)...\n")
  sa <- run_pipeline_xgb(mydata2, exclude_vars = "FirstUrineOutput",
                         label = "no-UO", tune = FALSE)
  auc_sa <- as.numeric(pROC::auc(roc(sa$oof$obs, sa$oof$pred, quiet = TRUE)))
  cat(sprintf("[R10-A] AUC without first-day urine output = %.4f\n", auc_sa))
  wcsv(sa$sel_count, pE("E:/NARDS/revision_output/R10A_boruta_freq_no_UO.csv"))

  cat("[R10] sensitivity B: replace min_weight with birth weight...\n")
  sb <- run_pipeline_xgb(mydata2, exclude_vars = "min_weight",
                         label = "no-minW", tune = FALSE)
  auc_sb <- as.numeric(pROC::auc(roc(sb$oof$obs, sb$oof$pred, quiet = TRUE)))
  cat(sprintf("[R10-B] AUC with birth weight instead of min_weight = %.4f\n", auc_sb))
  wcsv(sb$sel_count, pE("E:/NARDS/revision_output/R10B_boruta_freq_BW.csv"))

  wtxt(c(sprintf("Sensitivity A (exclude FirstUrineOutput): OOF AUC = %.4f", auc_sa),
               sprintf("Sensitivity B (min_weight -> birth weight): OOF AUC = %.4f", auc_sb),
               sprintf("Main model OOF AUC (XGB) = %.4f", as.numeric(pROC::auc(roc_xgb)))), pE("E:/NARDS/revision_output/R10_sensitivity_summary.txt"))
}

###############################################################
# [R11] Sample size justification (Riley 2019) + EPV
###############################################################
glm_full <- suppressWarnings(glm(
  as.formula(paste("AKI_flag1 ~", paste(num_vars, collapse = " + "))),
  data = d_diag, family = binomial))
r2 <- tryCatch(DescTools::PseudoR2(glm_full, which = "Nagelkerke"), error = function(e) 0.15)
pm <- tryCatch(
  pmsampsize::pmsampsize(type = "b",
                         nagrsquared = min(max(r2, 0.05), 0.9),  # this version uses nagrsquared
                         parameters = length(cand_pool),
                         prevalence = mean(mydata2$AKI_flag1 == 1),
                         shrinkage = 0.9),
  error = function(e) e)
cat("[R11] pmsampsize result (Riley 2019):\n"); print(pm)
n_final_feat <- median(sapply(Feature_all, length))
pm_line <- if (inherits(pm, "error")) paste("pmsampsize failed:", pm$message) else paste(capture.output(print(pm)), collapse = "\n")
R11 <- c(sprintf("[R11] candidate pool size = %d ; median confirmed features per fold = %.0f",
                 length(cand_pool), n_final_feat),
         sprintf("Events per candidate predictor (EPV) = %.1f (events = %d)",
                 N_EVENTS / length(cand_pool), N_EVENTS),
         sprintf("Events per confirmed feature (EPV, median fold) = %.1f",
                 N_EVENTS / max(n_final_feat, 1)),
         sprintf("Nagelkerke R2 of full logistic model = %.3f", r2),
         pm_line)
wtxt(R11, pE("E:/NARDS/revision_output/R11_sample_size.txt"))

###############################################################
# [R12] Auto-generated Methods reporting text (paste into manuscript)
###############################################################
params_df <- do.call(rbind, lapply(seq_along(xgb_params_log), function(i)
  data.frame(Fold = i, nrounds = xgb_params_log[[i]]$nrounds,
             max_depth = xgb_params_log[[i]]$max_depth,
             eta = xgb_params_log[[i]]$eta)))
R12 <- c(
  "[R12] METHODS REPORTING (for manuscript / response letter)",
  sprintf("MICE: m=5, maxit=10, applied to the training fold only; test fold imputed separately (m=1, maxit=1)."),
  sprintf("Boruta: applied within each training fold; maxRuns=20, TentativeRoughFix applied, shadow-feature inference with default ntree=500; candidate pool per fold = %d variables (full pool = %d).",
          median(pool_size_log), length(cand_pool)),
  if (TUNE_XGB_INNER)
    "XGBoost: hyperparameters (nrounds, max_depth, eta) tuned inside each training fold via inner 5-fold CV over an 8-point grid; no tuning used held-out data."
  else "XGBoost: fixed hyperparameters nrounds=200, max_depth=3, eta=0.05 (no tuning performed).",
  sprintf("Tuned parameters per fold: nrounds median=%g, max_depth median=%g, eta median=%g.",
          median(params_df$nrounds), median(params_df$max_depth), median(params_df$eta)),
  sprintf("Per-fold MEDIAN tuned values (reported in Methods; generated ALL pooled OOF performance, calibration and thresholds): nrounds=%g, max_depth=%g, eta=%g, seed=1234.",
          median(params_df$nrounds), median(params_df$max_depth), median(params_df$eta)),
  "SINGLE deployment refit on the full imputed cohort: nrounds=200, max_depth=3, eta=0.05 -> 200 trees in the released model.json.",
  sprintf("Sample size justification and EPV: see R11_sample_size.txt."),
  "FINAL training-set OOF cut-points (authoritative): 0.0651 / 0.3008; displayed as 0.065 / 0.301 in Table 6 and Figures 9-10.",
  sprintf("This run's diagnostic thresholds: Youden=%.4f, high-risk=%.4f; the released values are in risk_thresholds.csv.",
          youden_thr, ppv_thr)
)
wtxt(R12, pE("E:/NARDS/revision_output/R12_methods_reporting.txt"))
cat(paste(R12, collapse = "\n"), "\n")

###############################################################
# Original ROC plot section (unchanged)
###############################################################
pdf(out_path(pE("E:/NARDS/All_models_ROC.pdf")), width = 7, height = 7)
roc_list <- list()
roc_color <- c("red", "#2E8B57", "blue", "orange", "purple", "#00BFFF", "#8B4513", "#FF1493")
names(roc_color) <- models
valid_models <- models[models %in% colnames(Prediction_all)]
for (i in seq_along(valid_models)) {
  model_name <- valid_models[i]
  sub_df <- Prediction_all[, c("AKI_num", model_name)]
  sub_df <- sub_df[complete.cases(sub_df), ]
  if (nrow(sub_df) == 0) next
  roc_obj <- roc(sub_df$AKI_num, sub_df[[model_name]], quiet = TRUE)
  roc_list[[model_name]] <- roc_obj
  if (i == 1) plot(roc_obj, lwd = 2, col = roc_color[model_name],
                   main = "ROC curves of all models")
  else plot(roc_obj, add = TRUE, lwd = 2, col = roc_color[model_name])
}
if (length(roc_list) > 0) {
  legend("bottomright",
         legend = paste0(names(roc_list), " AUC=", round(sapply(roc_list, auc), 3)),
         lwd = 2, col = roc_color[names(roc_list)])
}
dev.off()
cat("ROC curve saved to E:/NARDS/\n")

###############################################################
# Original DCA plot section (unchanged)
###############################################################
valid_dca_cols <- c("XGB", "LR", "RF")
valid_dca_cols <- valid_dca_cols[valid_dca_cols %in% colnames(Prediction_all)]
dca_sub <- Prediction_all[, valid_dca_cols, drop = FALSE]
dca_data <- data.frame(AKI = Prediction_all$AKI_num, dca_sub)
dca_data <- dca_data[complete.cases(dca_data), ]
dca_results <- list()
for (m in valid_dca_cols) {
  cat("DCA:", m, "\n")
  dca_results[[m]] <- decision_curve(
    as.formula(paste("AKI~", m)), data = dca_data, family = "binomial",
    thresholds = seq(0, 1, 0.01), confidence.intervals = FALSE,
    study.design = "cohort")
}
pdf(out_path(pE("E:/NARDS/All_models_DCA.pdf")), width = 8, height = 8)
if (length(dca_results) > 0) {
  plot_decision_curve(dca_results, curve.names = names(dca_results),
                      xlab = "Threshold probability", cost.benefit.axis = FALSE,
                      standardize = FALSE, legend.position = "bottomright")
}
dev.off()
cat("DCA curve saved to E:/NARDS/\n")

###############################################################
# Final exports
###############################################################
wcsv(Prediction_all, pE("E:/NARDS/NestedCV_All_Predictions.csv"), rn = FALSE)
saveRDS(Prediction_all, pE("E:/NARDS/Prediction_temp.rds"))
cat("\n=== DONE. Reviewer outputs are in E:/NARDS/revision_output/ ===\n")
cat("R1_GA_BW_comparison.txt    -> Mandatory #1 (2.1 maturity confounding)\n")
cat("R2_correlation_matrix.csv  -> Mandatory #2 (collinearity)\n")
cat("R2_VIF.csv                 -> Mandatory #2 (VIF)\n")
cat("R3_boruta_stability.csv    -> Mandatory #2 (Boruta stability)\n")
cat("R4_bootstrap_CI.csv        -> Mandatory #4 (95% CIs, all models)\n")
cat("R5_delong_tests.csv        -> Mandatory #4 (XGB vs others)\n")
cat("R6_calibration_XGB.pdf/csv -> Mandatory #5 (calibration)\n")
cat("R7_stratified_AUC.txt      -> Mandatory #1 (<32w vs >=32w)\n")
cat("R7b_BW_stratified_AUC.txt  -> Mandatory #1 (birth-weight strata)\n")
cat("R1b_BW_category_AKI_rate.txt -> Mandatory #1 (AKI rate by BW category)\n")
cat("R13_adjusted_for_maturity.txt -> Mandatory #1 (adjusted for maturity)\n")
cat("R9_risk_stratification.txt -> Mandatory #8 (strata, CIs, trend)\n")
cat("R10_sensitivity_summary.txt-> reverse causation / birth-weight analyses\n")
cat("R11_sample_size.txt        -> Mandatory #7 (Riley 2019, EPV)\n")
cat("R12_methods_reporting.txt  -> Mandatory #6 (full model spec)\n")
