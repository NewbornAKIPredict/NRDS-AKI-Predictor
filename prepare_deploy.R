###############################################################################
# prepare_deploy.R - local, one-time preparation of the shinyapps.io bundle
# Manuscript: TP-2026-0897-CL (Translational Pediatrics, major revision)
#
# WHAT IT DOES
#   1. Converts the legacy binary booster (xgboost_model.rda, written by
#      xgboost 1.7.7.1) into the VERSION-PORTABLE JSON booster model.json.
#   2. Writes model_meta.rds = design columns + predictor dictionary + tuning
#      values. NO patient-level rows are ever included (data-use compliance).
#   3. Copies risk_thresholds.csv and refuses stale / rounded cut-points.
#   4. Verifies that the JSON booster gives bit-identical predictions to the
#      original booster on five reference patients, and that the three risk
#      strata are unchanged.
#
# WHEN TO RUN
#   The converted model.json / model_meta.rds are ALREADY SHIPPED in app/.
#   Re-run this only if the trained model changes. The full conversion branch
#   needs the R environment that produced the .rda (R 4.3.2 + xgboost
#   1.7.7.1), because xgboost 2.x/3.x cannot even read a legacy binary
#   booster. Under a newer xgboost the script runs in VERIFY-ONLY mode: it
#   checks the already-shipped model.json and exits successfully.
#
# USAGE
#   Rscript prepare_deploy.R [source_dir]
#   Environment overrides:
#     NARDS_DEPLOY_ROOT   directory containing app/ (default: this script's dir)
#     NARDS_V4_DIR        directory containing xgboost_model.rda
#     R_LIBS_USER         add a library path if xgboost is not in the default lib
#
# All comments are ASCII on purpose: GBK-encoded Chinese in an R script has
# previously broken parse() on this machine.
###############################################################################

# ---------------------------------------------------------------------------
# Paths - robust to Rscript, source() and an interactive RStudio console.
# The previous version relied only on --file=, which is absent when lines are
# pasted into the console; it then used getwd() and looked for app/ in the
# wrong folder.
# ---------------------------------------------------------------------------
argv <- commandArgs(trailingOnly = TRUE)

is_root <- function(d) {
  if (!is.character(d) || length(d) != 1L || is.na(d) || !nzchar(d)) return(FALSE)
  a <- file.path(d, "app")
  dir.exists(a) &&
    (file.exists(file.path(a, "app.R")) || file.exists(file.path(a, "model_meta.rds")))
}

script_dir <- function() {
  fa <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(fa)) {
    p <- normalizePath(sub("^--file=", "", fa[1L]), mustWork = FALSE)
    if (file.exists(p) && !dir.exists(p)) return(dirname(p))
  }
  for (i in seq_len(sys.nframe())) {
    o <- tryCatch(get("ofile", envir = sys.frame(i), inherits = FALSE),
                  error = function(e) NULL)
    if (is.character(o) && length(o) == 1L && !is.na(o) && nzchar(o)) {
      p <- normalizePath(o, mustWork = FALSE)
      if (file.exists(p) && !dir.exists(p)) return(dirname(p))
    }
  }
  NULL
}

CAND <- character(0)
add_cand <- function(x) {
  if (!is.character(x)) return(invisible(NULL))
  for (v in x) if (!is.na(v) && nzchar(v)) CAND <<- c(CAND, v)
  invisible(NULL)
}
add_cand(Sys.getenv("NARDS_DEPLOY_ROOT", unset = ""))
sd <- script_dir()
if (!is.null(sd)) add_cand(c(sd, file.path(sd, "app")))
wd <- getwd()
add_cand(c(wd, file.path(wd, "app"),
           file.path(wd, "NRDS_AKI_shinyapps"),
           file.path(dirname(wd), "NRDS_AKI_shinyapps")))
for (base in unique(c(path.expand("~"), Sys.getenv("USERPROFILE", unset = "")))) {
  if (!nzchar(base)) next
  add_cand(c(file.path(base, "Desktop", "NRDS_AKI_shinyapps"),
             file.path(base, "Desktop", "NRDS_AKI_shinyapps", "app"),
             file.path(base, "OneDrive", "Desktop", "NRDS_AKI_shinyapps")))
}
CAND <- unique(CAND)

ROOT <- NULL
for (d in CAND) {
  if (is_root(d)) {
    ROOT <- normalizePath(d, mustWork = TRUE)
    break
  }
  if (dir.exists(d) && identical(basename(d), "app") &&
      (file.exists(file.path(d, "app.R")) || file.exists(file.path(d, "model_meta.rds")))) {
    ROOT <- normalizePath(dirname(d), mustWork = TRUE)
    break
  }
}
if (is.null(ROOT))
  stop("Could not find the deployment root containing app/.\n",
       "Current working directory: ", wd, "\n",
       "Searched:\n  ", paste(CAND, collapse = "\n  "), "\n",
       "Fix with: Sys.setenv(NARDS_DEPLOY_ROOT = ",
       "'C:/Users/13607/Desktop/NRDS_AKI_shinyapps')\n",
       "or: setwd('C:/Users/13607/Desktop/NRDS_AKI_shinyapps')\n")
APP_DIR <- file.path(ROOT, "app")
cat("Working directory:", wd, "\n")
cat("Deployment root:", ROOT, "\n")

# Chinese folder name written with \u escapes so this file stays pure ASCII.
DEFAULT_V4 <- paste0("C:/Users/13607/Desktop/NARDS\u548cAKI\u7684\u8fd4\u4fee",
                     "\u610f\u89c1/NRDS_AKI_Calculator_FINAL_v4")
SRC_DIR <- if (length(argv) >= 1L) argv[1L] else
  Sys.getenv("NARDS_V4_DIR", unset = DEFAULT_V4)

RDA  <- file.path(SRC_DIR, "xgboost_model.rda")
CSV  <- file.path(SRC_DIR, "risk_thresholds.csv")
JSON <- file.path(APP_DIR, "model.json")
META <- file.path(APP_DIR, "model_meta.rds")
DST_CSV <- file.path(APP_DIR, "risk_thresholds.csv")

if (!requireNamespace("xgboost", quietly = TRUE))
  stop("xgboost is not installed here. Add its library path via R_LIBS_USER.")
suppressPackageStartupMessages(library(xgboost))
XGB_VER <- as.character(utils::packageVersion("xgboost"))
cat("xgboost:", XGB_VER, "\nroot:", ROOT, "\nsource:", SRC_DIR, "\n")

# ---------------------------------------------------------------------------
# Load metadata (shipped) and build five reference design rows
# ---------------------------------------------------------------------------
if (!file.exists(META)) stop("Missing ", META, ". Run this script in the ",
                             "R 4.3.2 / xgboost 1.7.7.1 environment first.")
meta <- readRDS(META)
need_meta <- c("X_template", "selected_feat", "feature_info", "med")
if (!all(need_meta %in% names(meta)))
  stop("model_meta.rds lacks: ",
       paste(setdiff(need_meta, names(meta)), collapse = ", "))
XT <- as.character(meta$X_template)
if (length(XT) != 29L) stop("Expected 29 design columns, found ", length(XT))
if (length(meta$selected_feat) != 22L)
  stop("Expected 22 predictors, found ", length(meta$selected_feat))

mk <- function(snap = 3, nsaids = "0", ga = "0", bw = 900, wt = "3") {
  vals <- lapply(meta$feature_info, function(f) {
    if (f$Feature == "SNAP_II") return(snap)
    if (f$Feature == "NSAIDs") return(nsaids)
    if (f$Feature == "GA") return(ga)
    if (f$Feature == "Weight_label") return(wt)
    if (f$Feature %in% c("firstweight", "min_weight")) return(bw / 1000)
    if (identical(f$Type, "factor"))
      return(factor(as.character(f$Default), levels = f$Levels))
    suppressWarnings(as.numeric(f$Default))
  })
  nm <- vapply(meta$feature_info, function(z) z$Feature, character(1))
  df <- as.data.frame(stats::setNames(vals, nm), check.names = FALSE)
  for (f in meta$feature_info)
    if (identical(f$Type, "factor"))
      df[[f$Feature]] <- factor(as.character(df[[f$Feature]]), levels = f$Levels)
  X <- stats::model.matrix(~ . - 1, df)
  Xa <- matrix(0, nrow = 1, ncol = length(XT), dimnames = list(NULL, XT))
  cn <- intersect(colnames(X), XT)
  Xa[, cn] <- X[, cn, drop = FALSE]
  if (length(cn) != length(XT))
    stop("Design alignment failed: ", length(cn), " of ", length(XT))
  Xa
}
cases <- list(
  default  = mk(),
  snap30   = mk(snap = 30),
  snap30ns = mk(snap = 30, nsaids = "1"),
  lowbw    = mk(snap = 60, ga = "4", bw = 700, wt = "1"),
  extreme  = mk(snap = 100, ga = "0", bw = 3200, wt = "4", nsaids = "1")
)

# ---------------------------------------------------------------------------
# Conversion branch (only possible where the legacy booster can be scored)
# ---------------------------------------------------------------------------
converted <- FALSE
legacy_readable <- FALSE
E <- new.env()
if (file.exists(RDA)) {
  try(load(RDA, envir = E), silent = TRUE)
  if (all(c("model_xgboost", "X_template", "selected_feat",
            "feature_info", "med") %in% ls(E))) {
    legacy_readable <- tryCatch({
      p <- as.numeric(predict(E$model_xgboost, cases$default))
      length(p) == 1L && is.finite(p)
    }, error = function(e) FALSE)
  }
}

if (legacy_readable) {
  cat("\nLegacy booster is readable -> re-exporting portable artefacts.\n")
  # The JSON export drops feature names, so scoring becomes positional. Prove
  # that the original booster's names are exactly the design columns we ship.
  bfn <- E$model_xgboost$feature_names
  if (is.null(bfn) || !identical(as.character(bfn), as.character(E$X_template)))
    stop("Original booster feature_names do not match X_template; a portable ",
         "positional booster would be unsafe. Do NOT deploy.")
  if (!identical(as.character(E$X_template), XT))
    stop("Source .rda design columns differ from the shipped metadata.")
  ref <- vapply(cases, function(X) as.numeric(predict(E$model_xgboost, X)),
                numeric(1))
  xgb.save(E$model_xgboost, JSON)
  saveRDS(list(
    X_template    = as.character(E$X_template),
    selected_feat = as.character(E$selected_feat),
    feature_info  = E$feature_info,
    med           = E$med
  ), META, version = 2L)
  port <- xgb.load(JSON)
  got <- vapply(cases, function(X) as.numeric(predict(port, X)), numeric(1))
  d <- max(abs(got - ref))
  cat("max |JSON - original| =", format(d, digits = 17), "\n")
  if (!is.finite(d) || d > 1e-12)
    stop("Portable model predictions differ from the original booster. ",
         "Do NOT deploy this model.json.")
  converted <- TRUE
} else {
  cat(paste0("\nLegacy .rda cannot be scored by xgboost ", XGB_VER,
             " (expected for 2.x/3.x). VERIFY-ONLY mode: checking the ",
             "already-shipped model.json.\n"))
  if (!file.exists(JSON)) stop("model.json is missing and the legacy booster ",
                               "cannot be converted here. Run this script ",
                               "under xgboost 1.7.7.1.")
}

# ---------------------------------------------------------------------------
# Verify the shipped portable model with the CURRENT xgboost
# ---------------------------------------------------------------------------
port <- xgboost::xgb.load(JSON)
got <- vapply(cases, function(X) as.numeric(predict(port, X)), numeric(1))
strata <- ifelse(got >= 0.3008, "High",
                 ifelse(got >= 0.0651, "Moderate", "Low"))
cat("\nPredictions with xgboost", XGB_VER, ":\n")
print(round(got, 8))
cat("Strata:", paste(names(strata), strata, sep = "=", collapse = " | "), "\n")
if (!identical(unname(strata), c("Low", "Moderate", "Moderate",
                                 "Moderate", "High")))
  stop("Risk strata of the portable model are inconsistent. Do NOT deploy.")

# ---------------------------------------------------------------------------
# Thresholds: exact values only, never the rounded display labels
# ---------------------------------------------------------------------------
if (!file.exists(CSV))
  stop("risk_thresholds.csv not found in ", SRC_DIR)
thr <- read.csv(CSV, stringsAsFactors = FALSE, check.names = FALSE)
y <- suppressWarnings(as.numeric(thr$youden_threshold[1]))
h <- suppressWarnings(as.numeric(thr$high_risk_threshold[1]))
if (!is.finite(y) || !is.finite(h) ||
    abs(y - 0.0651) > 1e-6 || abs(h - 0.3008) > 1e-6)
  stop("risk_thresholds.csv must contain the EXACT cut-points 0.0651 / ",
       "0.3008 (found ", y, " / ", h, "). The rounded 0.065 / 0.301 and the ",
       "superseded 0.168 / 0.252 and 0.214 / 0.67 are not acceptable.")
file.copy(CSV, DST_CSV, overwrite = TRUE)

cat("\n---------------------------------------------------------------\n")
cat(if (converted) "CONVERSION + VERIFICATION PASSED\n"
    else "VERIFICATION PASSED (shipped model.json reused)\n")
cat("app/ is ready for shinyapps.io:\n")
for (f in c("app.R", "model.json", "model_meta.rds", "risk_thresholds.csv")) {
  p <- file.path(APP_DIR, f)
  cat(sprintf("  %-24s %8.0f bytes\n", f,
              if (file.exists(p)) file.info(p)$size else NA_real_))
}
cat("Next: Rscript deploy.R\n")
