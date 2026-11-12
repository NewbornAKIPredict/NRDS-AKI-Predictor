# Transparent access to the code and the trained model

**TP-2026-0897-CL** - *Translational Pediatrics*, major revision
Reviewer-facing response and technical disclosure - 2026-11-12
Public repository: https://github.com/NewbornAKIPredict/NRDS-AKI-Predictor
Live calculator: https://dingliu.shinyapps.io/NRDS-aki-predictor/

This document is the single, self-contained answer to the reviewer's
reproducibility requirements. Section 2 can be pasted into the response
letter; section 3 can be pasted into the manuscript Footnote.

---

## Study context

This release accompanies a prediction-model development study with internal
validation in 1,115 neonates with NRDS from MIMIC-III v1.4 (ICD-9 769), with
118 AKI events (10.6%). The primary endpoint came from
`mimiciii_derived.kdigo_stages_7day`. Pooled out-of-fold performance of the
revised XGBoost model was AUC-ROC 0.8572 (95% CI 0.8175-0.8941), AUC-PR
0.5731, Brier score 0.0652, calibration intercept 0.195 and slope 1.088. In
the held-out test set (n = 335) the three risk strata showed AKI rates of
2.3% / 11.0% / 59.4%. Every value matches the revised manuscript.

---

## 1. The comments being answered (verbatim)

> "The model is described through SHAP and summary metrics, but there is no
> full specification of XGBoost (number of trees, depth, learning rate,
> subsample, colsample, seed)."

> "No accessible code for the full pipeline is provided (although GitHub +
> Shiny are promised), nor version parameters or fold splits."

> "TRIPOD items 15a-15b are formally violated - the model is not clinically
> reproducible from the article alone."

> Recommended (desirable): "Transparent access to the code and the trained
> model."

---

## 2. Reply to the reviewers (response-letter text)

We accept these criticisms. In the original submission only a deployment
script and a promise of a repository were available. With the revision we now
release the complete executable pipeline, the exact software environment, the
fold construction, the full hyperparameter specification and **the trained
model itself**, both as Supplementary Material and in the public repository
https://github.com/NewbornAKIPredict/NRDS-AKI-Predictor. No login, no MIMIC-III credential and no compiled
machine-learning library are needed to score the released model.

**(a) Full pipeline code.** `revision_main_v1.R` performs the stratified nested
10-fold cross-validation with training-fold-only multiple imputation (MICE,
m = 5, maxit = 10; held-out folds m = 1), per-fold Boruta selection over the
48-variable candidate pool (ntree = 500, maxRuns = 20, TentativeRoughFix) and
inner 5-fold XGBoost tuning over the eight-point grid, then exports pooled
out-of-fold predictions and analyses R1-R13. `revision_tables_figures_v1.R`
regenerates Tables 2-6, Figures 2-9, the SNAP-II single-predictor benchmark,
the subgroup analyses, calibration/decision-curve outputs and the model
artefacts. The six pre-revision scripts are preserved as thin wrappers in
`legacy_wrappers/`, and `revision_legacy_bridge.R` / `revision_consolidate.R`
restore the canonical result files. The exact run order is in
`README_reproducibility.md`.

**(b) Fold splits, seeds and version parameters.** The stratified 10-fold split
and the fixed 7:3 held-out split are regenerated deterministically with seed
1234; fold-wise MICE uses seeds 100+i and 200+i; the 1,000-replicate bootstrap
uses seed 2026. No held-out data were used for imputation, selection or tuning.
The exact environment is recorded in `sessionInfo.rds` and `sessionInfo.txt`
(R 4.3.2, xgboost 1.7.7.1, all loaded packages). Per-fold selected
hyperparameters, Boruta confirmation frequencies and fold-wise stability are
supplied as aggregate CSVs in `results/`.

**(c) Complete model specification (TRIPOD+AI 15a-15b).** See the table in
section 4 below. In brief: `binary:logistic`, 200 boosting rounds in the
released deployment model, `max_depth = 3`, `eta = 0.05`, `base_score = 0.5`,
`scale_pos_weight = 1`; `subsample = 1`, `colsample_bytree = 1`,
`min_child_weight = 1`, `gamma = 0`, `lambda = 1`, `alpha = 0` and all other
settings at the xgboost 1.7.7.1 defaults, as visible in the training call in
`revision_tables_figures_v1.R`. The 22 Boruta-confirmed predictors expand to
29 design-matrix columns; `firstweight` and `min_weight` are continuous
kilogram values and gestational age follows the five Table 1 categories
verbatim. The exact out-of-fold cut-points are 0.0651 / 0.3008 (rounded to
0.065 / 0.301 in Table 6 and Figures 9-10).

**(d) The trained model is actually downloadable.** `model.json` is a
version-portable 200-tree JSON booster; `model_meta.rds` carries the 29-column
design template and feature dictionary; `xgboost_model.rda` is the equivalent
original R booster; `risk_thresholds.csv` carries the exact cut-points. All
four contain **no patient records**. An earlier local artefact that embedded
the 1,115 x 49 analytic data frame was deliberately excluded under the
PhysioNet MIMIC-III data use agreement.

**(e) Runnable verification without privileged access.** `Rscript
predict_new_patient.R` needs only base R and `jsonlite`, reads the four
released files and prints a probability plus its research stratum
(default case 0.0120, Low). `Rscript verify_release.R` re-checks the booster
structure, the 29-column design, the exact cut-points, all SHA-256 checksums,
the absence of patient-level objects and the absence of credentials.
`app.R` is the exact source of the live calculator at https://dingliu.shinyapps.io/NRDS-aki-predictor/.
Agreement with the native xgboost booster is within 1.45e-07 (float32
accumulation).

**(f) Integrity and access.** `SHA256SUMS.txt` gives a checksum for every
released file. The repository is public and requires no login; the Shiny
calculator is public. `MODEL_CARD.md` discloses the outcome definition, the
leakage-free pipeline, inputs and units, performance, limitations and the
explicit prohibition on clinical use. `LICENSE.txt` states the code and
documentation licences together with the data restrictions.

**(g) The released code matches the revised manuscript.** An audit of the
earlier deposit found that the two analysis scripts still carried the
pre-revision gestational-age dictionary (`<=28w ... >=37w`), an incorrect
claim that birth weight was an ordinal category code, and a final-refit
routine that could be silently overwritten by the per-fold median
`nrounds = 100`. Both scripts were synchronised on 2026-11-12 with
`20261112NARDSmanuscript5.docx`: `GA_LAB` now follows Table 1 verbatim
(0 = Others, 1 = <28, 2 = 29-32, 3 = 33-34, 4 = 35-36 weeks), `<32 weeks`
is codes 1+2 and `>=32 weeks` codes 3+4 with Others reported separately,
`firstweight` / `min_weight` are documented as continuous kilograms, the
primary endpoint is stated as `mimiciii_derived.kdigo_stages_7day`, the
200-tree deployment refit is separated from the reported per-fold median, and
the authoritative cut-points are written into the auto-generated Methods
text. All later correction and verification scripts are preserved in
`revision_patches/` with an explicit FINAL / SUPERSEDED status, and every
hard-coded path is relocatable through `NARDS_ROOT`. The nested-CV
computation, all seeds and the released model artefacts are unchanged, so
every published result is still reproducible.

**Changes in the text:** Footnote (Data Sharing Statement; code and model
availability paragraph), Methods ("Model specification, reproducibility and
reporting", MICE, Boruta and tuning paragraphs), Supplementary Table S4
(TRIPOD+AI items 15a-15b), and the response letter. (Page __, Line __.)

---

## 3. Data and Code Availability Statement (manuscript-ready)

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

The complete executable code, the trained model in both its native R and
version-portable JSON forms, the model card, the exact software environment
and a runnable single-patient example are supplied as Supplementary Material
and deposited in the public repository https://github.com/NewbornAKIPredict/NRDS-AKI-Predictor. The live Shiny
calculator built from the same four released files is available at https://dingliu.shinyapps.io/NRDS-aki-predictor/.
All revised analyses are reproducible from `revision_main_v1.R` and
`revision_tables_figures_v1.R`; the fold split is regenerated with seed 1234,
fold-wise imputation with seeds 100+i and 200+i and the bootstrap with seed
2026. Software versions are recorded in `sessionInfo.rds` /
`sessionInfo.txt` (R 4.3.2, xgboost 1.7.7.1) and file integrity in
`SHA256SUMS.txt`. `risk_thresholds.csv` stores the exact training-set
out-of-fold cut-points 0.0651 and 0.3008 (displayed as 0.065 and 0.301 in
Table 6 and Figures 9-10). `predict_new_patient.R` reproduces a single-patient
probability using only base R and `jsonlite`, without installing xgboost or
accessing MIMIC-III.

The primary AKI outcome was taken from the 7-day view of the official MIMIC-III
derived KDIGO staging concept (`mimiciii_derived.kdigo_stages_7day`), whose
baseline-creatinine and staging rules are reproduced in the Methods; the 48-h
view (`kdigo_stages_48hr`) was an alternative ascertainment window and did not
define the primary endpoint. Patient-level data cannot be redistributed under
the PhysioNet MIMIC-III data use agreement; the provided code reconstructs the
analytic cohort from an authorised local copy of MIMIC-III.

---

## 4. Full model specification (answers "no full specification of XGBoost")

| Item | Value | Where it is verifiable |
|---|---|---|
| Algorithm / objective | XGBoost gradient-boosted trees, `binary:logistic` | `model.json`, `revision_tables_figures_v1.R` |
| Boosting rounds - per-fold models | median selected by inner CV = 100 | Methods; `results/R12_methods_reporting.txt` |
| Boosting rounds - released model | 200 (single full-cohort refit) | `model.json` (200 trees), `med` in `model_meta.rds` |
| max_depth / eta | 3 / 0.05 | `med`, Methods, `MODEL_CARD.md` |
| base_score / scale_pos_weight | 0.5 / 1 | `model.json` (`learner_model_param`, `objective`) |
| subsample / colsample_bytree | 1 / 1 (xgboost 1.7.7.1 defaults; not tuned) | training call in `revision_tables_figures_v1.R` |
| min_child_weight / gamma / lambda / alpha | 1 / 0 / 1 / 0 (defaults; not tuned) | same training call |
| Booster / tree method | `gbtree`, default `auto` | `model.json` |
| Seeds | 1234 (folds and split), 100+i / 200+i (fold MICE), 2026 (bootstrap) | `README_reproducibility.md`, scripts |
| Tuning grid | 8 points: nrounds 100/200, max_depth 3/6, eta 0.05/0.10; inner 5-fold CV inside each training fold | `revision_main_v1.R`, Supplementary Table S4 |
| Features | 22 Boruta-confirmed predictors -> 29 model-matrix columns | `model_meta.rds`, `feature_info` |
| Input units / coding | firstweight, min_weight in kilograms; GA = `<28`, `29-32`, `33-34`, `35-36` weeks, `Others`; Weight_label 0-4 | `MODEL_CARD.md`, Table 1 |
| Output | P(AKI) in [0,1]; research strata `<0.0651`, `0.0651-0.3008`, `>=0.3008` | `app.R`, `risk_thresholds.csv` |
| Development software | R 4.3.2, xgboost 1.7.7.1 | `sessionInfo.rds` / `.txt` |
| Scoring requirement | base R + `jsonlite` (no xgboost, no MIMIC-III) | `predict_new_patient.R`, `app.R` |

### Why the manuscript says 100 trees and the released model has 200

`nrounds = 100` in the Methods and in Supplementary Table S4 is the **median
of the per-fold inner-CV selected values**. Those per-fold models produced the
pooled out-of-fold predictions from which **every** performance estimate,
calibration statistic and both risk thresholds were derived; the article's
results therefore belong to that stage. The single model released for
deployment was subsequently refit once on the full imputed cohort using the
`med` vector stored in the model object (`nrounds = 200`, `max_depth = 3`,
`eta = 0.05`), which is why `model.json` holds 200 trees. The two numbers
describe different stages, not a discrepancy in the reported performance.
This distinction is stated in `MODEL_CARD.md` section 1 and
`README_reproducibility.md`. If the Footnote sentence is intended to describe
the released object rather than the per-fold models, it should read
`nrounds = 200` or carry the same clarifying sentence; the proposed wording
is in `code_availability_statement.md`.

---

## 5. What is in the deposit, and which requirement it satisfies

| File(s) | Reviewer requirement answered |
|---|---|
| `revision_main_v1.R`, `revision_tables_figures_v1.R`, `revision_legacy_bridge.R`, `revision_consolidate.R`, `legacy_wrappers/` | Full pipeline code; TRIPOD+AI 15a-15b |
| `README_reproducibility.md`, `results/` | Fold splits, seeds, per-fold hyperparameters, selection stability, version parameters |
| `sessionInfo.rds`, `sessionInfo.txt` | Exact software version parameters |
| `model.json`, `model_meta.rds`, `xgboost_model.rda` | The trained model, in portable and native form |
| `risk_thresholds.csv` | Exact cut-points behind Table 6 / Figures 9-10 |
| `predict_new_patient.R`, `verify_release.R`, `SHA256SUMS.txt` | Runnable, independently verifiable access |
| `app.R`, `DEPLOYMENT_NOTE.md` | Live calculator built from the same public files |
| `MODEL_CARD.md`, `LICENSE.txt`, `.gitignore` | Full specification, limitations, data governance |
| `TRANSPARENCY_RESPONSE.md`, `code_availability_statement.md`, `UPLOAD_GUIDE.md`, `MANIFEST.txt` | Response-letter text, manuscript text, upload instructions |
| `revision_patches/` | Audit trail for the post-11-05 corrections (GA coding, CIs, Supplementary Figure S3, DeLong test, cut-points, worked example); each script marked FINAL or SUPERSEDED |

**Explicitly excluded (MIMIC-III DUA):** `NRDSNOMICE.csv`, any `.RData`
containing patient rows, `NestedCV_All_Predictions.csv`, per-patient prediction
files, the local `model_transparency/NARDS_AKI_trained_model.rda` (embeds the
1,115 x 49 analytic data frame) and any shinyapps.io token/secret or
`rsconnect/` deployment record.

---

## 6. Verification record (performed on this release)

- `verify_release.R`: **26/26 checks pass, ALL CHECKS PASSED** - 200 trees,
  `binary:logistic`, 29 features, 22 predictors, kilogram units, exact
  cut-points, no xgboost runtime dependency in `app.R`, no patient-level
  objects, no live credentials, all SHA-256 checksums matching.
- `predict_new_patient.R`: default case `p = 0.0120 (1.20%)`, stratum Low;
  native xgboost cross-check difference 6.19e-09 under xgboost 1.7.7.1.
- Pure-R scorer vs native booster on 30 reference designs: maximum absolute
  difference 1.45e-07.
- Real Shiny sessions: 1.20% Low / 10.36% Moderate / 33.88% High; local
  `shiny::runApp()` returned HTTP 200; xgboost not loaded at runtime.
- All 23 R scripts parse (8 ASCII-named released scripts, the 6 original
  Chinese-named wrappers checked through ASCII copies, and the 9 scripts
  in `revision_patches/`); `SHA256SUMS.txt` covers every released file.

---

## 7. Limits of this disclosure

The released model is a **development-stage research tool with internal
validation only**. No external, temporal or geographical validation has been
performed. The primary outcome uses general KDIGO thresholds without
gestational-age or birth-weight adjustment; neonate-specific validity has not
been demonstrated. Nothing here is a clinical risk score, and the three-tier
labels and the `Clinical_Intervention` column in `results/` are descriptive
research labels, not treatment recommendations.

---

## 8. For the authors only - NOT part of the submission to reviewers

1. Push this directory to https://github.com/NewbornAKIPredict/NRDS-AKI-Predictor and delete the four
   superseded pre-revision Word documents listed in `UPLOAD_GUIDE.md` B2.
2. Replace the second Footnote paragraph with section 3 above, and insert the
   final page/line references in the response letter and TRIPOD+AI checklist.
3. Decide whether the Footnote `nrounds = 100` sentence should describe the
   per-fold models (add the clarifying sentence) or the released model
   (change to 200). Do not alter the Methods "median across folds" wording.
4. Confirm https://dingliu.shinyapps.io/NRDS-aki-predictor/ is publicly reachable; rotate any previously
   exposed shinyapps.io token. `deploy.R` contains live credentials and must
   never be committed (it is excluded by `.gitignore`).
5. If a Zenodo DOI is created, add it to the Footnote, the availability
   statement and the response letter.
