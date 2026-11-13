###############################################################################
# app.R - NRDS neonatal AKI risk calculator (XGBoost)
# SHINYAPPS.IO DEPLOYMENT BUILD - 2026-11-12 (based on FINAL v4)
# Manuscript: TP-2026-0897-CL (Translational Pediatrics, major revision)
#
# WHY THIS BUILD DIFFERS FROM FINAL v4 (deployment-critical)
#   Previous deployment builds loaded the xgboost package at startup. On
#   shinyapps.io that package is compiled from source on Linux, and a binary
#   booster written by xgboost 1.7.7.1 is rejected by xgboost 2.x / 3.x
#   ("'xgb.Booster' object is corrupted or is from an incompatible XGBoost
#   version"). Either failure aborts the app with "The application failed to
#   start / exit status 1". THIS BUILD HAS NO XGBOOST DEPENDENCY: it parses the
#   portable JSON booster (model.json, produced by prepare_deploy.R) and walks
#   its 200 trees in pure R. Verified against the real booster on 30 reference
#   rows (5 clinical cases + 25 randomised designs): max absolute difference
#   1.45e-07, caused only by float32 accumulation rounding. The only runtime
#   packages are shiny and jsonlite (jsonlite is already a shiny dependency).
#   Metadata (design columns, predictor dictionary, tuning values) live in
#   model_meta.rds; NO patient-level data are shipped, in line with the
#   MIMIC-III / local-cohort data-use terms.
#
# This file replaces the legacy app that hard-coded 0.214 / 0.67 (an even older
# copy used 0.168 / 0.252). It is a PREDICTION-ONLY app.
#
# WHY THE OLD "TRAIN A FRESH MODEL" BLOCK WAS REMOVED
#   The legacy script re-fit XGBoost on a random 70/30 split of
#   NARDSImputed_data.csv with nrounds = 15, max_depth = 6, eta = 0.3 and ALL
#   columns as predictors, then overwrote xgboost_model.rda. That model is NOT
#   the published model (nested 10-fold CV, training-fold-only MICE / Boruta /
#   inner tuning, 22 selected predictors, 29 design columns). Probabilities
#   from such a model are on a different scale, so the revised cut-points
#   0.0651 / 0.3008 would classify almost everyone as low risk. The training
#   code is therefore removed here; to re-fit, run revision_main_v1.R and
#   revision_tables_figures_v1.R, then rebuild xgboost_model.rda.
#
# SINGLE SOURCE OF TRUTH FOR CUT-POINTS: risk_thresholds.csv
#   youden_threshold    = 0.0651   (Table 6 / Fig 9-10 display 0.065)
#   high_risk_threshold = 0.3008   (Table 6 / Fig 9-10 display 0.301)
#   Derived ONLY from training-set out-of-fold predictions and applied
#   unchanged to the held-out test set. The rounded display values must NEVER
#   be used as cut-points.
#
# OTHER CORRECTIONS vs THE LEGACY APP
#   1) GA_value was undefined in the pasted code, and switch() sent codes 1-5.
#      GA is a 5-level factor with codes 0-4 (Table 1 wording).
#   2) The trained booster was fitted on model.matrix(~ . - 1, ...) with 29
#      columns. The legacy data.matrix() alignment used raw column names and
#      silently mismatched the booster. Here the exact design is rebuilt and
#      aligned to X_template (verified 29/29 columns).
#   3) firstweight / min_weight are KILOGRAMS in the analytic extract
#      (median 1.505 / 1.380 kg), not gram values and not category codes.
#      The UI takes grams and divides by 1000. Weight_label is the 0-4 birth
#      weight category and is derived from birth weight.
#   4) All 22 Boruta-confirmed predictors are present. HR, Apgar scores,
#      PS_flag, Sepsis_of_newborn, HEMATOCRIT_min etc. are NOT final predictors.
#   5) input$* is read only inside eventReactive / render* (reactive context).
#   6) The flow chart is drawn with base graphics: no DiagrammeR dependency.
#   7) Startup validation ABORTS on stale thresholds or on a legacy model
#      file, so a wrongly deployed calculator cannot silently show superseded
#      risk strata.
#
# REQUIRED FILES IN THE APP DIRECTORY (exactly these four go to shinyapps.io)
#   app.R                 this script
#   model.json            version-portable XGBoost booster
#   model_meta.rds        X_template + selected_feat + feature_info + med
#   risk_thresholds.csv   exact cut-points 0.0651 / 0.3008
# Do NOT add deploy.R / prepare_deploy.R / any CSV with patient data to app/.
# keep them one level up so rsconnect does not scan or upload them.
#
# RUN LOCALLY: setwd() to this folder, then shiny::runApp().
# PUBLISH:     Rscript ../deploy.R  (see that file for credentials).
# Set NARDS_MODEL_DIR only if the model files live elsewhere.
#
# RESEARCH PROTOTYPE ONLY: development cohort, internal validation only,
# no external validation. NOT for clinical decision-making.
###############################################################################

suppressPackageStartupMessages({
  library(shiny)
  library(jsonlite)
})
# NOTE: the xgboost package is deliberately NOT loaded or referenced here.
# rsconnect scans library/require calls to decide which packages to install on
# the server; keeping it out of this file removes the only heavyweight C++
# build from the deployment.

# ---------------------------------------------------------------------------
# File locator: works for shinyapps.io, Rscript app.R and source("app.R")
# ---------------------------------------------------------------------------
app_dirs <- function() {
  of <- tryCatch(normalizePath(sys.frame(1)$ofile, mustWork = FALSE),
                 error = function(e) NA_character_)
  d <- c(Sys.getenv("NARDS_MODEL_DIR", unset = ""), getwd(),
         if (!is.na(of)) dirname(of) else NA_character_)
  unique(d[!is.na(d) & nzchar(d)])
}
find_file <- function(name) {
  for (d in app_dirs()) {
    p <- file.path(d, name)
    if (file.exists(p)) return(p)
  }
  NA_character_
}
locate <- function(name) {
  p <- find_file(name)
  if (is.na(p))
    stop("Required file '", name, "' not found in ",
         paste(app_dirs(), collapse = " / "),
         ". Deploy app.R together with model.json, model_meta.rds and ",
         "risk_thresholds.csv in the same directory.")
  p
}

# ---------------------------------------------------------------------------
# Load the portable JSON booster + metadata. SCORING IS DONE IN PURE R.
# ---------------------------------------------------------------------------
MODEL_FORMAT <- "JSON booster / pure-R scorer (shiny + jsonlite only)"
p_json <- find_file("model.json")
p_meta <- find_file("model_meta.rds")
if (is.na(p_json))
  stop("model.json not found in ", paste(app_dirs(), collapse = " / "),
       ". Deploy app.R together with model.json, model_meta.rds and ",
       "risk_thresholds.csv.")
if (is.na(p_meta))
  stop("model_meta.rds not found in ", paste(app_dirs(), collapse = " / "))

BOOSTER <- tryCatch(
  jsonlite::fromJSON(paste(readLines(p_json, warn = FALSE), collapse = "\n"),
                     simplifyVector = FALSE),
  error = function(e) e)
if (inherits(BOOSTER, "error"))
  stop("model.json is not valid JSON: ", conditionMessage(BOOSTER))
L <- BOOSTER$learner
trees_raw <- tryCatch(L$gradient_booster$model$trees,
                      error = function(e) NULL)
if (is.null(trees_raw) || length(trees_raw) < 1L)
  stop("model.json contains no gradient-booster trees.")

as_int <- function(z) as.integer(unlist(z, use.names = FALSE))
as_num <- function(z) as.numeric(unlist(z, use.names = FALSE))
TREES <- lapply(trees_raw, function(t) {
  list(left  = as_int(t$left_children),
       right = as_int(t$right_children),
       idx   = as_int(t$split_indices) + 1L,
       cond  = as_num(t$split_conditions),
       defL  = as_int(t$default_left) == 1L)
})
NTREES <- length(TREES)
bad_tree <- vapply(TREES, function(t)
  length(t$left) < 1L || length(t$left) != length(t$right) ||
  length(t$left) != length(t$cond) || length(t$left) != length(t$idx) ||
  any(is.na(t$left)) || any(is.na(t$cond)), logical(1))
if (any(bad_tree)) stop("Inconsistent tree arrays in model.json.")

base_score <- suppressWarnings(as.numeric(L$learner_model_param$base_score))
if (!is.finite(base_score) || base_score <= 0 || base_score >= 1)
  base_score <- 0.5
BASE_MARGIN <- log(base_score / (1 - base_score))

# XGBoost tree semantics: an internal node takes the LEFT child when
# value < split_condition; a leaf's output is stored in split_conditions.
# JSON node ids are 0-based (-1 marks a leaf) while R is 1-based.
# Missing values follow default_left; our design matrix has no NA, but the
# rule is implemented for completeness.
score_booster <- function(x) {
  s <- BASE_MARGIN
  for (i in seq_len(NTREES)) {
    t <- TREES[[i]]
    node <- 1L
    while (isTRUE(t$left[node] >= 0L)) {
      v <- x[t$idx[node]]
      go_left <- if (is.na(v)) t$defL[node] else (v < t$cond[node])
      node <- (if (isTRUE(go_left)) t$left[node] else t$right[node]) + 1L
    }
    s <- s + t$cond[node]
  }
  1 / (1 + exp(-s))
}

md <- readRDS(p_meta)
miss <- setdiff(c("X_template", "selected_feat", "feature_info", "med"),
                names(md))
if (length(miss) > 0L)
  stop("model_meta.rds lacks: ", paste(miss, collapse = ", "))
X_template    <- as.character(md$X_template)
selected_feat <- as.character(md$selected_feat)
feature_info  <- md$feature_info
med           <- md$med

if (length(X_template) != 29L)
  stop("Model design has ", length(X_template), " columns; expected 29. ",
       "Do not use the legacy 20-feature model with this app.")
if (!identical(selected_feat,
               vapply(feature_info, function(z) z$Feature, character(1))))
  stop("feature_info does not match selected_feat.")
if (length(selected_feat) != 22L)
  stop("Expected 22 predictors, found ", length(selected_feat), ".")
# A JSON booster exported by 1.7 carries NO feature names, so scoring is
# POSITIONAL. build_design() builds a zero matrix whose columns are exactly
# X_template (the original booster's feature_names) and fills each by name.
# Never reorder X_template or change the predictor dictionary. If a booster
# does expose names, enforce equality.
fn <- as.character(unlist(L$feature_names, use.names = FALSE))
if (length(fn) == length(X_template) && !identical(fn, X_template))
  stop("Booster feature names do not match X_template.")

# Startup probe: pure-R scoring must produce a valid probability.
probe <- rep(0, length(X_template))
probe_p <- tryCatch(score_booster(probe), error = function(e) NA_real_)
PREDICT_OK <- length(probe_p) == 1L && is.finite(probe_p) &&
  probe_p > 0 && probe_p < 1

# ---------------------------------------------------------------------------
# Thresholds: exact cut-points from training-set OOF predictions
# ---------------------------------------------------------------------------
thr <- read.csv(locate("risk_thresholds.csv"), stringsAsFactors = FALSE,
                check.names = FALSE)
if (!all(c("youden_threshold", "high_risk_threshold") %in% names(thr)))
  stop("risk_thresholds.csv is missing youden_threshold / high_risk_threshold.")

youden_threshold <- suppressWarnings(as.numeric(thr$youden_threshold[1]))
ppv_threshold    <- suppressWarnings(as.numeric(thr$high_risk_threshold[1]))
disp_youden <- if ("youden_display" %in% names(thr))
  suppressWarnings(as.numeric(thr$youden_display[1])) else round(youden_threshold, 3)
disp_high <- if ("high_risk_display" %in% names(thr))
  suppressWarnings(as.numeric(thr$high_risk_display[1])) else round(ppv_threshold, 3)

stale <- list(c(0.214, 0.67), c(0.168, 0.252), c(0.065, 0.301))
for (s in stale)
  if (is.finite(youden_threshold) && is.finite(ppv_threshold) &&
      abs(youden_threshold - s[1]) < 1e-6 && abs(ppv_threshold - s[2]) < 1e-6)
    stop("STALE THRESHOLDS ", s[1], " / ", s[2], " DETECTED. ",
         "0.065 / 0.301 are the ROUNDED DISPLAY labels, not cut-points. ",
         "Replace risk_thresholds.csv with the exact 0.0651 / 0.3008 values.")

if (!is.finite(youden_threshold) || !is.finite(ppv_threshold) ||
    youden_threshold <= 0 || ppv_threshold >= 1 ||
    youden_threshold >= ppv_threshold ||
    abs(youden_threshold - 0.0651) > 1e-6 ||
    abs(ppv_threshold - 0.3008) > 1e-6)
  stop("risk_thresholds.csv does not match the revised manuscript. ",
       "Expected 0.0651 / 0.3008; found ", youden_threshold, " / ",
       ppv_threshold, ".")

EXPECTED_YOUDEN <- 0.0651
EXPECTED_HIGH   <- 0.3008

# Startup line appears in the shinyapps.io application log. It is the first
# thing to check when a deployment behaves differently from the local build.
message(sprintf(
  paste0("[NARDS-AKI] R %s | jsonlite %s | %s | %d trees | %d design columns | ",
         "cut-points %.4f / %.4f | pure-R probe %s (p=%.6f)"),
  getRversion(), as.character(utils::packageVersion("jsonlite")),
  MODEL_FORMAT, NTREES, length(X_template), youden_threshold, ppv_threshold,
  if (PREDICT_OK) "OK" else "FAILED", probe_p))

# ---------------------------------------------------------------------------
# Coding dictionaries
# ---------------------------------------------------------------------------
# Table 1 wording, verbatim. Code 4 is the residual "Others" category, NOT an
# ordinal rank; never reinterpret these codes as gestational-age ranks.
GA_CHOICES <- c("< 28 weeks" = "1", "29-32 weeks" = "2",
                "33-34 weeks" = "3", "35-36 weeks" = "4",
                "Others (Table 1)" = "0")
BW_CHOICES <- c("Unknown" = "0", "ELBW <1000 g" = "1",
                "VLBW 1000-1499 g" = "2", "1500-2499 g" = "3",
                ">=2500 g" = "4")

grams_to_kg <- function(g) {
  g <- suppressWarnings(as.numeric(g))
  if (!is.finite(g) || g < 0) return(0)
  g / 1000
}
grams_to_label <- function(g) {
  g <- suppressWarnings(as.numeric(g))
  if (!is.finite(g) || g <= 0) return("0")
  if (g < 1000) "1" else if (g < 1500) "2" else if (g < 2500) "3" else "4"
}

LAB <- c(
  HEMATOCRIT_max = "Hematocrit max (%)",
  HEMOGLOBIN_min = "Hemoglobin min (g/dL)",
  HEMOGLOBIN_max = "Hemoglobin max (g/dL)",
  PLATELET_min = "Platelet min (10^9/L)",
  PLATELET_max = "Platelet max (10^9/L)",
  WBC_min = "WBC min (10^9/L)",
  WBC_max = "WBC max (10^9/L)",
  SNAP_II = "SNAP-II score",
  LOS = "Length of stay (days)",
  FirstUrineOutput = "First-day urine output (mL)",
  firstweight = "Birth weight (g; sent to model as kg)",
  min_weight = "Minimum postnatal weight (g; sent to model as kg)",
  Anemia_of_prematurity = "Anemia of prematurity",
  Patent_ductus_arteriosus = "Patent ductus arteriosus (PDA)",
  Other_transitory_neonatal_electrolyte_disturbances =
    "Other transient neonatal electrolyte disturbance",
  NSAIDs = "NSAID exposure",
  vasoentdurationssingle_flag = "Vasopressor use",
  ventdurationssingle_flag = "Mechanical ventilation",
  GA = "Gestational age group (Table 1)",
  diuretics_flag = "Diuretics",
  methylxanthine_flag = "Methylxanthine",
  Weight_label = "Birth-weight category"
)
if (!setequal(names(LAB), selected_feat))
  stop("Input dictionary does not cover the 22 model predictors.")

group_of <- function(f) {
  if (f %in% c("SNAP_II", "LOS", "FirstUrineOutput")) return("Severity and stay")
  if (f %in% c("firstweight", "min_weight", "Weight_label")) return("Weight")
  if (f %in% c("HEMATOCRIT_max", "HEMOGLOBIN_min", "HEMOGLOBIN_max",
               "PLATELET_min", "PLATELET_max", "WBC_min", "WBC_max"))
    return("Laboratory")
  if (identical(f, "GA")) return("Gestational age (Table 1)")
  "Treatment and complications"
}
GROUP_ORDER <- c("Severity and stay", "Weight", "Laboratory",
                 "Treatment and complications", "Gestational age (Table 1)")

make_input <- function(f) {
  id  <- paste0("f_", f$Feature)
  lab <- unname(LAB[[f$Feature]])
  if (identical(f$Type, "factor")) {
    if (identical(f$Feature, "GA"))
      return(selectInput(id, lab, choices = GA_CHOICES, selected = f$Default))
    if (identical(f$Feature, "Weight_label"))
      return(selectInput(id, lab,
                         choices = c("Auto (from birth weight)" = "auto", BW_CHOICES),
                         selected = "auto"))
    if (length(f$Levels) == 2L && all(f$Levels %in% c("0", "1")))
      return(selectInput(id, lab, choices = c("No" = "0", "Yes" = "1"),
                         selected = f$Default))
    return(selectInput(id, lab, choices = stats::setNames(f$Levels, f$Levels),
                       selected = f$Default))
  }
  v <- suppressWarnings(as.numeric(f$Default))
  if (!is.finite(v)) v <- 0
  if (f$Feature %in% c("firstweight", "min_weight"))
    return(numericInput(id, lab, value = round(v * 1000),
                        min = 0, max = 8000, step = 10))
  numericInput(id, lab, value = v, step = 0.1)
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
ui <- fluidPage(
  titlePanel("Neonatal AKI Risk Calculator (XGBoost, revised model)"),
  sidebarLayout(
    sidebarPanel(
      helpText(paste0(
        "22 Boruta-confirmed predictors. Numeric defaults are the training-fold ",
        "medians stored in the released model. Categorical variables use the ",
        "exact study codes; weights are entered in grams.")),
      lapply(GROUP_ORDER, function(g) {
        fs <- Filter(function(z) identical(group_of(z$Feature), g), feature_info)
        if (length(fs) == 0L) return(NULL)
        tagList(h4(g), lapply(fs, make_input))
      }),
      actionButton("predict_btn", "Predict AKI Risk", class = "btn-primary"),
      helpText(paste0(
        "Research prototype: development cohort, internal validation only, ",
        "no external validation. Not for clinical decision-making."))
    ),
    mainPanel(
      h3("Predicted probability of AKI"),
      uiOutput("warning_msg"),
      verbatimTextOutput("pred_prob"),
      uiOutput("risk_label"),
      plotOutput("risk_plot", height = "260px"),
      h4("Risk thresholds"),
      verbatimTextOutput("thr_text"),
      h4("Risk stratification flow chart"),
      plotOutput("flow_chart", height = "330px"),
      h4("Values actually sent to the model"),
      verbatimTextOutput("echo_text"),
      h4("Model information"),
      verbatimTextOutput("model_text")
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------
server <- function(input, output, session) {

  # Rebuild the exact 29-column model.matrix design used at training.
  build_design <- function() {
    vals <- lapply(feature_info, function(f) {
      id <- paste0("f_", f$Feature)
      v <- input[[id]]
      if (is.null(v) || length(v) == 0L || is.na(v)) v <- f$Default
      if (f$Feature %in% c("firstweight", "min_weight"))
        return(grams_to_kg(v))
      if (identical(f$Feature, "Weight_label")) {
        if (identical(as.character(v), "auto"))
          return(grams_to_label(input[["f_firstweight"]]))
        return(as.character(v))
      }
      if (identical(f$Type, "factor"))
        return(factor(as.character(v), levels = f$Levels))
      suppressWarnings(as.numeric(v))
    })
    nm <- vapply(feature_info, function(z) z$Feature, character(1))
    df <- as.data.frame(stats::setNames(vals, nm), check.names = FALSE)
    for (f in feature_info)
      if (identical(f$Type, "factor"))
        df[[f$Feature]] <- factor(as.character(df[[f$Feature]]),
                                  levels = f$Levels)
    X <- stats::model.matrix(~ . - 1, df)
    Xa <- matrix(0, nrow = 1, ncol = length(X_template),
                 dimnames = list(NULL, X_template))
    cn <- intersect(colnames(X), X_template)
    Xa[, cn] <- X[, cn, drop = FALSE]
    if (length(cn) != length(X_template))
      stop("Design-matrix alignment failed: matched ", length(cn),
           " of ", length(X_template), " columns.")
    list(X = Xa, df = df, ncol = length(cn))
  }

  # NOTE: no return() inside a reactive expression - Shiny evaluates the
  # valueExpr as a promise, and return() there raises "no function to return
  # from, jumping to top level". Use a single if/else expression instead.
  result <- eventReactive(input$predict_btn, {
    built <- tryCatch(build_design(), error = function(e) e)
    if (inherits(built, "error")) {
      list(ok = FALSE, msg = conditionMessage(built))
    } else {
      pr <- tryCatch(as.numeric(score_booster(as.numeric(built$X[1, ]))),
                     error = function(e) e)
      if (inherits(pr, "error")) {
        list(ok = FALSE, msg = conditionMessage(pr))
      } else if (length(pr) != 1L || !is.finite(pr)) {
        list(ok = FALSE, msg = "Model returned a non-finite prediction.")
      } else {
        catg <- if (pr >= ppv_threshold) "High"
                else if (pr >= youden_threshold) "Moderate" else "Low"
        list(ok = TRUE, prob = pr, cat = catg, df = built$df,
             ncol = built$ncol)
      }
    }
  }, ignoreNULL = FALSE)

  output$warning_msg <- renderUI({
    r <- result()
    if (isTRUE(r$ok)) {
      NULL
    } else {
      tags$div(style = "color:#b00020;font-weight:bold;",
               paste("Prediction failed:", r$msg))
    }
  })

  output$pred_prob <- renderText({
    r <- result()
    if (!isTRUE(r$ok)) {
      "No prediction available."
    } else {
      sprintf("Predicted AKI probability: %.2f%% (%.4f)", 100 * r$prob, r$prob)
    }
  })

  output$risk_label <- renderUI({
    r <- result()
    if (!isTRUE(r$ok)) {
      NULL
    } else {
      col <- c(Low = "#2e7d32", Moderate = "#e08b00", High = "#c62828")[[r$cat]]
      tags$div(style = paste0("color:", col,
                              ";font-weight:bold;font-size:18px;"),
               paste0("Risk category: ", r$cat))
    }
  })

  output$risk_plot <- renderPlot({
    r <- result()
    if (isTRUE(r$ok)) {
      col <- c(Low = "#2e7d32", Moderate = "#e08b00", High = "#c62828")[[r$cat]]
      barplot(r$prob, col = col, ylim = c(0, 1), width = 0.35,
              xlim = c(0, 1), names.arg = "AKI risk",
              main = "Predicted probability vs. training-OOF cut-points")
      abline(h = youden_threshold, lty = 2, col = "#e08b00", lwd = 2)
      abline(h = ppv_threshold,    lty = 2, col = "#c62828", lwd = 2)
      legend("topright", lty = 2, lwd = 2, bty = "n", cex = 0.85,
             col = c("#e08b00", "#c62828"),
             legend = c(sprintf("Youden %.4f", youden_threshold),
                        sprintf("High risk %.4f", ppv_threshold)))
    }
  })

  output$thr_text <- renderText({
    paste0(
      sprintf("Exact cut-points: Low < %.4f | Moderate %.4f - < %.4f | High >= %.4f\n",
              youden_threshold, youden_threshold, ppv_threshold, ppv_threshold),
      sprintf("Table 6 / Figures 9-10 display: < %.3f | %.3f - %.3f | >= %.3f\n",
              disp_youden, disp_youden, disp_high, disp_high),
      "Derived ONLY from training-set out-of-fold predictions; ",
      "applied unchanged to the held-out test set.")
  })

  output$flow_chart <- renderPlot({
    par(mar = c(0, 0, 0, 0))
    plot.new()
    plot.window(xlim = c(0, 1), ylim = c(0, 1))
    rect(0.28, 0.79, 0.72, 0.97, col = "#dbeafe", border = "#1e40af", lwd = 2)
    text(0.50, 0.88, "XGBoost predicted probability", cex = 0.95, font = 2)

    x0 <- c(0.015, 0.345, 0.675); x1 <- x0 + 0.31
    bg <- c("#dcfce7", "#fef3c7", "#fee2e2")
    bd <- c("#2e7d32", "#e08b00", "#c62828")
    labs <- c(
      paste0("LOW RISK\n< ", sprintf("%.4f", youden_threshold),
             "\n(Table 6 < ", sprintf("%.3f", disp_youden), ")\nRoutine monitoring"),
      paste0("MODERATE RISK\n", sprintf("%.4f", youden_threshold), " - < ",
             sprintf("%.4f", ppv_threshold), "\n(Table 6 ",
             sprintf("%.3f", disp_youden), "-", sprintf("%.3f", disp_high),
             ")\nClose monitoring; avoid nephrotoxins"),
      paste0("HIGH RISK\n>= ", sprintf("%.4f", ppv_threshold),
             "\n(Table 6 >= ", sprintf("%.3f", disp_high),
             ")\nMultidisciplinary review")
    )
    for (i in 1:3) {
      arrows(0.50, 0.79, (x0[i] + x1[i]) / 2, 0.64,
             length = 0.08, lwd = 1.6, col = "#475569")
      rect(x0[i], 0.16, x1[i], 0.63, col = bg[i], border = bd[i], lwd = 2)
      text((x0[i] + x1[i]) / 2, 0.395, labs[i], cex = 0.72)
    }
    text(0.50, 0.065,
         paste0("Held-out test set: Low 2.3% (5/221) | Moderate 11.0% (9/82) | ",
                "High 59.4% (19/32) observed AKI"),
         cex = 0.70, col = "#334155")
    text(0.50, 0.025, "Research labels only - not clinical recommendations",
         cex = 0.66, col = "#64748b")
  })

  output$echo_text <- renderText({
    r <- result()
    if (!isTRUE(r$ok)) {
      "Model inputs unavailable."
    } else {
      d <- r$df
      paste0(
        sprintf("firstweight = %.3f kg   min_weight = %.3f kg   Weight_label = %s\n",
                d$firstweight[1], d$min_weight[1],
                as.character(d$Weight_label[1])),
        sprintf("GA code = %s   SNAP-II = %g   FirstUrineOutput = %g mL\n",
                as.character(d$GA[1]), d$SNAP_II[1], d$FirstUrineOutput[1]),
        sprintf("Design columns matched: %d of %d", r$ncol, length(X_template)))
    }
  })

  output$model_text <- renderText({
    base <- sprintf(paste0(
      "Gradient-boosted trees (JSON) | %d trees | %d design columns | ",
      "max_depth = %g | eta = %g | seed = 1234\n",
      "R %s | jsonlite %s | scorer: %s\n",
      "Full specification: MODEL_CARD.md and Methods."),
      NTREES, length(X_template), med[["max_depth"]], med[["eta"]],
      as.character(getRversion()),
      as.character(utils::packageVersion("jsonlite")), MODEL_FORMAT)
    if (PREDICT_OK) base else paste0(
      base,
      "\nWARNING: the startup prediction probe failed. Check the ",
      "shinyapps.io application log before trusting any probability.")
  })
}

shinyApp(ui, server)
