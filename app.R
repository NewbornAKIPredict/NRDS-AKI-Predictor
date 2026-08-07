# app.R 【云端shinyapps.io专用纯净版本】
# 仅运行预测，不含建模代码！！
library(shiny)
library(xgboost)
library(dplyr)
library(DiagrammeR)

# ===================== 全局固定参数 =====================
ppv_threshold <- 0.252   # High-risk threshold
youden_threshold <- 0.168 # Moderate-risk threshold

# 加载模型与Boruta筛选特征（相对路径，云端可用）
model_file <- "./xgboost_model.rda"
if (!file.exists(model_file)) {
  stop("Model file xgboost_model.rda cannot be found!")
}
load(model_file) # 载入 model_xgboost, selected_feat

# -------------------- Shiny UI --------------------
ui <- fluidPage(
  titlePanel("👶 Neonatal AKI Risk Calculator (XGBoost)"),
  sidebarLayout(
    sidebarPanel(
      h4("Clinical Predictors (Boruta Selected Variables)"),
      
      h4("Clinical Score"),
      numericInput("SNAP_II", "SNAP-II Score:", value = 15, min = 0, max = 100, step = 1),
      numericInput("LOS", "Length of Stay (days):", value = 10, min = 1, max = 365, step = 1),
      
      h4("Urine and Weight"),
      numericInput("FirstUrineOutput", "First Urine Output (ml):", value = 0, min = 0, max = 1200, step = 0.1),
      numericInput("firstweight", "Birth Weight (g):", value = 2500, min = 0, max = 8000, step = 10),
      numericInput("min_weight", "Minimum Weight (g):", value = 2400, min = 0, max = 8000, step = 10),
      selectInput("Weight_label", "Weight Label", choices = c("0"=0,"1"=1)),
      
      h4("Blood Parameters"),
      numericInput("WBC_min", "WBC Min (×10^9/L):", value = 5, min = 1, max = 50, step = 0.1),
      numericInput("WBC_max", "WBC Max (×10^9/L):", value = 15, min = 1, max = 50, step = 0.1),
      numericInput("HEMATOCRIT_min", "Hematocrit Min (%):", value = 30, min = 10, max = 80, step = 0.1),
      numericInput("HEMATOCRIT_max", "Hematocrit Max (%):", value = 42, min = 10, max = 80, step = 0.1),
      numericInput("HEMOGLOBIN_min", "Hemoglobin Min (g/dL):", value = 11, min = 5, max = 25, step = 0.1),
      numericInput("HEMOGLOBIN_max", "Hemoglobin Max (g/dL):", value = 15, min = 5, max = 25, step = 0.1),
      numericInput("PLATELET_min", "Platelet Min (×10^9/L):", value = 150, min = 10, max = 1000, step = 10),
      numericInput("PLATELET_max", "Platelet Max (×10^9/L):", value = 280, min = 10, max = 1000, step = 10),
      
      h4("Treatment & Complications (0=No,1=Yes)"),
      selectInput("NSAIDs", "NSAIDs Exposure:", choices = c("No" = 0, "Yes" = 1)),
      selectInput("ventdurationssingle_flag", "Mechanical Ventilation:", choices = c("No" = 0, "Yes" = 1)),
      selectInput("diuretics_flag", "Diuretics:", choices = c("No" = 0, "Yes" = 1)),
      selectInput("methylxanthine_flag", "Methylxanthine:", choices = c("No" = 0, "Yes" = 1)),
      selectInput("Patent_ductus_arteriosus", "PDA:", choices = c("No" = 0, "Yes" = 1)),
      
      h4("Demographics"),
      selectInput("GA", "Gestational Age Group:",
                  choices = c("≤28 w" = "≤28 w",
                              "29–32 w" = "29–32 w",
                              "33–34 w" = "33–34 w",
                              "35–36 w" = "35–36 w",
                              "≥37 w" = "≥37 w")),
      
      actionButton("predict_btn", "Predict AKI Risk", class = "btn-primary")
    ),
    mainPanel(
      h3("Predicted Probability of AKI"),
      uiOutput("warning_msg"),
      verbatimTextOutput("pred_prob"),
      uiOutput("risk_label"),
      plotOutput("risk_plot"),
      h4("Risk Stratification Flow Chart"),
      grVizOutput("flow_chart", height = "350px")
    )
  )
)

# -------------------- Shiny Server --------------------
server <- function(input, output, session) {
  
  observeEvent(input$predict_btn, {
    # 孕周分组转为数值编码（和训练集保持一致）
    GA_value <- switch(input$GA,
                       "≤28 w" = 1,
                       "29–32 w" = 2,
                       "33–34 w" = 3,
                       "35–36 w" = 4,
                       "≥37 w" = 5)
    
    # 构建患者输入数据集【全部变量来自selected_feat清单】
    new_patient <- data.frame(
      SNAP_II = input$SNAP_II,
      LOS = input$LOS,
      FirstUrineOutput = input$FirstUrineOutput,
      firstweight = input$firstweight,
      min_weight = input$min_weight,
      Weight_label = as.numeric(input$Weight_label),
      WBC_min = input$WBC_min,
      WBC_max = input$WBC_max,
      HEMATOCRIT_min = input$HEMATOCRIT_min,
      HEMATOCRIT_max = input$HEMATOCRIT_max,
      HEMOGLOBIN_min = input$HEMOGLOBIN_min,
      HEMOGLOBIN_max = input$HEMOGLOBIN_max,
      PLATELET_min = input$PLATELET_min,
      PLATELET_max = input$PLATELET_max,
      NSAIDs = as.numeric(input$NSAIDs),
      ventdurationssingle_flag = as.numeric(input$ventdurationssingle_flag),
      diuretics_flag = as.numeric(input$diuretics_flag),
      methylxanthine_flag = as.numeric(input$methylxanthine_flag),
      Patent_ductus_arteriosus = as.numeric(input$Patent_ductus_arteriosus),
      GA = GA_value
    )
    
    # 校验变量完整性
    missing_vars <- setdiff(selected_feat, colnames(new_patient))
    if(length(missing_vars) > 0){
      msg <- paste("Missing required predictors:", paste(missing_vars, collapse = ", "))
      output$warning_msg <- renderUI({ tags$div(style="color:red;font-weight:bold;", msg) })
      return()
    }
    # 严格对齐模型特征
    new_patient <- new_patient[, selected_feat, drop = FALSE]
    x_new <- data.matrix(new_patient)
    
    # 预测
    pred_prob <- tryCatch({
      predict(model_xgboost, x_new)
    }, error = function(e) {
      output$warning_msg <- renderUI({ tags$div(style="color:red;", paste("Prediction failed:", e$message)) })
      return(NA)
    })
    if (is.na(pred_prob)) return()
    
    # 风险分层
    risk_category <- ifelse(pred_prob >= ppv_threshold, "High",
                            ifelse(pred_prob >= youden_threshold, "Moderate", "Low"))
    risk_color <- ifelse(risk_category == "High", "red",
                         ifelse(risk_category == "Moderate", "orange", "green"))
    
    output$pred_prob <- renderText({
      paste0("Predicted AKI Probability: ", round(pred_prob*100, 1), "%")
    })
    output$risk_label <- renderUI({
      tags$div(style=paste0("color:", risk_color, "; font-weight:bold; font-size:16px;"),
               paste0("Risk Category: ", risk_category))
    })
    output$risk_plot <- renderPlot({
      barplot(pred_prob, col=risk_color, ylim=c(0,1), names.arg="AKI Risk")
      abline(h=youden_threshold, lty=2, col="orange", lwd=2)
      abline(h=ppv_threshold, lty=2, col="red", lwd=2)
      text(x=1, y=youden_threshold+0.02, labels=paste0("Youden = ",youden_threshold), col="orange")
      text(x=1, y=ppv_threshold+0.02, labels=paste0("PPV threshold = ",ppv_threshold), col="red")
    })
    output$flow_chart <- renderGrViz({
      grViz("
        digraph flowchart {
          graph [rankdir = TB]
          node [shape=roundedbox, style=filled, fontname=Helvetica]
          Start    [label='XGBoost Predicted AKI Probability', fillcolor='lightblue']
          Low      [label='Low Risk (<0.168)\\nRoutine monitoring: serum creatinine and urine output, standard NSAID regimen', fillcolor='palegreen']
          Moderate [label='Moderate Risk (0.168–0.252)\\nEnhanced surveillance: optimize NSAID duration, strict fluid balance, close renal monitoring', fillcolor='gold']
          High     [label='High Risk (≥0.252)\\nMultidisciplinary consultation; limit nephrotoxic NSAID exposure; evaluate PDA ligation strategies', fillcolor='tomato']
          
          Start -> Low [label=' <0.168']
          Start -> Moderate [label=' 0.168 ~ 0.252']
          Start -> High [label=' ≥0.252']
        }
      ")
    })
  })
}

# 启动App
shinyApp(ui = ui, server = server)