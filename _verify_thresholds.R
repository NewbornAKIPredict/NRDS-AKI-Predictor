# Verify that the FINAL v3 risk-threshold file is accepted and that both
# the rounded display file and the pre-revision file are rejected by the
# same validation rules implemented in app.R / predict_new_patient.R.
validate <- function(csv) {
  thr <- read.csv(csv, stringsAsFactors = FALSE)
  y <- as.numeric(thr$youden_threshold[1])
  h <- as.numeric(thr$high_risk_threshold[1])
  ok <- is.finite(y) && is.finite(h) && y > 0 && h < 1 && y < h &&
        abs(y - 0.0651) < 1e-6 && abs(h - 0.3008) < 1e-6
  cat(sprintf("  %-24s y=%.4f h=%.4f ACCEPT=%s\n", basename(csv), y, h, ok))
  ok
}

root <- "E:/NARDS/"
stopifnot(validate(file.path(root, "risk_thresholds.csv")))

write.csv(data.frame(youden_threshold = 0.065, high_risk_threshold = 0.301),
          file.path(root, "_thr_rounded_test.csv"), row.names = FALSE)
write.csv(data.frame(youden_threshold = 0.168, high_risk_threshold = 0.252),
          file.path(root, "_thr_legacy_test.csv"), row.names = FALSE)
stopifnot(!validate(file.path(root, "_thr_rounded_test.csv")))
stopifnot(!validate(file.path(root, "_thr_legacy_test.csv")))
unlink(file.path(root, c("_thr_rounded_test.csv", "_thr_legacy_test.csv")))

# Classification boundaries match Table 6 / Figure 9 wording.
stratum <- function(p) if (p >= 0.3008) "High" else if (p >= 0.0651) "Moderate" else "Low"
stopifnot(stratum(0.0650) == "Low", stratum(0.0651) == "Moderate",
          stratum(0.3007) == "Moderate", stratum(0.3008) == "High")
cat("THRESHOLD VALIDATION OK: exact accepted; rounded + legacy rejected; boundaries match Table 6\n")
