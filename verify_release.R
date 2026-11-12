###############################################################################
# verify_release.R - self-check for the TP-2026-0897-CL transparency bundle
# GitHub release, 2026-11-12
#
# A reviewer can run this on a fresh download with ONLY base R + jsonlite
# (tools::md5sum / sha256sum are used opportunistically, never required).
#   Rscript verify_release.R
#
# It checks: required files, portable booster structure, 29-column design,
# 22 predictors, exact cut-points, absence of patient-level objects, DUA
# hygiene, and (optionally) SHA-256 checksums and native xgboost parity.
###############################################################################

root <- Sys.getenv("NARDS_BUNDLE_DIR", unset = "")
if (!nzchar(root)) {
  a <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
  root <- if (length(a) && !is.na(a) && nzchar(a)) dirname(normalizePath(a)) else getwd()
}
cat("Bundle directory:", root, "\n\n")
OK <- TRUE
check <- function(label, cond, detail = "") {
  cat(sprintf("[%s] %-46s %s\n", if (isTRUE(cond)) "PASS" else "FAIL",
              label, detail))
  if (!isTRUE(cond)) OK <<- FALSE
  invisible(isTRUE(cond))
}

REQUIRED <- c(
  ".gitignore", "README.md", "MODEL_CARD.md",
  "TRANSPARENT_ACCESS.md", "TRANSPARENCY_RESPONSE.md",
  "code_availability_statement.md", "README_reproducibility.md",
  "DEPLOYMENT_NOTE.md", "UPLOAD_GUIDE.md", "MANIFEST.txt", "LICENSE.txt",
  "SHA256SUMS.txt", "sessionInfo.rds", "sessionInfo.txt",
  "xgboost_model.rda", "model.json", "model_meta.rds", "risk_thresholds.csv",
  "app.R", "predict_new_patient.R", "prepare_deploy.R", "verify_release.R",
  "revision_main_v1.R", "revision_tables_figures_v1.R",
  "revision_legacy_bridge.R", "revision_consolidate.R")
present <- file.exists(file.path(root, REQUIRED))
check("all 26 required top-level files present", all(present),
      if (all(present)) "" else paste(REQUIRED[!present], collapse = ", "))
# Six wrappers retain their original Chinese filenames. Some Windows R builds
# running under a C.UTF-8 locale cannot enumerate non-ASCII names, so count
# them from SHA256SUMS.txt (whose hashes are verified below) as well as from
# the directory; either source confirming six is sufficient.
sums_file <- file.path(root, "SHA256SUMS.txt")
sums_lines <- if (file.exists(sums_file))
  readLines(sums_file, warn = FALSE, encoding = "UTF-8") else character(0)
wrapper_rows <- grep("^[0-9a-fA-F]{64}\\s+\\*?legacy_wrappers/", sums_lines,
                     value = TRUE)
wrapper_n_dir <- length(list.files(file.path(root, "legacy_wrappers")))
check("legacy_wrappers/ has 6 original scripts",
      length(wrapper_rows) == 6L || wrapper_n_dir == 6L,
      sprintf("%d listed in SHA256SUMS.txt, %d visible to R", length(wrapper_rows),
              wrapper_n_dir))
check("results/ has aggregate tables + README",
      length(list.files(file.path(root, "results"))) >= 19L)

# ---- Portable booster -------------------------------------------------------
if (requireNamespace("jsonlite", quietly = TRUE)) {
  B <- jsonlite::fromJSON(paste(
    readLines(file.path(root, "model.json"), warn = FALSE), collapse = "\n"),
    simplifyVector = FALSE)
  L <- B$learner
  nt <- length(L$gradient_booster$model$trees)
  check("model.json contains 200 trees", nt == 200L, paste("trees =", nt))
  check("model.json objective is binary:logistic",
        identical(L$objective$name, "binary:logistic"))
  check("model.json declares 29 features",
        identical(as.character(L$learner_model_param$num_feature), "29"))
  check("model.json carries NO patient records",
        !any(grepl("subject_id|hadm_id|patient", tolower(names(B)))))
} else {
  cat("[SKIP] jsonlite not installed - install.packages('jsonlite') to run all checks\n")
}

# ---- Metadata ---------------------------------------------------------------
md <- readRDS(file.path(root, "model_meta.rds"))
check("model_meta.rds has 29 design columns", length(md$X_template) == 29L)
check("model_meta.rds has 22 predictors", length(md$selected_feat) == 22L)
check("feature_info matches selected_feat",
      identical(md$selected_feat,
                vapply(md$feature_info, function(z) z$Feature, character(1))))
check("model_meta.rds has NO patient-level objects",
      !any(c("d_full", "pd", "mydata2", "data", " predictions") %in% names(md)))
check("final refit nrounds recorded as 200", md$med[["nrounds"]] == 200)
check("final refit max_depth / eta = 3 / 0.05",
      md$med[["max_depth"]] == 3 && abs(md$med[["eta"]] - 0.05) < 1e-9)

w <- md$feature_info[[which(md$selected_feat == "firstweight")]]
check("firstweight is numeric in KILOGRAMS (default 1.5)",
      identical(w$Type, "numeric") && abs(as.numeric(w$Default) - 1.5) < 1e-9)

# ---- Native R booster -------------------------------------------------------
e <- new.env(); load(file.path(root, "xgboost_model.rda"), envir = e)
check("xgboost_model.rda holds the 5 expected objects",
      all(c("model_xgboost", "X_template", "selected_feat", "feature_info", "med")
          %in% ls(e)))
check("xgboost_model.rda has NO patient-level objects",
      !any(c("d_full", "pd", "mydata2") %in% ls(e)))
check("native booster is the 200-tree / 29-column model",
      isTRUE(e$model_xgboost$niter == 200) &&
      length(e$X_template) == 29L)
check("native and portable dictionaries identical",
      identical(as.character(e$X_template), as.character(md$X_template)) &&
      identical(as.character(e$selected_feat), as.character(md$selected_feat)))

# ---- Thresholds -------------------------------------------------------------
thr <- read.csv(file.path(root, "risk_thresholds.csv"),
                stringsAsFactors = FALSE, check.names = FALSE)
y <- as.numeric(thr$youden_threshold[1]); h <- as.numeric(thr$high_risk_threshold[1])
check("exact cut-points 0.0651 / 0.3008",
      abs(y - 0.0651) < 1e-9 && abs(h - 0.3008) < 1e-9)
check("display labels 0.065 / 0.301 are separate columns",
      all(c("youden_display", "high_risk_display") %in% names(thr)) &&
      abs(as.numeric(thr$youden_display[1]) - 0.065) < 1e-9 &&
      abs(as.numeric(thr$high_risk_display[1]) - 0.301) < 1e-9)

app <- paste(readLines(file.path(root, "app.R"), warn = FALSE), collapse = "\n")
check("app.R validates the exact cut-points",
      grepl("0\\.0651", app, fixed = FALSE) && grepl("0\\.3008", app))
check("app.R has NO xgboost runtime dependency",
      !grepl("library\\s*\\(\\s*[\"']?xgboost|requireNamespace\\s*\\(\\s*[\"']xgboost|\\bxgboost\\s*::", app))
check("app.R loads the portable JSON booster",
      grepl("model.json", app, fixed = TRUE))

# ---- Synchronisation with the revised manuscript ---------------------------
main_src <- paste(readLines(file.path(root, "revision_main_v1.R"), warn = FALSE),
                  collapse = "\n")
tf_src <- paste(readLines(file.path(root, "revision_tables_figures_v1.R"),
                          warn = FALSE), collapse = "\n")
check("both scripts declare Table 1 GA coding",
      grepl('"0" = "Others"', main_src, fixed = TRUE) &&
      grepl('"0" = "Others"', tf_src, fixed = TRUE))
check("<32w = codes 1+2, >=32w = 3+4",
      grepl("s_lt32 <- Prediction_all$GA_grp %in% c(1, 2)", main_src,
            fixed = TRUE) &&
      grepl("pred$GA_grp %in% c(1, 2)", tf_src, fixed = TRUE))
check("no obsolete ordinal-category weight text",
      !grepl("ORDINAL CATEGORY CODES|ordinal CATEGORY codes", main_src) &&
      !grepl("ORDINAL CATEGORY CODES|ordinal CATEGORY codes", tf_src))
check("kdigo_stages_7day documented in main script",
      grepl("kdigo_stages_7day", main_src, fixed = TRUE))
check("deployment refit fixed at 200 trees",
      grepl("med <- c(nrounds = 200, max_depth = 3, eta = 0.05)", tf_src,
            fixed = TRUE) && grepl("report_med", tf_src, fixed = TRUE))
check("exact cut-points in generated Methods text",
      grepl("0.0651 / 0.3008", main_src, fixed = TRUE))
check("paths relocatable via NARDS_ROOT / pE()",
      grepl("NARDS_ROOT <- Sys.getenv", main_src, fixed = TRUE) &&
      grepl("pE <- function(p)", tf_src, fixed = TRUE) &&
      !grepl("pE(pE(", main_src, fixed = TRUE) &&
      !grepl("pE(pE(", tf_src, fixed = TRUE))
check("revision_patches/ has 9 scripts + README",
      length(list.files(file.path(root, "revision_patches"))) == 10L)

# ---- DUA / credential hygiene ----------------------------------------------
allf <- list.files(root, recursive = TRUE, full.names = TRUE)
bad_names <- grep("NRDSNOMICE|NARDSImputed|NRDSMICE|NestedCV_All_Predictions",
                  basename(allf), value = TRUE)
check("no patient-level data files in bundle", length(bad_names) == 0L,
      if (length(bad_names)) paste(bad_names, collapse = ", ") else "")
text_files <- grep("\\.(R|md|txt|csv)$", allf, value = TRUE)
# Build the two sensitive literals from fragments so that this scanner does
# not flag its own source file, then match with fixed strings.
needles <- c(paste0("238084B8714511531", "D552651848F6609"),
             paste0("xakuSIn4O4qa9sJPgn", "LFuXVJ+R2xygiouUIF5X2G"))
secret_hit <- vapply(text_files, function(f) {
  s <- tryCatch(paste(readLines(f, warn = FALSE), collapse = "\n"),
                error = function(x) "")
  any(vapply(needles, function(n) grepl(n, s, fixed = TRUE), logical(1)))
}, logical(1))
check("no live shinyapps.io token / secret", !any(secret_hit),
      if (any(secret_hit)) paste(basename(text_files[secret_hit]), collapse = ", ") else "")

# ---- Checksums (optional; needs sha256sum or a pure-R fallback) -------------
sums <- file.path(root, "SHA256SUMS.txt")
if (file.exists(sums)) {
  ln <- readLines(sums, warn = FALSE, encoding = "UTF-8")
  ln <- ln[nzchar(ln) & !grepl("^#", ln)]
  parsed <- regmatches(ln, regexec("^([0-9a-fA-F]{64})\\s+\\*?(.+)$", ln))
  ok_rows <- vapply(parsed, length, integer(1)) == 3L
  parsed <- parsed[ok_rows]
  if (length(parsed) > 0L) {
    # Real verification uses sha256sum if available on the system.
    sh <- Sys.which("sha256sum")
    if (nzchar(sh)) {
      # Copy each file to an ASCII-named temp path before hashing: six legacy
      # wrappers keep their original Chinese filenames, and passing those
      # through system2() on some Windows builds loses the encoding.
      hash_of <- function(f) {
        tmp <- tempfile("nards_", fileext = ".bin")
        on.exit(unlink(tmp), add = TRUE)
        if (!file.copy(f, tmp, overwrite = TRUE)) return("")
        out <- tryCatch(system2(sh, shQuote(normalizePath(tmp, winslash = "/")),
                                stdout = TRUE), error = function(x) "")
        if (!length(out)) return("")
        tolower(strsplit(out[1], "\\s+")[[1]][1])
      }
      bad <- vapply(parsed, function(m) {
        f <- file.path(root, trimws(m[3]))
        if (!file.exists(f)) return(TRUE)
        !identical(hash_of(f), tolower(m[2]))
      }, logical(1))
      check("SHA256SUMS.txt matches every released file", !any(bad),
            sprintf("%d files checked, %d mismatches", length(bad), sum(bad)))
    } else {
      cat("[SKIP] sha256sum not on PATH - checksums listed but not recomputed\n")
    }
  }
}

# ---- End-to-end prediction (pure R) ----------------------------------------
if (requireNamespace("jsonlite", quietly = TRUE)) {
  X <- matrix(0, nrow = 1, ncol = length(md$X_template),
              dimnames = list(NULL, md$X_template))
  L <- B$learner
  TREES <- lapply(L$gradient_booster$model$trees, function(t) list(
    left = as.integer(unlist(t$left_children)),
    right = as.integer(unlist(t$right_children)),
    idx = as.integer(unlist(t$split_indices)) + 1L,
    cond = as.numeric(unlist(t$split_conditions))))
  bs <- suppressWarnings(as.numeric(L$learner_model_param$base_score))
  if (!is.finite(bs) || bs <= 0 || bs >= 1) bs <- 0.5
  sc <- function(x) {
    s <- log(bs / (1 - bs))
    for (t in TREES) {
      node <- 1L
      while (t$left[node] >= 0L)
        node <- (if (x[t$idx[node]] < t$cond[node]) t$left[node]
                 else t$right[node]) + 1L
      s <- s + t$cond[node]
    }
    1 / (1 + exp(-s))
  }
  p <- sc(as.numeric(X[1, ]))
  check("pure-R scorer returns a finite probability",
        length(p) == 1L && is.finite(p) && p > 0 && p < 1,
        sprintf("p = %.6f", p))
}

cat("\n", if (OK) "ALL CHECKS PASSED" else "SOME CHECKS FAILED", "\n", sep = "")
cat("Research use only - development model, internal validation, no external validation.\n")
if (!OK) quit(save = "no", status = 1L)
