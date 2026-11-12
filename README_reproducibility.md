REPRODUCIBILITY README - TP-2026-0897-CL (FINAL v4)

Working directory used by the authors: E:/NARDS   (R 4.3.2)
Exact installed package versions: sessionInfo.rds / sessionInfo.txt
Authorised input (NOT distributed): NRDSNOMICE.csv, an MIMIC-III-derived
analytic cohort placed in the working directory by the holder of a PhysioNet
credential (Certification No. 55551396).

-------------------------------------------------------------------------------
A. REPRODUCE A PREDICTION (no MIMIC-III access, no xgboost required)
-------------------------------------------------------------------------------
  install.packages("jsonlite")        # one time; already a shiny dependency
  Rscript predict_new_patient.R       # edit PATIENT to change values
  Rscript verify_release.R            # structure, thresholds, checksums, DUA

These read model.json (200 trees), model_meta.rds (29 design columns, 22
predictors, defaults, tuning values) and risk_thresholds.csv (0.0651 / 0.3008).
The pure-R tree walker in predict_new_patient.R is the same scorer as app.R;
it agrees with the native xgboost booster to 1.45e-07.

-------------------------------------------------------------------------------
B. REPRODUCE THE ANALYSES (requires an authorised MIMIC-III-derived cohort)
-------------------------------------------------------------------------------
Run order:
  1. Rscript revision_main_v1.R
       -> NestedCV_All_Predictions.csv (pooled OOF predictions for 8 models)
          and R1-R13 aggregate result files in revision_output/.
  2. Rscript revision_tables_figures_v1.R
       -> T2/T2b/T2c/T3/T4/T5/T6 tables, Fig2-Fig9, SNAP-II benchmark,
          subgroup analyses, and the local model_transparency/ artefacts.
  3. Rscript predict_new_patient.R
       -> one single-patient probability and its research risk stratum.
  4. Source app.R for the interactive calculator (needs shiny + jsonlite).

The two main scripts call setwd("E:/NARDS") and write to
"E:/NARDS/revision_output/". On another machine create your own working
directory and replace every occurrence of E:/NARDS with that path, then place
the authorised cohort file NRDSNOMICE.csv there. No result depends on the
absolute path itself. Do NOT run the scripts in RStudio debug mode
(Browse[]> prompt): interrupting a fold loop leaves an empty Prediction_all
and overwrites exported CSVs. Use ordinary Source or Rscript.

-------------------------------------------------------------------------------
C. FOLD SPLITS, SEEDS AND TUNING
-------------------------------------------------------------------------------
  Fold split / held-out split : seed 1234 (stratified 10-fold; fixed 7:3
                                held-out split for risk-stratification only)
  Fold-wise MICE              : m = 5, maxit = 10 (training fold only);
                                held-out fold m = 1; seeds 100+i and 200+i
  Boruta                      : within each training fold, 48 candidates,
                                ntree = 500, maxRuns = 20, TentativeRoughFix
  Inner XGBoost tuning        : inner 5-fold CV, 8-point grid
                                nrounds 100/200, max_depth 3/6, eta 0.05/0.10
  Median selected across folds: nrounds = 100, max_depth = 3, eta = 0.05
                                (reported in Methods; produces all OOF metrics)
  Final single full-cohort    : nrounds = 200, max_depth = 3, eta = 0.05
    refit (released model)      (`med` in the model object; 200 trees in JSON)
  Bootstrap                   : 1,000 replicates, seed 2026
  Imputation/selection/tuning : NEVER on the full cohort before CV

-------------------------------------------------------------------------------
D. CODING DICTIONARIES AND UNITS
-------------------------------------------------------------------------------
AKI_flag1 = outcome. Primary endpoint: mimiciii_derived.kdigo_stages_7day
(7-day view of the official MIMIC-III derived KDIGO concept; general adult
thresholds; baseline serum creatinine = lowest in the preceding 7 days; no
gestational-age or birth-weight adjustment). kdigo_stages_48hr was an
alternative ascertainment window only.

Gestational age is reported exactly as in Table 1: < 28, 29-32, 33-34,
35-36 weeks and Others. Source-extract codes are 0-4; the manuscript does not
treat them as gestational-age ranks. <32 weeks = < 28 + 29-32 weeks;
>=32 weeks = 33-34 + 35-36 weeks; Others is reported separately. The GA_LAB
vector inside the local working artefact is a legacy internal label set and is
NOT the manuscript wording.

Weight_label: 0 = unknown, 1 = ELBW <1000 g, 2 = VLBW 1000-1499 g,
3 = 1500-2499 g, 4 = >=2500 g. firstweight and min_weight are CONTINUOUS
WEIGHTS IN KILOGRAMS (medians 1.505 / 1.380 kg), NOT grams and NOT category
codes; the Shiny UI accepts grams and divides by 1000. This corrects earlier
bundle documentation that mislabelled these two fields as ordinal codes.

risk_thresholds.csv holds the EXACT training-set OOF cut-points
0.0651 / 0.3008; its *_display columns carry the rounded 0.065 / 0.301 labels
in Table 6 and Figures 9-10. app.R and predict_new_patient.R abort at start-up
on stale pairs (0.214 / 0.67, 0.168 / 0.252) or on the rounded display pair.

-------------------------------------------------------------------------------
E. LOCAL ARTEFACTS THAT MUST NOT BE PUBLISHED (PhysioNet MIMIC-III DUA)
-------------------------------------------------------------------------------
revision_tables_figures_v1.R writes
model_transparency/NARDS_AKI_trained_model.rda, which embeds the full
1,115 x 49 patient-level analytic data frame (d_full). Under the DUA that
object, NRDSNOMICE.csv, NARDSImputed_data.*, .RData,
NestedCV_All_Predictions.csv and any per-patient prediction file must NEVER be
uploaded to a public repository or a journal system. Deployment tokens,
rsconnect account secrets and any file containing credentials are likewise
excluded. The public objects are xgboost_model.rda, model.json,
model_meta.rds and risk_thresholds.csv; their boosters are byte-identical to
the booster inside the local artefact and contain no patient rows.

The rsconnect deployment record directory (app/rsconnect/) is a local
by-product of publishing and is not part of this bundle.

Verify downloaded files with SHA256SUMS.txt or `Rscript verify_release.R`.


-------------------------------------------------------------------------------
F. SYNCHRONISATION WITH 20261112NARDSmanuscript5.docx (2026-11-12)
-------------------------------------------------------------------------------
The two released analysis scripts were synchronised with the revised
manuscript. Nine changes matter for reproducibility:

  1. GA_LAB follows Table 1 verbatim: 0 = Others, 1 = <28 weeks (n=283),
     2 = 29-32 weeks (n=405), 3 = 33-34 weeks (n=200), 4 = 35-36 weeks
     (n=92). GA_LEVELS gives the display order, GA_ORDER = 1,2,3,4,0.
  2. <32 weeks = codes 1+2 (AUC 0.8381); >=32 weeks = codes 3+4 (0.8838);
     Others (0) is reported separately and EXCLUDED from that dichotomy.
     Unpaired DeLong p = 0.315.
  3. firstweight and min_weight are CONTINUOUS KILOGRAM values (medians
     1.505 / 1.380 kg); Weight_label is the 0-4 ordinal category. The Shiny
     UI takes grams and divides by 1000.
  4. Primary endpoint = mimiciii_derived.kdigo_stages_7day (118 events,
     10.6%); kdigo_stages_48hr is an alternative ascertainment window only.
  5. report_med (per-fold MEDIAN nrounds = 100) is reported in Methods and
     Supplementary Table S4; it generated ALL pooled OOF performance,
     calibration and both thresholds. The SINGLE deployment refit is fixed at
     med = (nrounds 200, max_depth 3, eta 0.05) -> the released 200-tree
     model.json. The old code let an R12 log overwrite the final refit.
  6. Authoritative cut-points 0.0651 / 0.3008 (display 0.065 / 0.301) are
     written into the auto-generated Methods text; a run's own diagnostic
     thresholds are explicitly marked non-authoritative.
  7. NARDS_ROOT (default E:/NARDS) plus pE() relocate EVERY hard-coded
     E:/NARDS path. Set NARDS_ROOT to your own directory (forward slashes).
  8. Auto-generated local files are now written as
     README_reproducibility_LOCAL.md and predict_example_LOCAL.R, so running
     the pipeline cannot overwrite the released README_reproducibility.md or
     predict_new_patient.R.
  9. The local artefact embedding d_full (1,115 x 49 patient rows) is marked
     NOT publishable under the PhysioNet MIMIC-III data use agreement.

Manuscript item -> released aggregate result
  Table 1 GA categories / AKI rates .... results/GA_Table1_authoritative.csv
  Table 2 model performance + CIs ..... results/T2_model_performance_with_CI.csv
  VIF / correlation matrix ............ results/R2_VIF.csv, R2_correlation_matrix.csv
  Boruta stability .................... results/R3_boruta_stability.csv,
                                       Fig2_Boruta_fold_stability.csv
  Bootstrap CIs / DeLong tests ........ results/R4_bootstrap_CI.csv, R5_delong_tests.csv
  Calibration deciles ................. results/R6_calibration_deciles.csv
  Subgroup AUCs (S3 forest plot) ...... results/subgroup_analyses_FINAL.csv,
                                       subgroup_AUC_comparison_FINAL.csv
  Table 6 / Figures 9-10 risk strata .. results/T6_risk_stratification_decision_*.csv
  Riley sample size / sensitivity ..... results/R11_sample_size.txt,
                                       R10_sensitivity_summary.txt

Correction trail: revision_patches/README.md lists the nine post-11-05
WorkBuddy scripts, their dates and their FINAL / SUPERSEDED status. Those
scripts are verification helpers; the required run order is still section B
above. results/README.md marks the superseded historical values in
R12_methods_reporting.txt (thresholds 0.051 / 0.273) as obsolete.
