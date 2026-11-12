TRANSPARENT ACCESS TO THE CODE AND THE TRAINED MODEL
Reviewer-facing point-by-point answer
TP-2026-0897-CL (Translational Pediatrics, major revision) - GitHub release
2026-11-12

This document answers the two reviewer statements about reproducibility. It is
written so that each reply can be pasted directly into the response letter.

===============================================================================
COMMENT A (Major issues, statistical/reporting section)
"No accessible code for the full pipeline is provided (although GitHub + Shiny
are promised), nor version parameters or fold splits."
===============================================================================

Reply: We accept this criticism. In the original submission only a partial
deployment script and a promise of a repository were available. With the
revision we now release the complete executable pipeline as Supplementary
Material and in the public repository
https://github.com/NewbornAKIPredict/NRDS-AKI-Predictor .

(1) Full pipeline code. revision_main_v1.R performs the stratified nested
10-fold cross-validation with training-fold-only MICE (m = 5, maxit = 10;
held-out folds m = 1), per-fold Boruta selection over the 48-variable
candidate pool (ntree = 500, maxRuns = 20, TentativeRoughFix) and inner
5-fold XGBoost tuning over the 8-point grid (nrounds 100/200, max_depth 3/6,
eta 0.05/0.10), then exports pooled out-of-fold predictions and analyses
R1-R13. revision_tables_figures_v1.R regenerates Tables 2-6, Figures 2-9, the
SNAP-II single-predictor benchmark, the subgroup analyses, the calibration and
decision-curve outputs and the model artefacts. The six original scripts are
preserved as thin wrappers in legacy_wrappers/ so that the pre-revision
analysis remains inspectable. revision_consolidate.R restores the canonical
result CSVs after they are opened in Excel/WPS.

(2) Fold splits and seeds. The split is regenerated deterministically by
seed 1234 (stratified 10-fold plus the fixed 7:3 held-out split used for the
risk-stratification evaluation). Fold-wise MICE seeds are 100+i and 200+i; the
1,000-replicate bootstrap uses seed 2026. No tuning used held-out data.
Per-fold selected hyperparameters and the fold-wise Boruta confirmation
frequency are supplied as aggregate CSVs in results/ (R3_boruta_stability.csv,
Fig2_Boruta_fold_stability.csv, R12_methods_reporting.txt).

(3) Version parameters. The exact environment is recorded in sessionInfo.rds
and sessionInfo.txt (R 4.3.2; xgboost 1.7.7.1; all loaded packages). The
inner-CV grid, the median selected values across folds (nrounds = 100,
max_depth = 3, eta = 0.05, objective binary:logistic, seed = 1234) and the
final full-cohort refit (nrounds = 200, max_depth = 3, eta = 0.05) are stated
in the Methods, Supplementary Table S4, MODEL_CARD.md and in the released
model object itself. The distinction between the per-fold median (which
generated all reported out-of-fold performance) and the single deployment
refit (200 trees) is documented explicitly to avoid ambiguity.

(4) Runnable without privileged data or compiled dependencies. Because
MIMIC-III may not be redistributed and xgboost binaries are version-specific,
we additionally converted the booster to a version-portable JSON model and
wrote a pure-R tree walker. `Rscript predict_new_patient.R` needs only base R
and jsonlite and reproduces a probability and risk stratum from the released
model; `verify_release.R` checks the model structure, exact cut-points, file
checksums and the absence of patient-level objects. Scoring agrees with the
native xgboost booster to within 1.45x10-7 (float32 accumulation).

(5) Integrity. SHA256SUMS.txt gives a checksum for every released file, and
the bundle contains no patient-level data, no per-patient prediction file and
no deployment credential, in accordance with the PhysioNet MIMIC-III data use
agreement.

Changes in the text: Footnote (Data Sharing Statement and the code/model
availability paragraph), Methods ("Model specification, reproducibility and
reporting", MICE, Boruta and tuning paragraphs), Supplementary Table S4
(TRIPOD+AI items 15a-15b), Reply 11. (see Page __, Line __).

===============================================================================
COMMENT B (Recommended / desirable)
"Transparent access to the code and the trained model."
===============================================================================

Reply: This item is now completed in full.

Code. The complete analysis code, the six legacy wrappers, the run-order
README, the Shiny calculator source (app.R), a model-conversion script
(prepare_deploy.R), a single-patient example (predict_new_patient.R) and an
integrity check (verify_release.R) are supplied as a self-contained
supplementary archive
(TP-2026-0897-CL_GitHub_Upload_FINAL.zip) and deposited in the
public repository https://github.com/NewbornAKIPredict/NRDS-AKI-Predictor .
All random seeds, the exact R and package versions, the fold construction, the
coding dictionaries and the aggregate result tables are included.

Trained model. The final XGBoost model is released in two equivalent forms:
xgboost_model.rda (original R booster plus the 29-column model-matrix
template, the 22 Boruta-confirmed predictors, per-feature defaults and the
final refit hyperparameters) and model.json (version-portable 200-tree JSON
booster) with its dictionary in model_meta.rds. Both were verified to produce
identical predictions (maximum absolute difference 1.45x10-7). The released
objects contain NO patient records: an earlier local artefact that embedded
the 1,115 x 49 analytic data frame was excluded to comply with the MIMIC-III
data use agreement, and its booster is byte-identical to the released one.
risk_thresholds.csv holds the exact training-set out-of-fold cut-points
0.0651 / 0.3008 (displayed as 0.065 / 0.301 in Table 6 and Figures 9-10);
app.R and predict_new_patient.R read the exact values and abort if a
superseded pair (0.214 / 0.67, 0.168 / 0.252) or the rounded display pair is
deployed.

Accessibility. No login, no MIMIC-III credential and no xgboost installation
are needed to score the model: `Rscript predict_new_patient.R` runs on any
machine with base R and jsonlite. The same four released files
(app.R, model.json, model_meta.rds, risk_thresholds.csv) power the public
calculator at https://dingliu.shinyapps.io/NRDS-aki-predictor/ , and
DEPLOYMENT_NOTE.md documents that build. MODEL_CARD.md discloses the outcome
definition, the leakage-free pipeline, inputs and units, performance,
limitations and the explicit prohibition on clinical use; LICENSE.txt states
the code/documentation licences and the data restrictions.

Documentation corrected. All pre-revision model-card and worked-example files
in the repository are replaced by a single MODEL_CARD.md so that the deposited
performance values (AUC-ROC 0.8572, AUC-PR 0.5731, Brier 0.0652), the exact
thresholds and the 7-day KDIGO-derived primary outcome match the revised
manuscript. The repository must still be updated with the public repository bundle and the four
obsolete Word files deleted; UPLOAD_GUIDE.md gives the exact overwrite and
delete list.

Changes in the text: Footnote (Data Sharing Statement; code and model
availability paragraph), Methods ("Model specification, reproducibility and
reporting"), Supplementary Table S4; the bundle is submitted as Supplementary
Material. (see Page __, Line __).

===============================================================================
SELF-CHECK BEFORE SUBMISSION (author actions)
===============================================================================
  [ ] Repository root contains the public repository bundle, not the six pre-revision files.
  [ ] The four obsolete Word files listed in UPLOAD_GUIDE.md B2 are deleted.
  [ ] xgboost_model.rda on GitHub is the 48 KB / 29-column object; its
      SHA-256 matches SHA256SUMS.txt.
  [ ] `Rscript verify_release.R` passes from the downloaded bundle.
  [ ] `Rscript predict_new_patient.R` prints a probability and a stratum.
  [ ] The Shiny URL in the manuscript is
      https://dingliu.shinyapps.io/NRDS-aki-predictor/ .
  [ ] Final page/line references are inserted in the response letter.
  [ ] No patient-level CSV, .RData or deployment token is in the repository.


===============================================================================
ADDITIONAL CLARIFICATION - "number of trees" (TRIPOD+AI 15a-15b)
===============================================================================

The reviewer specifically asked for the number of trees, depth, learning rate,
subsample, colsample and seed. The complete table is in MODEL_CARD.md section
1 and TRANSPARENT_ACCESS.md section 4: binary:logistic; base_score 0.5;
scale_pos_weight 1; max_depth 3; eta 0.05; subsample 1; colsample_bytree 1;
min_child_weight 1; gamma 0; lambda 1; alpha 0 (all untuned xgboost 1.7.7.1
defaults); seeds 1234 / 100+i / 200+i / 2026; 22 predictors expanded to 29
design columns.

The Methods and Supplementary Table S4 report nrounds = 100, the MEDIAN of the
per-fold inner-CV selected values. Those per-fold models generated the pooled
out-of-fold predictions behind every performance estimate, calibration
statistic and both risk thresholds in the article. The single model released
for deployment was refit once on the full imputed cohort with nrounds = 200,
max_depth = 3 and eta = 0.05 (the `med` vector inside the released object),
which is why model.json contains 200 trees. The two values describe different
stages of the same pipeline, not a discrepancy in reported performance. The
proposed Footnote wording that states this explicitly is supplied in
code_availability_statement.md.

The live calculator URL in the revised manuscript is
https://dingliu.shinyapps.io/NRDS-aki-predictor/ .
