e <- new.env()
load('E:/NARDS/submission_stage/TP-2026-0897-CL_Revision_Submission_Package/05_Code_and_Model/xgboost_model.rda', envir = e)
p <- 'E:/NARDS/submission_stage/TP-2026-0897-CL_Revision_Submission_Package/05_Code_and_Model/predict_new_patient.R'
txt <- paste(readLines(p, warn = FALSE), collapse = '\n')
pat <- "X_new\\[1, '([^']+)'\\]"
hits <- regmatches(txt, gregexpr(pat, txt))[[1]]
cols <- gsub(pat, '\\1', hits)
cat('assigned columns          :', paste(cols, collapse = ', '), '\n')
cat('X_template length         :', length(e$X_template), '\n')
missing <- setdiff(cols, e$X_template)
cat('missing from X_template   :', if (length(missing) == 0) 'NONE' else paste(missing, collapse = ', '), '\n')
cat('script parses             :', length(parse(p)) > 0, '\n')
cat('RESULT                    :', if (length(missing) == 0) 'PASS' else 'FAIL', '\n')
