library(fixest)

setwd("C:/Users/jdany/data501")
data.final = read.csv("data_final.csv")

# two-tailed Z proportion test - pvalue < 0.05
prop.test(table(data.final$holiday, data.final$DepDel15))

# one-tailed to test if the proportion of delayed flights in holiday periods 
#is actually greater than non-holiday periods - # pvalue < 0.05
prop.test(table(data.final$holiday, data.final$DepDel15), alternative = "g") 

model_rq2 <- feglm( DepDel15 ~ holiday + airport_crowd + Distance +
                      TEMP + VISIB + PRCP + Rain + Snow + MXSPD |
                      Reporting_Airline + Origin + DayOfWeek + DepTimeBlk,
                    data = data.final,
                    family = "binomial")

summary(model_rq2)

exp(0.065235)