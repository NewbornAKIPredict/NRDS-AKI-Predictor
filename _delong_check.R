suppressPackageStartupMessages(library(pROC))
d <- read.csv("NestedCV_All_Predictions.csv")
# Table 1 coding: <32w = GA_grp 1+2 ; >=32w = GA_grp 3+4 ; Others = 0 excluded
a <- d[d$GA_grp %in% c(1,2),]; b <- d[d$GA_grp %in% c(3,4),]
cat(sprintf("<32w n=%d ev=%d ; >=32w n=%d ev=%d\n",nrow(a),sum(a$AKI_num),nrow(b),sum(b$AKI_num)))
r1 <- roc(a$AKI_num, a$XGB, quiet=TRUE); r2 <- roc(b$AKI_num, b$XGB, quiet=TRUE)
cat(sprintf("AUC <32w=%.4f  >=32w=%.4f\n",as.numeric(r1$auc),as.numeric(r2$auc)))
cat(sprintf("unpaired DeLong p = %.6g\n", roc.test(r1,r2,method="delong")$p.value))
