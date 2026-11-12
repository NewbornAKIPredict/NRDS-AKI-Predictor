UPLOAD GUIDE - PUBLIC GITHUB REPOSITORY
TP-2026-0897-CL - "Transparent access to the code and the trained model"
Release 2026-11-12

Repository: https://github.com/NewbornAKIPredict/NRDS-AKI-Predictor
This directory IS the repository root. Extract
TP-2026-0897-CL_GitHub_Upload_FINAL.zip flat into a clone of the repository,
commit and push. Do not create an extra nested folder.

=====================================================================
SECTION A - ONE-TIME CLEANUP (do this first)
=====================================================================
DELETE these four pre-revision files from the repository root. They contain
obsolete performance (AUC 0.8534, AUC-PR 0.5821, Brier 0.0646), obsolete
thresholds (0.168 / 0.252) and a pipeline order implying imputation and
selection before cross-validation:

  NRDS Model Card for Neonatal AKI Prediction Model.docx
  NRDS Worked Example.docx
  NRDS-AKI Model Release Artifacts.doc
  README.md.docx

Single replacement: MODEL_CARD.md and README.md. Do NOT leave the old files
alongside the new ones - two model cards with different numbers in one
repository is worse than having none.

OVERWRITE the old 141-byte README.md, the legacy 16 KB xgboost_model.rda
(20 features / 15 trees), the old app.R and the old risk_thresholds.csv.
The correct xgboost_model.rda is 48,472 bytes / 29 design columns /
22 predictors / 200 trees.

=====================================================================
SECTION B - UPLOAD
=====================================================================
Option 1 (recommended, preserves history):

  git clone https://github.com/NewbornAKIPredict/NRDS-AKI-Predictor.git
  cd NRDS-AKI-Predictor
  # delete the four files listed in Section A
  # extract the ZIP flat into this directory (overwrite when prompted)
  git add -A
  git commit -m "Release full pipeline, trained model and model card for TP-2026-0897-CL revision"
  git push

Option 2 (GitHub web UI): open the repository, use "Add file > Upload files",
select ALL files in this directory including .gitignore, then commit. Note
that the web UI cannot create the results/ and legacy_wrappers/ folders by
dragging a folder on every browser - verify both folders appear afterwards.
Option 1 is safer.

Files that must be present at the repository root after upload:
  .gitignore, README.md, TRANSPARENT_ACCESS.md,
  TRANSPARENCY_RESPONSE.md, code_availability_statement.md, MODEL_CARD.md,
  README_reproducibility.md, DEPLOYMENT_NOTE.md, UPLOAD_GUIDE.md,
  MANIFEST.txt, LICENSE.txt, SHA256SUMS.txt,
  sessionInfo.rds, sessionInfo.txt,
  model.json, model_meta.rds, xgboost_model.rda, risk_thresholds.csv,
  app.R, predict_new_patient.R, prepare_deploy.R, verify_release.R,
  revision_main_v1.R, revision_tables_figures_v1.R,
  revision_legacy_bridge.R, revision_consolidate.R,
  legacy_wrappers/ (6 scripts), results/ (aggregate tables + README.md),
  revision_patches/ (9 correction scripts + README.md)

=====================================================================
SECTION C - NEVER UPLOAD (enforced by .gitignore)
=====================================================================
  NRDSNOMICE.csv, NARDSImputed_data.*, NRDSMICE.sav, any .RData
  NestedCV_All_Predictions.csv and ANY per-patient prediction file
  model_transparency/NARDS_AKI_trained_model.rda (embeds 1,115 x 49 rows)
  deploy.R (contains a live shinyapps.io token and secret)
  rsconnect/ and app/rsconnect/ deployment records, *.dcf
  Any file with subject_id / hadm_id / patient-level rows

results/ contains aggregate tables only and is safe to publish.
risk_thresholds.csv contains two cut-points and is safe to publish.
If a deployment token has ever been exposed, rotate it on shinyapps.io.

=====================================================================
SECTION D - POST-UPLOAD SELF-CHECK
=====================================================================
  [ ] Repository is public and opens without a login.
  [ ] README.md is the GitHub landing page and links TRANSPARENT_ACCESS.md.
  [ ] The four obsolete Word files are gone.
  [ ] xgboost_model.rda is 48,472 bytes; model.json has 200 trees.
  [ ] `Rscript verify_release.R` -> ALL CHECKS PASSED on a fresh clone.
  [ ] `Rscript predict_new_patient.R` -> p = 0.0120, Low.
  [ ] `git ls-files | grep -Ei "NRDSNOMICE|deploy.R|rsconnect"` returns nothing.
  [ ] The Footnote, availability statement, Reply 11 and Reply 17 cite the
      same repository and https://dingliu.shinyapps.io/NRDS-aki-predictor/.
  [ ] SHA256SUMS.txt matches the committed files.

=====================================================================
SECTION E - JOURNAL SIDE (separate from GitHub)
=====================================================================
Upload TP-2026-0897-CL_GitHub_Upload_FINAL.zip under "Supplementary Material
/ Code and Model" and the reviewer-facing Word document
TP-2026-0897-CL_Transparent_Access_Reviewer_FINAL.docx. If an older v2/v3/v4
archive is already in the system, REPLACE it - do not upload two versions.
Also attach the signed Data-Sharing-Statement form and the TRIPOD+AI
checklist (Supplementary Table S4).
