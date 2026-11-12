###############################################################################
# predict_new_patient.R - reproduce ONE prediction from the released model
# TP-2026-0897-CL (Translational Pediatrics, major revision)
# Transparency bundle FINAL v4, 2026-11-12
#
# WHY THIS SCRIPT DOES NOT REQUIRE xgboost
#   The published calculator (and this bundle) ships a version-portable JSON
#   booster, model.json. This script walks its 200 trees in pure R using the
#   SAME scorer as the deployed Shiny app. Only base R + jsonlite are needed,
#   so a reviewer can reproduce a probability on any machine without compiling
#   xgboost. Verified against the original xgb.Booster: max |difference| =
#   1.45e-07 (float32 accumulation only).
#
# USAGE
#   install.packages("jsonlite")           # first time only
#   Rscript predict_new_patient.R
#   Edit the PATIENT list below to try your own values.
#
# FILES READ (all in this directory)
#   model.json           200-tree portable booster (no patient data)
#   model_meta.rds       29 design columns, 22 predictors, medians, tuning values
#   risk_thresholds.csv  EXACT cut-points 0.0651 / 0.3008
#
# OPTIONAL CROSS-CHECK
#   If xgboost 1.7.7.1 is installed, xgboost_model.rda is loaded too and the
#   native prediction is compared with the pure-R one. Newer xgboost releases
#   cannot read that legacy binary booster; the check is skipped, not fatal.
#
# RESEARCH USE ONLY. Development-stage model, internal validation only, NO
# external validation. Not for diagnosis, triage or treatment decisions.
# See MODEL_CARD.md section 2.
###############################################################################

if (!requireNamespace("jsonlite", quietly = TRUE))
  stop("Please run install.packages('jsonlite') once (it ships with shiny).")

here <- function(name) {
  # Works with Rscript (--file=), source() (ofile) and an interactive console.
  fa <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
  script_dir <- if (length(fa) && !is.na(fa) && nzchar(fa))
    dirname(normalizePath(fa, mustWork = FALSE)) else NA_character_
  of <- tryCatch(normalizePath(sys.frame(1)$ofile, mustWork = FALSE),
                 error = function(e) NA_character_)
  d <- unique(c(Sys.getenv("NARDS_MODEL_DIR", unset = ""), getwd(),
                script_dir, if (!is.na(of)) dirname(of) else NA_character_))
  d <- d[!is.na(d) & nzchar(d)]
  for (x in d) {
    p <- file.path(x, name)
    if (file.exists(p)) return(p)
  }
  stop("Required file '", name, "' not found. Put model.json, model_meta.rds ",
       "and risk_thresholds.csv next to this script, or set NARDS_MODEL_DIR.")
}

# ---------------------------------------------------------------------------
# 1. Load the portable booster and build the pure-R tree walker
# ---------------------------------------------------------------------------
B <- jsonlite::fromJSON(
  paste(readLines(here("model.json"), warn = FALSE), collapse = "\n"),
  simplifyVector = FALSE)
L <- B$learner
raw <- L$gradient_booster$model$trees
if (length(raw) < 1L) stop("model.json contains no trees.")

as_int <- function(z) as.integer(unlist(z, use.names = FALSE))
as_num <- function(z) as.numeric(unlist(z, use.names = FALSE))
TREES <- lapply(raw, function(t) list(
  left  = as_int(t$left_children),
  right = as_int(t$right_children),
  idx   = as_int(t$split_indices) + 1L,
  cond  = as_num(t$split_conditions),
  defL  = as_int(t$default_left) == 1L))
NTREES <- length(TREES)

base_score <- suppressWarnings(as.numeric(L$learner_model_param$base_score))
if (!is.finite(base_score) || base_score <= 0 || base_score >= 1) base_score <- 0.5
BASE_MARGIN <- log(base_score / (1 - base_score))

score_booster <- function(x) {
  s <- BASE_MARGIN
  for (i in seq_len(NTREES)) {
    t <- TREES[[i]]; node <- 1L
    while (isTRUE(t$left[node] >= 0L)) {
      v <- x[t$idx[node]]
      go_left <- if (is.na(v)) t$defL[node] else (v < t$cond[node])
      node <- (if (isTRUE(go_left)) t$left[node] else t$right[node]) + 1L
    }
    s <- s + t$cond[node]
  }
  1 / (1 + exp(-s))
}

# ---------------------------------------------------------------------------
# 2. Load the model dictionary and the exact thresholds
# ---------------------------------------------------------------------------
md <- readRDS(here("model_meta.rds"))
X_template    <- as.character(md$X_template)
selected_feat <- as.character(md$selected_feat)
feature_info  <- md$feature_info
med           <- md$med
stopifnot(length(X_template) == 29L, length(selected_feat) == 22L,
          length(feature_info) == 22L,
          identical(selected_feat,
                    vapply(feature_info, function(z) z$Feature, character(1))))

thr <- read.csv(here("risk_thresholds.csv"), stringsAsFactors = FALSE,
                check.names = FALSE)
youden <- suppressWarnings(as.numeric(thr$youden_threshold[1]))
high   <- suppressWarnings(as.numeric(thr$high_risk_threshold[1]))
disp_y <- if ("youden_display" %in% names(thr))
  suppressWarnings(as.numeric(thr$youden_display[1])) else round(youden, 3)
disp_h <- if ("high_risk_display" %in% names(thr))
  suppressWarnings(as.numeric(thr$high_risk_display[1])) else round(high, 3)
stopifnot(is.finite(youden), is.finite(high),
          abs(youden - 0.0651) < 1e-6, abs(high - 0.3008) < 1e-6)

# ---------------------------------------------------------------------------
# 3. EDIT HERE: a single patient, in the exact units of the analytic extract
#    Birth and minimum weights are KILOGRAMS (medians 1.505 / 1.380 kg).
#    GA and Weight_label are 0-4 study codes (see MODEL_CARD.md section 6).
#    Any field left NULL uses the training-fold median stored in feature_info.
# ---------------------------------------------------------------------------
PATIENT <- list(
  SNAP_II          = NULL,     # example overrides: 3 (default), 30 (moderate)
  FirstUrineOutput = NULL,     # first-day urine output, mL
  firstweight      = NULL,     # kg; e.g. 0.900
  min_weight       = NULL,     # kg; e.g. 0.850
  GA               = NULL,     # 0=<28w 1=29-32w 2=33-34w 3=35-36w 4=Others
  Weight_label     = NULL      # 0=unknown 1=ELBW 2=VLBW 3=1500-2499g 4=>=2500g
)

build_design <- function(overrides = list()) {
  vals <- lapply(feature_info, function(f) {
    v <- if (f$Feature %in% names(overrides)) overrides[[f$Feature]] else NULL
    if (is.null(v) || length(v) == 0L || is.na(v)) v <- f$Default
    if (identical(f$Type, "factor"))
      return(factor(as.character(v), levels = f$Levels))
    suppressWarnings(as.numeric(v))
  })
  df <- as.data.frame(stats::setNames(
    vals, vapply(feature_info, function(z) z$Feature, character(1))),
    check.names = FALSE)
  X <- stats::model.matrix(~ . - 1, df)
  Xa <- matrix(0, nrow = 1, ncol = length(X_template),
               dimnames = list(NULL, X_template))
  cn <- intersect(colnames(X), X_template)
  Xa[, cn] <- X[, cn, drop = FALSE]
  if (length(cn) != length(X_template))
    stop("Design-matrix alignment failed: matched ", length(cn), " of ",
         length(X_template), " columns.")
  list(X = Xa, df = df)
}

d <- build_design(PATIENT)
prob <- score_booster(as.numeric(d$X[1, ]))
stratum <- if (prob >= high) "High" else if (prob >= youden) "Moderate" else "Low"

cat("\n===== NRDS-AKI: single-patient reproduction =====\n")
cat(sprintf("Model            : %d trees, %d design columns, %d predictors\n",
            NTREES, length(X_template), length(selected_feat)))
cat(sprintf("Final refit      : nrounds=%g, max_depth=%g, eta=%g\n",
            med[["nrounds"]], med[["max_depth"]], med[["eta"]]))
cat(sprintf("Predicted AKI p  : %.4f (%.2f%%)\n", prob, 100 * prob))
cat(sprintf("Research stratum : %s\n", stratum))
cat(sprintf("Cut-points       : %.4f / %.4f (Table 6 displays %.3f / %.3f)\n",
            youden, high, disp_y, disp_h))
cat(sprintf("Weights sent     : firstweight=%.3f kg, min_weight=%.3f kg\n",
            d$df$firstweight[1], d$df$min_weight[1]))

# Optional, non-fatal cross-check against the original R booster.
p_rda <- file.path(dirname(here("model.json")), "xgboost_model.rda")
if (file.exists(p_rda) && requireNamespace("xgboost", quietly = TRUE)) {
  e <- new.env(); ok <- tryCatch({ load(p_rda, envir = e); TRUE },
                                 error = function(x) FALSE)
  if (ok && "model_xgboost" %in% ls(e)) {
    p2 <- tryCatch(as.numeric(stats::predict(e$model_xgboost, d$X)),
                   error = function(x) NA_real_)
    if (length(p2) == 1L && is.finite(p2))
      cat(sprintf("Native xgboost p : %.4f  |difference| = %.3g\n",
                  p2, abs(p2 - prob)))
    else cat("Native xgboost p : skipped (legacy binary booster needs 1.7.7.1)\n")
  }
} else {
  cat("Native xgboost p : skipped (xgboost not installed; not required)\n")
}
cat("For research reproduction only - not for clinical use.\n")
cat("Held-out observed AKI rates: 2.3% / 11.0% / 59.4% (n = 335).\n\n")
