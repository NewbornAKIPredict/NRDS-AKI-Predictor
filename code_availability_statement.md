DATA AND CODE AVAILABILITY STATEMENT
TP-2026-0897-CL (Translational Pediatrics, major revision)
Manuscript-ready text - 2026-11-12, aligned to 20261112NARDSmanuscript5.docx

-------------------------------------------------------------------------------
Replace the SECOND paragraph of the Footnote (the one beginning "The source
code, trained model implementation, model card and Shiny-based NRDS-AKI
prediction calculator ...") with the text below. The first paragraph (Data
Sharing Statement) stays as it is and is reproduced here for completeness.
-------------------------------------------------------------------------------

Data Sharing Statement

Clinical data were extracted using Structured Query Language from the Medical
Information Mart for Intensive Care III (MIMIC-III) database
(https://doi.org/10.13026/C2XW26). Access was obtained through the PhysioNet
credentialing process after completion of the required human research
protection training (Certification No. 55551396). Because of the MIMIC-III
data use agreement, patient-level data cannot be publicly redistributed; the
authors confirm their willingness to share the derived analytic dataset
dictionary, the complete analysis code, the trained model and the model card
with qualified researchers on reasonable request. The completed Data Sharing
Statement form is submitted with the manuscript.

Code and model availability

The complete executable code, the trained model in both its native R and
version-portable JSON forms, the model card, the exact software environment
and a runnable single-patient example are supplied as Supplementary Material
and deposited in the public repository https://github.com/NewbornAKIPredict/NRDS-AKI-Predictor. The live Shiny
calculator built from the same four released files (app.R, model.json,
model_meta.rds and risk_thresholds.csv) is available at https://dingliu.shinyapps.io/NRDS-aki-predictor/.

All revised analyses are reproducible from `revision_main_v1.R` (nested
10-fold cross-validation with training-fold-only MICE, per-fold Boruta
selection and inner-CV hyperparameter tuning, plus analyses R1-R13) and
`revision_tables_figures_v1.R` (Tables 2-6, Figures 2-9, the SNAP-II
single-predictor benchmark, subgroup analyses and the model artefacts). Six
wrappers for the original scripts, a run-order README, a model-conversion
script and an integrity-check script are included. The fold split is
regenerated with seed 1234, fold-wise MICE with seeds 100+i and 200+i and the
1,000-replicate bootstrap with seed 2026. Exact software versions are recorded
in sessionInfo.rds and sessionInfo.txt (R 4.3.2, xgboost 1.7.7.1) and file
integrity in SHA256SUMS.txt.

The final trained XGBoost model is released in two equivalent forms:
xgboost_model.rda (the original R booster together with the 29-column
model-matrix template, the 22 Boruta-confirmed predictors, per-feature
defaults and the final refit hyperparameters) and model.json (a
version-portable 200-tree JSON booster) with its dictionary in model_meta.rds.
Both were verified to give identical predictions (maximum absolute difference
1.45x10-7) and contain no patient records. Hyperparameters were tuned by inner
5-fold cross-validation inside each training fold over an eight-point grid;
the median selected values across folds, reported in the Methods, were
nrounds = 100, max_depth = 3 and eta = 0.05 (objective binary:logistic; seed
= 1234). The single deployment model was then refit once on the full imputed
cohort with nrounds = 200, max_depth = 3 and eta = 0.05, as recorded in the
released model object; its 200 trees are those in model.json. All performance
estimates in this article were computed from pooled out-of-fold predictions of
the per-fold models, not from the deployment refit. All other XGBoost settings
remained at the xgboost 1.7.7.1 defaults (subsample = 1, colsample_bytree =
1, min_child_weight = 1, gamma = 0, lambda = 1, alpha = 0).

risk_thresholds.csv stores the exact training-set out-of-fold cut-points
0.0651 and 0.3008 (displayed as 0.065 and 0.301 in Table 6 and Figures 9-10).
app.R and predict_new_patient.R read those exact values and terminate if a
superseded or rounded pair is supplied. predict_new_patient.R reproduces a
single-patient probability using only base R and jsonlite, without installing
xgboost or accessing MIMIC-III. The coding dictionaries follow Table 1
verbatim: gestational-age categories < 28, 29-32, 33-34, 35-36 weeks and
Others; Weight_label 0 = unknown, 1 = <1000 g, 2 = 1000-1499 g,
3 = 1500-2499 g, 4 = >=2500 g. Birth weight and minimum postnatal weight are
continuous variables in kilograms.

The primary AKI outcome was taken from the 7-day view of the official MIMIC-III
derived KDIGO staging concept (mimiciii_derived.kdigo_stages_7day, built on
mimiciii_derived.kdigo_stages; MIT-LCP mimic-code repository,
https://github.com/MIT-LCP/mimic-code/tree/main/mimic-iii/concepts/organfailure),
whose baseline-creatinine and staging rules are reproduced verbatim in the
Methods. The 48-h view (kdigo_stages_48hr) was an alternative ascertainment
window and did not define the primary endpoint. Patient-level data cannot be
redistributed under the PhysioNet MIMIC-III data use agreement; the provided
code reconstructs the analytic cohort from an authorised local copy of
MIMIC-III.

-------------------------------------------------------------------------------
The model is a development-stage research tool with internal validation only,
no external validation, and is not for clinical use (MODEL_CARD.md section 2).
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
Author note (NOT part of the manuscript text): the released analysis scripts
were synchronised with 20261112NARDSmanuscript5.docx on 2026-11-12 (Table 1 GA
coding, continuous kilogram birth weights, the kdigo_stages_7day primary
endpoint, exact cut-points, and the separation of the per-fold median
nrounds = 100 from the 200-tree deployment refit). The correction trail and
the status of every historical script are in revision_patches/README.md.
-------------------------------------------------------------------------------
