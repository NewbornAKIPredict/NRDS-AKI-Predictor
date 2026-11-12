###############################################################
# revision_legacy_bridge.R
# Shared compatibility layer for the SIX legacy scripts.
#
# The legacy scripts used hard-coded thresholds, a stacked 10-fold training
# set, fixed XGBoost parameters and an undefined `folds` object. They were
# NOT reproducible and produced numbers inconsistent with the revised
# manuscript. They now all read the outputs of the revision-consistent
# pipeline (revision_tables_figures_v1.R) through this bridge.
#
# Run order: (1) revision_main_v1.R  (2) revision_tables_figures_v1.R
#            (3) any legacy script below (optional, re-exports old filenames)
###############################################################

BRIDGE_OUT <- "E:/NARDS/revision_output"
BRIDGE_ROOT <- "E:/NARDS"

# Return the newest matching result file. Excel/WPS may lock the canonical
# CSV; the analysis script then writes *_FINAL.csv or a timestamped copy.
bridge_latest <- function(stem, ext = "csv") {
  fs <- list.files(BRIDGE_OUT, pattern = paste0("^", stem, ".*\\.", ext, "$"),
                   full.names = TRUE)
  if (length(fs) == 0) return(file.path(BRIDGE_OUT, paste0(stem, ".", ext)))
  fs[which.max(file.mtime(fs))]
}

bridge_require <- function(...) {
  fs <- file.path(BRIDGE_OUT, c(...))
  miss <- fs[!file.exists(fs)]
  if (length(miss) > 0) {
    stop("Missing revision outputs:\n  ", paste(miss, collapse = "\n  "),
         "\nRun E:/NARDS/revision_tables_figures_v1.R first.", call. = FALSE)
  }
  invisible(fs)
}

bridge_copy <- function(src, dst) {
  ok <- tryCatch(file.copy(src, dst, overwrite = TRUE), error = function(e) FALSE)
  if (!isTRUE(ok)) {
    alt <- sub("(\\.[A-Za-z]+)$", paste0("_", format(Sys.time(), "%H%M%S"), "\\1"), dst)
    cat("WARNING:", dst, "locked -> writing", alt, "\n")
    ok <- file.copy(src, alt, overwrite = TRUE)
    if (!isTRUE(ok)) warning("Could not write ", dst)
  } else cat("OK:", dst, "\n")
  invisible(ok)
}

# EXACT training-set OOF thresholds (4 d.p.), as reported in Methods, the
# Table 6 footnote and Reply 12. The Table 6 / Figure 9 / Figure 10 labels
# 0.065 / 0.301 are ROUNDED FOR DISPLAY ONLY and must never be used as
# cut-points. The Shiny calculator reads these exact values.
bridge_exact_thresholds <- function() {
  v <- c(youden = 0.0651, high = 0.3008)
  fn <- file.path(BRIDGE_OUT, "T6_footnote.txt")
  if (file.exists(fn)) {
    ln <- grep("Youden threshold", readLines(fn, warn = FALSE), value = TRUE)
    if (length(ln) >= 1) {
      num <- as.numeric(unlist(regmatches(ln[1],
        gregexpr("[0-9]+\\.[0-9]+", ln[1]))))
      if (length(num) >= 2 && all(is.finite(num[1:2])))
        v <- c(youden = num[1], high = num[2])
    }
  }
  if (!is.finite(v[["youden"]]) || !is.finite(v[["high"]]) ||
      v[["youden"]] <= 0 || v[["high"]] >= 1 || v[["youden"]] >= v[["high"]])
    stop("Could not resolve revision-consistent exact thresholds.")
  v
}

# Build the two artefacts the Shiny calculator needs, from the SAME final
# model and thresholds used for the revised Tables 2-6.
bridge_build_app_artifacts <- function() {
  bundle <- file.path(BRIDGE_OUT, "model_transparency/NARDS_AKI_trained_model.rda")
  t6f <- bridge_latest("T6_risk_stratification_decision")
  if (!file.exists(bundle) || !file.exists(t6f))
    stop("Run revision_tables_figures_v1.R first (model bundle / T6 missing).")
  cat("Using T6 file:", t6f, "\n")
  load(bundle)  # final_xgb, final_features, med, GA_LAB, d_full

  # training design matrix: keep its exact column names so the app aligns
  X_ref <- model.matrix(~ . - 1, d_full[, final_features, drop = FALSE])
  X_template <- colnames(X_ref)
  feature_info <- lapply(final_features, function(v) {
    z <- d_full[[v]]
    if (is.factor(z)) {
      list(Feature = v, Type = "factor", Levels = levels(z), Default = levels(z)[1])
    } else {
      dv <- suppressWarnings(as.numeric(as.character(z)))
      list(Feature = v, Type = "numeric", Levels = NULL,
           Default = if (all(is.na(dv))) 0 else round(median(dv, na.rm = TRUE), 2))
    }
  })
  model_xgboost <- final_xgb
  selected_feat <- final_features
  save(model_xgboost, selected_feat, X_template, feature_info, med,
       file = file.path(BRIDGE_ROOT, "xgboost_model.rda"))

  th <- bridge_exact_thresholds()
  youden <- th[["youden"]]; high <- th[["high"]]
  write.csv(data.frame(
      youden_threshold = youden,
      high_risk_threshold = high,
      youden_display = round(youden, 3),
      high_risk_display = round(high, 3),
      derivation = "training-set out-of-fold predictions only; applied unchanged to the held-out test set",
      source = "revision_tables_figures_v1.R (T6_footnote.txt / tables_figures_log.txt)"),
    file.path(BRIDGE_ROOT, "risk_thresholds.csv"), row.names = FALSE)
  cat("App artefacts: xgboost_model.rda (", length(selected_feat), "features, ",
      length(X_template), "design columns) + risk_thresholds.csv (Youden=",
      youden, ", high=", high, "; displayed as ", round(youden, 3), "/",
      round(high, 3), ")\n", sep = "")
  invisible(list(youden = youden, high = high, features = selected_feat))
}

# Per-patient decision table from pooled 10-fold OOF predictions (1115 rows),
# using the revision-consistent T6 thresholds.
bridge_patient_decisions <- function() {
  t6f <- bridge_latest("T6_risk_stratification_decision")
  if (!file.exists(t6f)) stop("Run revision_tables_figures_v1.R first (T6 missing).")
  pf <- file.path(BRIDGE_ROOT, "NestedCV_All_Predictions.csv")
  if (!file.exists(pf)) stop("Run revision_main_v1.R first (OOF predictions missing).")
  p <- read.csv(pf, stringsAsFactors = FALSE)
  t6 <- read.csv(t6f, stringsAsFactors = FALSE)
  th <- bridge_exact_thresholds()
  y_thr <- th[["youden"]]; h_thr <- th[["high"]]
  pr <- p$XGB
  lev <- cut(pr, breaks = c(-Inf, y_thr, h_thr, Inf),
             labels = c("Low Risk", "Moderate Risk", "High Risk"), right = FALSE)
  out <- data.frame(
    Patient_ID = p$RowID,
    Predicted_AKI_Risk = round(pr, 4),
    True_AKI_Label = p$AKI_num,
    Risk_Level = as.character(lev),
    Clinical_Recommendation = as.character(t6$Clinical_Intervention[match(as.character(lev), t6$Risk_Level)]),
    Data_Source = "pooled 10-fold out-of-fold prediction (revision pipeline)")
  write.csv(out, file.path(BRIDGE_ROOT, "XGB_All_Patient_Risk_Decision.csv"),
            row.names = FALSE)
  cat("OK: XGB_All_Patient_Risk_Decision.csv (", nrow(out), " patients)\n", sep = "")
  print(table(out$Risk_Level, useNA = "ifany"))
  invisible(out)
}
