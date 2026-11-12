# Model Card - NRDS-AKI XGBoost Predictor (FINAL v4)

Manuscript: TP-2026-0897-CL (*Translational Pediatrics*, major revision)
Model version: FINAL v4 / resubmission build, 2026-11-12
Repository: https://github.com/NewbornAKIPredict/NRDS-AKI-Predictor
Live calculator: https://dingliu.shinyapps.io/NRDS-aki-predictor/

**This card supersedes every earlier model card deposited in the repository**,
including `NRDS Model Card for Neonatal AKI Prediction Model.docx`, which
reported pre-revision performance (AUC 0.8534, AUC-PR 0.5821, Brier 0.0646),
pre-revision thresholds (0.168 / 0.252) and a pipeline order implying
imputation and selection before cross-validation. Those numbers and that
ordering are obsolete; the older files must be deleted (UPLOAD_GUIDE.md B2).
Every number below is the FINAL value in the revised manuscript.

---

## 1. Model details

| Item | Value |
|---|---|
| Name | NRDS-AKI XGBoost Predictor |
| Type | Gradient-boosted decision trees (XGBoost, `binary:logistic`) |
| Task | Estimate AKI probability in neonates with NRDS |
| Development software | R 4.3.2, xgboost 1.7.7.1 (exact versions: `sessionInfo.rds` / `.txt`) |
| Runtime for the released artefacts | base R + `jsonlite` only; **no xgboost needed** |
| Released booster | `model.json`: 200 trees, 29 input columns, `base_score` 0.5 |
| Equivalent R object | `xgboost_model.rda` (48,472 bytes): booster + `X_template` + `selected_feat` + `feature_info` + `med` |
| Inner-CV tuning grid | nrounds 100/200, max_depth 3/6, eta 0.05/0.10 (8 points), 5-fold inner CV inside each training fold |
| **Fold-wise MEDIAN of tuned values** (reported in Methods) | nrounds = 100, max_depth = 3, eta = 0.05, seed = 1234 |
| **Final single full-cohort refit** (the released object) | nrounds = 200, max_depth = 3, eta = 0.05 (`med` inside the model; 200 trees in `model.json`) |
| Random seeds | 1234 (folds / split), 100+i and 200+i (fold-wise MICE), 2026 (bootstrap) |
| Licence | `LICENSE.txt` (MIT code / CC BY 4.0 docs + model), research use only |

> **Hyperparameter wording matters.** The manuscript's Methods report the
> median of the per-fold inner-CV selected values (nrounds = 100); those
> per-fold models produced the pooled out-of-fold predictions from which ALL
> performance metrics, calibration and both thresholds were derived. The
> single model released here for deployment was then refit once on the full
> imputed cohort with the `med` vector stored in the model object
> (nrounds = 200, max_depth = 3, eta = 0.05), which is why `model.json`
> contains 200 trees. The two numbers describe different stages, not a
> discrepancy in the reported performance. `predict_new_patient.R` and
> `app.R` score the released 200-tree model. See section 12.

## 2. Intended use and explicit non-uses

**Intended use: research reproducibility only.** Released so reviewers and
readers can reproduce the analyses, inspect the predictor list, and rerun the
single-patient example.

This is a **prediction-model DEVELOPMENT study with internal validation only**
(TRIPOD+AI: development + internal validation). No external, temporal or
geographical validation has been performed. The model must **not** be used for:

- clinical diagnosis, triage, monitoring decisions or treatment selection;
- guiding NSAID, diuretic, PDA or ventilation management;
- bedside deployment outside a research protocol with prospective validation;
- any claim that the output is a validated clinical risk score.

The `Clinical_Intervention` column in
`results/T6_risk_stratification_decision_FINAL_104917.csv` is a *research
label* retained from the original stratification exercise. It is descriptive,
not a clinical recommendation. The three-tier labels here are likewise
descriptive.

## 3. Outcome definition (read before interpreting any output)

The primary outcome (118 AKI events among 1,115 infants, 10.6%) came from the
**7-day view of the official MIMIC-III derived KDIGO staging concept**
(`mimiciii_derived.kdigo_stages_7day`, MIT-LCP mimic-code), built on the
parent concept `mimiciii_derived.kdigo_stages`. It applies **general (adult)
KDIGO** thresholds:

- baseline serum creatinine = **lowest value in the preceding 7 days**;
- stage 1: >=0.3 mg/dL or 1.5-1.9x baseline; stage 2: 2.0-2.9x;
  stage 3: 3.0x baseline, or serum creatinine >=4.0 mg/dL, or renal
  replacement therapy;
- urine-output windows 6 h / 12 h / 24 h; the 7-day view collapses all
  stages recorded within the first 7 days into one worst stage.

`kdigo_stages_48hr` was extracted as an **alternative ascertainment window
only** and did not define the primary endpoint. Both views inherit identical
thresholds and baseline rules and differ only in the ICU-admission window.

This definition is **neither paediatric RIFLE nor neonatal-modified KDIGO**
and contains **no adjustment for gestational age or birth weight**. We do not
claim these general thresholds have been validated in neonates: neonatal serum
creatinine partly reflects maternal creatinine and declines physiologically
after birth, and non-oliguric AKI is common, so definition-dependent
misclassification is likely. External validation must re-adjudicate AKI with a
contemporary neonatal-modified definition.

## 4. Development data

| Item | Value |
|---|---|
| Source | MIMIC-III v1.4 (Beth Israel Deaconess Medical Center, 2001-2012), single centre |
| Cohort | First NICU admission with NRDS (ICD-9 code 769) |
| N | 1,115 neonates; 118 AKI (10.6%), 997 non-AKI |
| Candidate pool | 48 variables (Methods and Supplementary Table S4) |
| Access | PhysioNet credentialing (Certification No. 55551396) + CITI training; MIMIC-III DUA |

**No patient-level data are distributed with this model.** The local artefact
`model_transparency/NARDS_AKI_trained_model.rda` generated by
`revision_tables_figures_v1.R` embeds the 1,115 x 49 analytic data frame
(`d_full`) and must **never** be uploaded. The released `xgboost_model.rda`
and `model.json` contain only the booster and metadata; their boosters are
byte-identical to that local artefact's booster.

## 5. Development pipeline (leakage-free ordering)

1. Nested 10-fold cross-validation with a fixed 7:3 held-out split for the
   risk-stratification evaluation.
2. **Within each training fold only**: MICE (`m = 5`, `maxit = 10`), Boruta
   selection and inner 5-fold XGBoost tuning. Held-out folds are imputed
   separately (`m = 1`).
3. Pooled out-of-fold (OOF) predictions across all folds for every performance
   metric, calibration analysis, DeLong tests and decision-curve analysis.
4. 1,000-replicate bootstrap (seed 2026) for 95% confidence intervals.
5. Final single full-cohort refit with `med` (nrounds 200, max_depth 3,
   eta 0.05), after one MICE imputation of the full cohort; released as
   `xgboost_model.rda`, converted to `model.json` for portable scoring.
6. SHAP / TreeSHAP interpretation and three-tier risk stratification.

Imputation, selection and tuning were **never** applied to the full cohort
before cross-validation. Any earlier "MICE -> Boruta -> XGBoost -> 10-fold CV"
description is superseded.

## 6. Inputs

`selected_feat` (22 predictors, in order):
HEMATOCRIT_max, HEMOGLOBIN_min, HEMOGLOBIN_max, PLATELET_min, PLATELET_max,
WBC_min, WBC_max, SNAP_II, LOS, FirstUrineOutput, firstweight, min_weight,
Anemia_of_prematurity, Patent_ductus_arteriosus,
Other_transitory_neonatal_electrolyte_disturbances, NSAIDs,
vasoentdurationssingle_flag, ventdurationssingle_flag, GA, diuretics_flag,
methylxanthine_flag, Weight_label.

`X_template` holds the **29** model-matrix columns produced by
`model.matrix(~ . - 1, ...)` after expansion of the 0/1 and 0-4 factors.
A new patient must be aligned to this exact template (see
`predict_new_patient.R` and `build_design()` in `app.R`). The JSON booster
carries no feature names, so scoring is POSITIONAL: never reorder
`X_template`.

Coding dictionaries:

- **Gestational age follows Table 1 of the manuscript verbatim**: `< 28`,
  `29-32`, `33-34`, `35-36 weeks` and `Others`. In the source extract these
  are stored as numeric codes 0-4 (`GA1` ... `GA4` after expansion). The
  manuscript does NOT treat them as an ordinal gestational-age rank and does
  not assign `Others` a rank. The `<32 weeks` stratum combines `< 28` +
  `29-32 weeks`; the `>=32 weeks` stratum combines `33-34` + `35-36 weeks`;
  `Others` is reported separately and merged into neither.
- `Weight_label`: 0 = unknown, 1 = ELBW <1000 g, 2 = VLBW 1000-1499 g,
  3 = 1500-2499 g, 4 = >=2500 g.
- **`firstweight` and `min_weight` are continuous weights in KILOGRAMS**, not
  grams and not category codes. In the analytic extract their medians are
  1.505 kg and 1.380 kg (defaults 1.5 / 1.38 in `feature_info`). The Shiny UI
  accepts grams and divides by 1000 before prediction; `Weight_label` is a
  separate categorical field. Earlier documentation that called these two
  fields "ordinal category codes" was wrong and is corrected here.
- `FirstUrineOutput` is first-day urine output in mL; laboratory variables use
  the raw units of the extract (see `feature_info` defaults).

## 7. Output and risk strata

The model outputs a probability in [0, 1]. Thresholds were derived
**exclusively from training-set OOF predictions** and applied unchanged to the
held-out test set (n = 335). The ranges below are the ROUNDED labels printed
in Table 6, Figures 9-10; the exact cut-points are 0.0651 and 0.3008:

| Stratum | Probability (exact) | Display | Held-out n | Observed AKI rate |
|---|---|---|---|---|
| Low | < 0.0651 | < 0.065 | 221 | 2.3% (5/221) |
| Moderate | 0.0651 - 0.3008 | 0.065 - 0.301 | 82 | 11.0% (9/82) |
| High | >= 0.3008 | >= 0.301 | 32 | 59.4% (19/32) |

`risk_thresholds.csv` stores the exact cut-points plus separate `*_display`
columns. `app.R` and `predict_new_patient.R` classify with the exact values and
**abort on stale pairs** (0.214 / 0.67, 0.168 / 0.252) and even on the
rounded 0.065 / 0.301 pair. Cochran-Armitage p for trend = 1.47x10-19. The
high-risk stratum contains only 32 infants, so its estimate is imprecise.

## 8. Performance (pooled OOF; internal validation only)

| Metric | XGBoost (final) | 95% CI |
|---|---|---|
| AUC-ROC | 0.8572 | 0.8175 - 0.8941 |
| AUC-PR | 0.5731 | 0.4796 - 0.6568 |
| Brier score | 0.0652 | 0.0546 - 0.0762 |
| Calibration intercept / slope | 0.195 / 1.088 | - |
| Sensitivity / specificity | 0.3559 / 0.9870 | - |

Comparators: random forest AUC-ROC 0.8523 (0.8164-0.8875), DeLong p = 0.716;
SNAP-II as sole predictor in a logistic model refit within each training fold,
AUC-ROC 0.7210 (0.6798-0.7625), AUC-PR 0.2068, Brier 0.0916 (DeLong
p = 1.55x10-10 versus the full model). Decile calibration, Brier and
decision-curve analysis use OOF predictions, not the training fit.

SHAP / TreeSHAP top five by mean absolute SHAP value (`results/`, Figure 5):
SNAP-II 0.878, NSAID exposure 0.258, first-day urine output 0.209, first
weight 0.198, minimum postnatal weight 0.191. SHAP values are associative,
not causal.

Subgroup performance (Table 1 GA labels): `<32 weeks` 0.8381
(0.7871-0.8855) versus `>=32 weeks` 0.8838 (0.8067-0.9506), p = 0.315;
without PDA 0.8803 versus with PDA 0.7390 (p = 0.0048); without NSAID
exposure 0.8799 versus with NSAID exposure 0.6164 (p = 2.3x10-5). Performance
is attenuated with PDA and NSAID exposure, a stated limitation.

## 9. Limitations

- Development only; **no external, temporal or geographical validation**.
- Riley criteria indicate 5,295 patients / 561 events would be required for de
  novo development with shrinkage 0.90; only 1,115 / 118 events were available
  (~2.5 events per candidate predictor), so estimates are subject to optimism.
- Definition-dependent outcome misclassification (general adult KDIGO in
  neonates; section 3). Stratified and birth-weight-adjusted analyses did not
  suggest maturity-related misclassification drives the main findings, but it
  cannot be excluded.
- MIMIC-III data were collected 2001-2012 at a single centre.
- Missing laboratory data may be informative / missing not at random.
- The high-risk stratum contained only 32 infants in the held-out set.
- SHAP attributions are not causal; interaction readings are exploratory.

## 10. Reproduction

`Rscript predict_new_patient.R` needs only base R + `jsonlite`.
`Rscript verify_release.R` checks the model, cut-points, checksums and that no
patient-level objects are present. Full pipeline run order, fold splits,
seeds and portability notes are in `README_reproducibility.md`. Exact
environment: `sessionInfo.rds` / `sessionInfo.txt`. Integrity: `SHA256SUMS.txt`.

The pure-R scorer in `app.R` / `predict_new_patient.R` was verified against
the native xgboost booster on 30 reference designs (5 clinical cases + 25
randomised): max absolute difference 1.45e-07, attributable to float32
accumulation. The deployed calculator therefore returns the same probability
as the original model while requiring no compiled dependencies.

## 11. Ethics and data governance

MIMIC-III v1.4 is available from PhysioNet after the DUA and CITI training
(https://physionet.org/content/mimiciii/, doi:10.13026/C2XW26). Patient-level
data, the derived analytic cohort and per-patient OOF prediction files are
**not redistributed**. The supplied code reconstructs the cohort from an
authorised local copy. The derived data dictionary, code, trained model and
this card are available from the corresponding author on reasonable request,
subject to the DUA. No deployment token or credential is part of this bundle.

## 12. Version history

| Version | Date | Change |
|---|---|---|
| v1 / repository deposit | earlier | Pre-revision model card with superseded performance and thresholds; must be deleted |
| v2 | 2026-11-05 | Table 1 GA wording, curated aggregate results |
| v3 / FINAL | 2026-11-11 | 7-day primary outcome confirmed; model card, licence, upload guide and checksums added; patient-bearing artefact removed |
| **v4 / FINAL (this file)** | **2026-11-12** | Replaced the WRONG 16 KB legacy 20-feature `xgboost_model.rda` with the correct 48 KB / 29-column model; added the version-portable `model.json` + `model_meta.rds`; removed the `xgboost` dependency from the shipped `app.R` (pure-R tree walker); corrected `firstweight` / `min_weight` from "category codes" to kilograms; clarified fold-wise median (nrounds 100) versus final refit (200 trees); updated the live calculator URL; rewrote the one-patient example to run without xgboost; added `verify_release.R` and `DEPLOYMENT_NOTE.md` |

## 13. Author actions still required

1. Replace the Shiny URL in the manuscript (Results and Footnote) with
   https://dingliu.shinyapps.io/NRDS-aki-predictor/ .
2. Confirm that the Footnote's "hyperparameters (nrounds = 100 ...)" is read
   as the fold-wise median; if it is meant to describe the released object,
   change it to nrounds = 200 or add the clarifying sentence in section 1.
3. Overwrite the public repository with this bundle and delete the four
   pre-revision Word files (UPLOAD_GUIDE.md B2).
4. Insert final page/line references in the response letter.
