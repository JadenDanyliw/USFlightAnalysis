library(ranger)
library(tidyverse)
library(pROC)
library(caret)
library(vip)

setwd("C:/Users/jdany/data501")
data.final = read.csv("data_final.csv")

# Selecting only columns needed, removing duplicate columns or ones that
# are unavailable at start of day/would contribute to data leakage
data.rf = data.final |> select(
  Quarter, Month, DayofMonth, DayOfWeek, Reporting_Airline, Origin, OriginState, 
  Dest, DestState, DepTimeBlk, CRSElapsedTime, Distance, direction, 
  airport_crowd, TEMP, DEWP, SLP, STP, VISIB, WDSP, MXSPD, MAX, MIN, PRCP, SNDP, 
  Fog, Rain, Snow, Hail, Thunder, holiday, DepDel15
)

# Correctly formatting each variable (some categorical are stored as numeric)
data.rf = data.rf |> mutate(across(.cols = c(
  Quarter, Month, DayofMonth, DayOfWeek, Reporting_Airline, Origin, OriginState, 
  Dest, DestState, DepTimeBlk, direction, Fog, Rain, Snow, Hail,Thunder, 
  holiday, DepDel15), .fns = as.factor))

glimpse(data.rf)
colnames(data.rf)

# Train/test split of 80/20
set.seed(501)
train.rows = sample(nrow(data.rf), floor(0.8*nrow(data.rf)))
data.train = data.rf[train.rows,]
data.test = data.rf[-train.rows,]

# For training in caret package, indicators and factors with numeral values
# must be changed
data.rf2 = data.rf |> mutate(across(.cols = c(
  Quarter, Month, DayofMonth, DayOfWeek, DepTimeBlk, direction, Fog, Rain, Snow, 
  Hail, Thunder, holiday, DepDel15), .fns = make.names))
data.train2 = data.rf2[train.rows,]
data.test2 = data.rf2[-train.rows,]

# 5-fold cross validation settings. Hyperparameters chosen based on AUC 
cv = trainControl(methodb= "cv", number = 5, verboseIter = TRUE, 
                  classProbs = TRUE, summaryFunction = twoClassSummary)

# Different mtry values and split rules
param_grid = expand.grid(mtry = c(3,4,5), splitrule = c("gini", "extratrees"), 
                         min.node.size = c(10))

# Cross validation for hyperparamter selection
# 300 trees chosen based on approximately 10 times the number of variables (31)
cv1 = train(
  y = data.train2$DepDel15,
  x = data.train2[,-32],
  method = "ranger",
  trControl = cv,
  num.trees = 300,
  seed = 501,
  importance = "impurity",
  respect.unordered.factors = "ignore",
  tuneGrid = param_grid,
  metric = "ROC"
)
# The selection process took ~ 8 hrs on pc with:
# AMD Radeon RX 9070 XT GPU
# 8 core AMD Ryzen 7 9700X 8-Core Processor CPU (32GB RAM)

cv1$results
# Chose mtry = 7, splitrule = "gini"


###  Model 1  ###
# Probability forest based on chosen hyperparameters using full training dataset
rf1.prob = ranger(
  DepDel15 ~.,
  data = data.train,
  num.trees = 300,
  mtry = 7,
  splitrule = "gini",
  min.node.size = 10,
  seed = 501,
  probability = TRUE,
  respect.unordered.factors = "ignore",
  importance = "impurity"
)

# Predictions on test dataset 
rf1.prob.predicts = predict(rf1.prob, data=data.test)

# Compute and display ROC curve for model
rf1.prob.roc = roc(response = data.test$DepDel15, 
                   predictor = rf1.prob.predicts$predictions[,2])
plot(rf1.prob.roc, print.auc =T, col = "#69AAA5")
# 0.727

# Variable importance (not the exact graph visualized in the report)
vip(rf1.prob, num_features = 31, geom = c("point"), 
    aesthetics = list(col = "#69AAA5", size=2))

# Threshold comparison
thresholds = seq(0.1, 0.9, by = 0.1)
# Set a empty frame
metrics = data.frame(
  Threshold = thresholds,
  Recall = NA,
  Specificity = NA,
  Accuracy = NA,
  Precision = NA,
  F1_Score = NA
)

# For every threshold calculate metrics
for (i in 1:length(thresholds)) {
  thresh = thresholds[i]
  predicted_class = ifelse(rf1.prob.predicts$predictions[,2] > thresh, 1, 0)
  cm = table(
    Predicted = predicted_class,   
    Actual = data.test$DepDel15
  )
  TP = cm[2, 2]
  TN = cm[1, 1]
  FP = cm[2, 1]
  FN = cm[1, 2]
  metrics$Recall[i] = TP / (TP + FN)
  metrics$Specificity[i] = TN / (TN + FP)
  metrics$Accuracy[i] = (TP + TN) / (TP + TN + FP + FN)
  metrics$Precision[i] = ifelse((TP + FP) == 0, NA, TP / (TP + FP))
  metrics$F1_Score[i] = ifelse((2 * TP + FP + FN) == 0, NA, 2 * TP / 
                                 (2 * TP + FP + FN))
}
print(metrics, row.names = FALSE, digits = 4)

# Extract variable importance as a csv for visualization in Tableau
var.imp.full = as.data.frame(rf1.prob$variable.importance)
var.imp.full = var.imp.full |> rename(importance = `rf1.prob$variable.importance`)
total.full = sum(var.imp.full$importance)
var.imp.full = var.imp.full |> mutate(percent.importance = importance/total.full)

write.csv(var.imp.full, file = "var_imp_full.csv", row.names = TRUE)



###  Model 2  ###
# Probability forest using a balanced sampling method instead
percent.of.train = table(data.train$DepDel15)/sum(table(data.train$DepDel15))

# Ratio of delayed to on-time flights
relative = unname(percent.of.train["1"]/percent.of.train["0"])

# Half of delayed flights will be sampled (with replacement),
# Same number of on-time flights will be sampled (with replacement)
fractions = c("0" = 0.5*relative, "1" = 0.5)
fractions * percent.of.train # ensure the sampling "weights" are the same

# Second probability forest
rf2.prob = ranger(
  DepDel15 ~.,
  data = data.train,
  num.trees = 300,
  mtry = 7,
  splitrule = "gini",
  min.node.size = 10,
  seed = 501,
  probability = TRUE,
  respect.unordered.factors = "ignore",
  importance = "impurity",
  sample.fraction = fractions
)

# Predictions on test dataset 
rf2.prob.predicts = predict(rf2.prob, data=data.test)

# Compute and display ROC curve for model
rf2.prob.roc = roc(response = data.test$DepDel15, 
                   predictor = rf2.prob.predicts$predictions[,2])
plot(rf2.prob.roc, print.auc =T)
# 0.729

# Variable importance
vip(rf2.prob, num_features = 31, geom = c("point"), 
    aesthetics = list(col = "#69AAA5", size=2))

# Threshold comparison
thresholds = seq(0.1, 0.9, by = 0.1)
# Set a empty frame
metrics2 = data.frame(
  Threshold = thresholds,
  Recall = NA,
  Specificity = NA,
  Accuracy = NA,
  Precision = NA,
  F1_Score = NA
)

# For every threshold calculate metrics
for (i in 1:length(thresholds)) {
  thresh = thresholds[i]
  predicted_class = ifelse(rf2.prob.predicts$predictions[,2] > thresh, 1, 0)
  cm = table(
    Predicted = predicted_class,   
    Actual = data.test$DepDel15
  )
  TP = cm[2, 2]
  TN = cm[1, 1]
  FP = cm[2, 1]
  FN = cm[1, 2]
  metrics2$Recall[i] = TP / (TP + FN)
  metrics2$Specificity[i] = TN / (TN + FP)
  metrics2$Accuracy[i] = (TP + TN) / (TP + TN + FP + FN)
  metrics2$Precision[i] = ifelse((TP + FP) == 0, NA, TP / (TP + FP))
  metrics2$F1_Score[i] = ifelse((2 * TP + FP + FN) == 0, NA, 2 * TP / 
                                  (2 * TP + FP + FN))
}
print(metrics2, row.names = FALSE, digits = 4)



###  Model 3  ###
# Adjustment of first probability forest with less trees to save space
rf3.prob = ranger(
  DepDel15 ~.,
  data = data.train,
  num.trees = 75,
  mtry = 7,
  splitrule = "gini",
  min.node.size = 10,
  seed = 501,
  probability = TRUE,
  respect.unordered.factors = "ignore",
  importance = "impurity"
)

# Predictions on test dataset 
rf3.prob.predicts = predict(rf3.prob, data=data.test)

# Compute and display ROC curve for model
rf3.prob.roc = roc(response = data.test$DepDel15, 
                     predictor = rf3.prob.predicts$predictions[,2])
plot(rf3.prob.roc, print.auc =T, col = "#69AAA5")
# 0.723

# Variable importance (not the exact graph visualized in the report)
vip(rf3.prob, num_features = 31, geom = c("point"), 
    aesthetics = list(col = "#69AAA5"))

# Threshold comparison
thresholds = seq(0.1, 0.9, by = 0.1)
# Set a empty frame
metrics3 = data.frame(
  Threshold = thresholds,
  Recall = NA,
  Specificity = NA,
  Accuracy = NA,
  Precision = NA,
  F1_Score = NA
)

# For every threshold calculate metrics
for (i in 1:length(thresholds)) {
  thresh = thresholds[i]
  predicted_class = ifelse(rf3.prob.predicts$predictions[,2] > thresh, 1, 0)
  cm = table(
    Predicted = predicted_class,   
    Actual = data.test$DepDel15
  )
  TP = cm[2, 2]
  TN = cm[1, 1]
  FP = cm[2, 1]
  FN = cm[1, 2]
  metrics3$Recall[i] = TP / (TP + FN)
  metrics3$Specificity[i] = TN / (TN + FP)
  metrics3$Accuracy[i] = (TP + TN) / (TP + TN + FP + FN)
  metrics3$Precision[i] = ifelse((TP + FP) == 0, NA, TP / (TP + FP))
  metrics3$F1_Score[i] = ifelse((2 * TP + FP + FN) == 0, NA, 2 * TP / 
                                  (2 * TP + FP + FN))
}
print(metrics3, row.names = FALSE, digits = 4)

# Extract variable importance as a csv for visualization in Tableau
var.imp = as.data.frame(rf3.prob$variable.importance)
var.imp = var.imp |> rename(importance = `rf3.prob$variable.importance`)
total = sum(var.imp$importance)
var.imp = var.imp |> mutate(percent.importance = importance/total)

write.csv(var.imp, file = "var_imp.csv", row.names = TRUE)



# Save Model 3 as a RDS file
saveRDS(rf3.prob, file = "rfmodel1_75tree.rds")



