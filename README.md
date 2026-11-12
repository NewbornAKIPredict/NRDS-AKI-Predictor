# Revision patches - post-11-05 WorkBuddy corrections

**TP-2026-0897-CL** - reproducibility trail, 2026-11-12

## Why this folder exists

The two main analysis scripts were written on 4-5 November. Between 5 and 11
November WorkBuddy produced a series of short correction and verification
scripts while the manuscript was revised (`20261112NARDSmanuscript5.docx`;
Table 1 gestational-age categories, Wilson/Clopper-Pearson CIs, Supplementary
Figure S3, the <32 vs >=32 weeks DeLong test, the exact risk cut-points and
the single-patient example). Those later changes were **not** written back into
the two released main scripts, which is why the earlier GitHub ZIP contained
stale GA coding and stale unit descriptions.

On 2026-11-12 the released `revision_main_v1.R` and
`revision_tables_figures_v1.R` were synchronised with the manuscript and with
the corrections below. These scripts are kept here so that a reviewer can
inspect exactly how each final number was obtained and re-run each check.

## Status of each script

| Script | Date | Status | What it establishes |
|---|---|---|---|
| `_ga_check.R` | 05 Nov 16:59 | FINAL (labels) | Table 1 five-stratum counts, Wilson and exact CIs, Fisher / chi-square / trend tests (283 / 405 / 200 / 92 / 135; 118 events). Its last label reads `>=37`; the manuscript calls that stratum **Others** - see `results/GA_Table1_authoritative.csv`. |
| `_ci_check.R` | 05 Nov 17:07 | FINAL | Wilson vs Clopper-Pearson exact 95% CIs for the GA, Table 12, Table 13 and birth-weight strata. |
| `_ga_subgroup_correct.R` | 05 Nov 17:10 | **FINAL - authoritative GA coding** | Verifies `0 = Others`, `1 = <28`, `2 = 29-32`, `3 = 33-34`, `4 = 35-36` weeks and recomputes the five GA subgroup AUCs; source of `results/subgroup_analyses_FINAL.csv`. |
| `_ga_subgroup_recalc.R` | 05 Nov 17:09 | **SUPERSEDED - do not use** | Intermediate version that put `Others` (code 0) into the `>=32 weeks` stratum. Superseded by `_ga_subgroup_correct.R` and `_delong_check.R`. Kept only to document the correction. |
| `_delong_check.R` | 05 Nov 18:04 | FINAL | `<32 weeks = codes 1+2` vs `>=32 weeks = codes 3+4`, Others excluded; AUC 0.8381 vs 0.8838, unpaired DeLong p = 0.315. |
| `_make_s3_corrected.R` | 05 Nov 17:31 | FINAL | Rebuilds Supplementary Figure S3 with the five Table 1 GA categories instead of the old four-level GA coding. |
| `_make_supp_figures.R` | 05 Nov 11:55 | FINAL | Base-R generation of Supplementary Figures S2 (Boruta fold stability) and S3. |
| `_verify_thresholds.R` | 11 Nov 19:25 | FINAL | Accepts only `0.0651 / 0.3008`, rejects the rounded display pair `0.065 / 0.301` and the pre-revision pair `0.168 / 0.252`; checks stratum boundaries. |
| `_verify_predict_example.R` | 11 Nov 19:02 | FINAL | Checks that every column assigned by the worked example exists in the released 29-column `X_template`. |

## What was synchronised into the main scripts on 2026-11-12

1. `GA_LAB` now follows Table 1 verbatim, with `GA_LEVELS` (display order) and
   `GA_ORDER` (`1,2,3,4,0`); the old `<=28w ... >=37w` dictionary is gone.
2. `<32 weeks = codes 1+2`, `>=32 weeks = codes 3+4`, `Others` (0) reported
   separately and excluded from the dichotomy, in both main scripts.
3. `firstweight` and `min_weight` are documented as **continuous kilogram**
   values; the obsolete "ordinal category codes / not gram values" text and
   the Shiny "converts grams to codes" claim were removed.
4. The primary endpoint is documented as `mimiciii_derived.kdigo_stages_7day`
   (118 events); `kdigo_stages_48hr` is an alternative window only.
5. `report_med` (per-fold median `nrounds = 100`, Methods / Supplementary
   Table S4) is separated from the **single deployment refit**
   (`nrounds = 200`, the released 200-tree `model.json`). The old code let the
   R12 log overwrite the final refit with 100 trees.
6. R12 now states the authoritative cut-points `0.0651 / 0.3008` and treats
   the run's own diagnostic thresholds as non-authoritative.
7. `NARDS_ROOT` (environment variable, default `E:/NARDS`) plus `pE()` make
   every hard-coded path relocatable without editing the scripts.
8. The auto-generated local README / worked example are now written as
   `README_reproducibility_LOCAL.md` and `predict_example_LOCAL.R`, so running
   the pipeline can no longer overwrite the released
   `README_reproducibility.md` and `predict_new_patient.R`.
9. A PhysioNet DUA warning marks the local artefact that embeds `d_full`
   (1,115 x 49 patient rows) as NOT publishable.

## Running these scripts

They are **verification / regeneration helpers**, not part of the required run
order. The required order is in `README_reproducibility.md`:

```
Rscript revision_main_v1.R
Rscript revision_tables_figures_v1.R
Rscript predict_new_patient.R
Rscript verify_release.R
```

Most patch scripts read `NestedCV_All_Predictions.csv` or
`revision_output/subgroup_GA_corrected.csv`, i.e. files derived from the
authorised MIMIC-III cohort. Those data are **not** in this public repository
(PhysioNet MIMIC-III data use agreement). Set `NARDS_ROOT` to your own working
directory. `_verify_thresholds.R` and `_verify_predict_example.R` can be run
against the released artefacts without patient-level data.

## Historical scripts deliberately NOT included

`revision_patch.R` (debug-mode output recovery, still carries the obsolete
GA coding and the wrong weight-unit note), `TP2026-0897_revision_analyses.R`
(first-round supplementary analyses), and the `chk_*.R` smoke-test probes are
development-time artefacts. They are superseded by the two synchronised main
scripts and by the aggregate tables in `results/`; including them would give a
reviewer several contradictory ways to reproduce the same number.
