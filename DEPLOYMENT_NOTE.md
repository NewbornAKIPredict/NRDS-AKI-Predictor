DEPLOYMENT NOTE - public Shiny calculator
TP-2026-0897-CL (FINAL v4, 2026-11-12)

Live application: https://dingliu.shinyapps.io/NRDS-aki-predictor/
Application name: NRDS-aki-predictor (shinyapps.io appId 16350425)

WHY THIS IS PART OF THE TRANSPARENCY BUNDLE
------------------------------------------
The reviewer asked for transparent access to the code AND the trained model.
A public repository alone is not enough if a reviewer cannot execute the
model: the original R booster was written by xgboost 1.7.7.1 and is rejected
by xgboost 2.x / 3.x ("'xgb.Booster' object is corrupted or is from an
incompatible XGBoost version"), while shinyapps.io installs the current CRAN
release. Loading `xgboost` at start-up also requires a C++ source build on the
Linux worker, which is a common cause of "The application failed to start /
exit status 1".

The released calculator therefore scores the model with a PURE-R TREE WALKER.
The four published files are:

  app.R                 revised calculator; reads the exact cut-points;
                        aborts on stale or rounded thresholds
  model.json            version-portable booster, 200 trees, 29 features
  model_meta.rds        29 design columns + 22-predictor dictionary + medians
                        + tuning values (no patient rows)
  risk_thresholds.csv   0.0651 / 0.3008 (NOT the rounded display labels)

Only `shiny` and `jsonlite` are required at runtime; `jsonlite` is already a
shiny dependency, so no compiled package is installed for scoring.

HOW THE PORTABLE MODEL WAS PRODUCED
-----------------------------------
prepare_deploy.R loads the original xgboost_model.rda under the modelling
environment (R 4.3.2 + xgboost 1.7.7.1), saves the booster as JSON, writes
model_meta.rds, copies risk_thresholds.csv, and verifies on five reference
patients that the JSON booster gives the same predictions and the same three
risk strata. Under a newer xgboost it runs in VERIFY-ONLY mode and checks the
already-shipped model.json. The conversion is reproducible; the shipped files
are already converted.

ACCURACY
--------
The pure-R scorer was compared with the native xgboost booster on 30 reference
designs (5 clinical cases + 25 randomised designs): maximum absolute
difference 1.45e-07, entirely attributable to float32 accumulation. In real
Shiny sessions the calculator returns 1.20% (Low), 10.36% (Moderate) and
33.88% (High) for the default, SNAP-II = 30 and extreme inputs respectively,
under both xgboost 1.7.7.1 and 3.2.1.1 library paths - with xgboost not loaded
at all. Application start-up was confirmed by a local HTTP 200 response with
all 22 inputs rendered.

CREDENTIALS
-----------
Publishing uses rsconnect::setAccountInfo() with an account/token/secret held
in environment variables. NO credential is included in this bundle or in the
public repository, and none must ever be committed. The working deployment
script stays local (outside the published app/ directory) precisely because it
contains a live token and secret. If a token has been exposed anywhere, rotate
it on shinyapps.io.

DUA
---
No patient-level data are uploaded. app.R, model.json, model_meta.rds and
risk_thresholds.csv contain only model structure, a feature dictionary and two
cut-points. The rsconnect deployment-record directory generated locally by
rsconnect is not part of the release.
