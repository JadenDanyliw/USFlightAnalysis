setwd("C:/Users/jdany/data501/flights")

# read all twelve monthly datasets
data1 = read.csv("2024_01_OTRCOTP.csv")
data2 = read.csv("2024_02_OTRCOTP.csv")
data3 = read.csv("2024_03_OTRCOTP.csv")
data4 = read.csv("2024_04_OTRCOTP.csv")
data5 = read.csv("2024_05_OTRCOTP.csv")
data6 = read.csv("2024_06_OTRCOTP.csv")
data7 = read.csv("2024_07_OTRCOTP.csv")
data8 = read.csv("2024_08_OTRCOTP.csv")
data9 = read.csv("2024_09_OTRCOTP.csv")
data10 = read.csv("2024_10_OTRCOTP.csv")
data11 = read.csv("2024_11_OTRCOTP.csv")
data12 = read.csv("2024_12_OTRCOTP.csv")

# bind all together by rows
bigdata = rbind(data1, data2, data3, data4, data5, data6, 
                  data7, data8, data9, data10, data11, data12)

# export as csv
write.csv(bigdata, file = "2024combined.csv", row.names = FALSE)
