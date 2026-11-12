###############################################################
# revision_consolidate.R
# Run this AFTER closing Excel/WPS windows that may hold result files open.
# The main script always writes *_FINAL.csv copies that can never be locked;
# this helper copies them back onto the canonical filenames so the
# manuscript tables all point at one unambiguous, up-to-date file.
###############################################################
OUT <- "E:/NARDS/revision_output"
stems <- c("T3_imbalance_comparison", "T6_risk_stratification_decision")
for (s in stems) {
  final <- file.path(OUT, paste0(s, "_FINAL.csv"))
  dest <- file.path(OUT, paste0(s, ".csv"))
  if (!file.exists(final)) { cat("SKIP (missing):", final, "\n"); next }
  ok <- tryCatch(file.copy(final, dest, overwrite = TRUE), error = function(e) FALSE)
  cat(if (isTRUE(ok)) "OK: " else "LOCKED (close WPS and re-run): ", dest, "\n", sep = "")
}
cat("Consolidation finished.\n")
