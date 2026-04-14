setwd("C:/Users/jdany/data501/flights")
library(tidyverse) # includes dplyr
library(geosphere)

# Monthly number of flights
# 7079061
# 547271+519221+591767+582185+609743+611132+634613+619025+582622+615497+575404+590581

setwd("C:/Users/jdany/data501")

## Combined dataset of domestic flights from each month of 2024
bigdata = read.csv("2024combined.csv")

# Number of cancelled and diverted flights to be removed
sum(bigdata$Cancelled) # 96315
sum(bigdata$Diverted) # 17499

data.removed = bigdata |> filter(Cancelled == 0 & Diverted == 0)
nrow(data.removed) # 6965247

sort(table(data.removed$Origin), decreasing = T)[1:15]
top15 = names(sort(table(data.removed$Origin), decreasing = T)[1:15])

data.top15 = data.removed |> filter(Origin %in% top15)
nrow(data.top15) # 3026080

sum(data.top15$DepDelay > 120)/nrow(data.top15) # 0.02936505
data.noextremes = data.top15 |> filter(DepDelay > -15 & DepDelay < 120)
nrow(data.noextremes) # 2925303
nrow(data.noextremes) / nrow(bigdata) # 0.4132332


## Metadata for every airport
metadata = read.csv("airports.csv")
nrow(metadata)


# Master Location Identifier Database 
# https://www.weathergraphics.com/identifiers/
master.location = read.csv("master-location-identifier.csv", skip=5)



### METADATA JOINING ###

# metadata for only the top 15 origin airports in the domestic flight data
trimmed.metadata = metadata[metadata$iata_code %in% top15,]

# Adding WBAN number by joining through ICAO code
origin.wban.metadata = trimmed.metadata |>
  left_join(master.location |> select(icao, national_id, wban, lat, lon), 
            by = join_by(icao_code ==icao))

# metadata for the destination airports in the filtered domestic flight data
dest.metadata = metadata[metadata$iata_code %in% unique(data.noextremes$Dest),]



### OTR JOINING ###

## Joining with metadata

# Origin
data.with.origin.metadata = data.noextremes |> 
  left_join(origin.wban.metadata |> 
              select(iata_code, wban, latitude_deg, longitude_deg), 
            by = join_by(Origin==iata_code))

# Destination
data.with.metadata = data.with.origin.metadata |> 
  left_join(dest.metadata |> select(iata_code, latitude_deg, longitude_deg), 
            by = join_by(Dest==iata_code))

# Renaming new columns
colnames(data.with.metadata)
data.with.metadata = data.with.metadata |> 
  rename(origin.lat = latitude_deg.x, origin.long = longitude_deg.x,
         dest.lat = latitude_deg.y, dest.long = longitude_deg.y)


## Addition of direction variable for flights

# Function to turn bearing degrees into one of the 8 highest cardinal directions
deg_to_direction = function(degrees){
  directions = c("N", "NE", "E", "SE", "S", "SW", "W", "NW", "N")
  index = floor((degrees + 22.5) %% 360 / 45) + 1
  return(directions[index])
}

# Direction of each flight
direction.included = data.with.metadata |> rowwise() |>
  mutate(direction = deg_to_direction(bearing(c(origin.long, origin.lat),
                                              c(dest.long, dest.lat))))

direction.included[floor(runif(1, 1, 2900000)),] |> select(Origin, Dest, direction)



## Addition of network and airport crowdedness variables

airport.crowd = direction.included |> 
  group_by(Origin, Month, DayofMonth, DepTimeBlk) |>
  add_count() |> ungroup() |> rename(airport_crowd = n)

colnames(airport.crowd)


## Addition of "day before" variable ##

# Function to determine the day before the day of the flight
day.before = function(year, month, day){
  if (day == 1) {
    if (month == 1){
      prev.year = 2023; prev.month = 12; prev.day = 31
    } else if (month == 3) {
      prev.year = 2024; prev.month = 2; prev.day = 29
    } else if (month == 2 | month == 4 | month == 6 | 
               month == 8 | month == 9 | month == 11) {
      prev.year = 2024; prev.month = month - 1; prev.day = 31
    } else {
      prev.year = 2024; prev.month = month - 1; prev.day = 30
    }
  } else {
    prev.year = 2024; prev.month = month; prev.day = day - 1
  }
  
  return (c(prev.year, prev.month, prev.day))
}


data.day.before = airport.crowd |> rowwise() |>
  mutate(previousday.year = day.before(Year, Month, DayofMonth)[1],
         previousday.month = day.before(Year, Month, DayofMonth)[2],
         previousday.day = day.before(Year, Month, DayofMonth)[3])

data.day.before[floor(runif(1, 1, 2900000)),] |> 
  select(Year, Month, DayofMonth, previousday.year, previousday.month, previousday.day)




### GSOD Weather Data ###

# setwd("C:/Users/jdany/data501/gsod24")

# 0, 7, 13, 18, 20, 24, 31, 35, 42, 46, 53, 57, 64, 68, 74, 78, 84, 88, 95, 102, 110, 118, 125, 132, 133, 134, 135, 136, 137
# This is the order of character spacing/starting values for manual conversion 
# from .op file to .csv file done in excel


# List of 2024 csv files in the gsod24 folder 
# 16 files, 1 for each airport and 1 supplementary file for missing PHX data
weather.list.24 = list.files(pattern="\\-24.csv$")

# Only the full datasets, not including PHX 2024, which will be supplemented 
# with 23104 (Chandler) for october
fulldataset.list.24 = weather.list.24[-which(weather.list.24 %in% 
                                              c("23183-24.csv", "23104-24.csv"))]

# Read every full csv file
weather.data.list.24 = lapply(fulldataset.list.24, read.csv)

# All but PHX
combined.2024 = do.call(rbind, weather.data.list.24) 
# lots of missing values for GUST, will be removed later


# To remedy to missing values in the PHX data, ratio interpolation based on 
# nearby Chandler station is done for some of the missing days (Oct 1-12)
phoenix  = read.csv("23183-24.csv")
view(phoenix)
chandler = read.csv("23104-24.csv")

chandler.septoct = chandler |> filter(MO == 9 | (MO == 10 & DA > 12))
phoenix.septoct = phoenix |> filter(MO == 9 | MO == 10)

# Cleaning sept/oct for phoenix and chandler to perform ratio estimation of missing values 
chandler.septoct = chandler.septoct |> rowwise() |>
  mutate(SLP = ifelse(SLP == 9999.9, NA, SLP)) |>
  mutate(STP = ifelse(STP == 9999.9, NA, STP)) |>
  mutate(SNDP = ifelse(SNDP == 999.9, 0, SNDP)) |>
  mutate(MAX = as.numeric(str_remove_all(MAX, "\\*"))) |>
  mutate(MIN = as.numeric(str_remove_all(MIN, "\\*"))) |>
  mutate(PRCP = as.numeric(str_remove_all(PRCP, "[ABCDEFGHI]")))
view(chandler.septoct)

phoenix.septoct = phoenix.septoct |> rowwise() |>
  mutate(SLP = ifelse(SLP == 9999.9, NA, SLP)) |>
  mutate(STP = ifelse(STP == 9999.9, NA, STP)) |>
  mutate(SNDP = ifelse(SNDP == 999.9, 0, SNDP)) |>
  mutate(MAX = as.numeric(str_remove_all(MAX, "\\*"))) |>
  mutate(MIN = as.numeric(str_remove_all(MIN, "\\*"))) |>
  mutate(PRCP = as.numeric(str_remove_all(PRCP, "[ABCDEFGHI]")))
view(phoenix.septoct)

# Phoenix divided by Chandler for ratios
temp.ratio = mean(phoenix.septoct$TEMP / chandler.septoct$TEMP) # 1.062
dewp.ratio = mean(phoenix.septoct$DEWP / chandler.septoct$DEWP) # 0.908
phx.slp.to.stp.ratio = mean(phoenix.septoct$SLP / phoenix.septoct$STP) # 1.039
stp.ratio = mean(phoenix.septoct$STP[-which(is.na(chandler.septoct$STP))] / 
                   chandler.septoct$STP[-which(is.na(chandler.septoct$STP))]) # 1.009
visib.ratio = mean(phoenix.septoct$VISIB / chandler.septoct$VISIB) # 1.001
wdsp.ratio = mean(phoenix.septoct$WDSP / chandler.septoct$WDSP) # 0.891
mxspd.ratio = mean(phoenix.septoct$MXSPD / chandler.septoct$MXSPD) # 0.942
max.ratio = mean(phoenix.septoct$MAX / chandler.septoct$MAX) # 1.062
min.ratio = mean(phoenix.septoct$MIN / chandler.septoct$MIN) # 1.083

# Modify the chandler values to become the phoenix values
chandler.fill.in = chandler |> filter(MO == 10 & DA <=12)

phoenix.fill.in = chandler.fill.in |> rowwise() |> mutate(WBAN = 23183) |>
  mutate(TEMP = round(TEMP * temp.ratio,1)) |>
  mutate(DEWP = round(DEWP * dewp.ratio,1)) |>
  mutate(STP = round(STP * stp.ratio,1)) |>
  mutate(WDSP = round(WDSP * wdsp.ratio,1)) |>
  mutate(MXSPD = round(MXSPD * mxspd.ratio,1)) |>
  mutate(SNDP = ifelse(SNDP == 999.9, 0, SNDP)) |>
  mutate(MAX = round(as.numeric(str_remove_all(MAX, "\\*")) * max.ratio,1)) |>
  mutate(MIN = round(as.numeric(str_remove_all(MIN, "\\*")) * min.ratio,1)) |>
  mutate(PRCP = as.numeric(str_remove_all(PRCP, "[ABCDEFGHI]")))

# Estimated based on relationship between STP and STP for Phoenix
phoenix.fill.in = phoenix.fill.in |> rowwise() |>
  mutate(SLP = round(STP * phx.slp.to.stp.ratio, 1)) 

glimpse(phoenix.fill.in)
glimpse(phoenix)

phoenix.all.days = rbind(phoenix, phoenix.fill.in, 
                  c(722780, 23183, 2024, 10, 1, rep(NA, ncol(phoenix)-5)),
                  c(722780, 23183, 2024, 10, 2, rep(NA, ncol(phoenix)-5)),
                  c(722780, 23183, 2024, 10, 7, rep(NA, ncol(phoenix)-5)))

view(phoenix.all.days)
glimpse(phoenix.all.days)

# 
combined.all.2024 = rbind(combined.2024, phoenix.all.days)
nrow(combined.all.2024) # = 15*366


# 2023 data for december 31
# setwd("C:/Users/jdany/data501/gsod23")


# List of 2023 csv files in the gsod23 folder 
# (number of files)
weather.list.23 = list.files(pattern="\\-23.csv$")

# Read every csv file
weather.data.list.23 = lapply(weather.list.23, read.csv)

# All as one combined dataset
combined.2023 = do.call(rbind, weather.data.list.23)

# Only december 31; that is all we need
last.day = combined.2023 |> filter(MO==12 & DA==31)
last.day

# Combine with 2024
weather.all.days = rbind(combined.all.2024, last.day)
nrow(weather.all.days)/367 # = 367*15

# Sort to be chronological by wban station
weather.all.days = weather.all.days |> arrange(WBAN, YEAR, MO, DA)
glimpse(weather.all.days)
view(weather.all.days)

# Rename columns to be more informative
names = colnames(weather.all.days)
names[24] = "Fog"; names[25] = "Rain"; names[26] = "Snow"
names[27] = "Hail"; names[28] = "Thunder"; names[29] = "Tornado"
colnames(weather.all.days) = names

# Pick out only variables needed
weather.all.days = weather.all.days |>
  select(WBAN, YEAR, MO, DA, TEMP, DEWP, SLP, STP, VISIB, WDSP, MXSPD, MAX, MIN,
         PRCP, SNDP, Fog, Rain, Snow, Hail, Thunder, Tornado)
glimpse(weather.all.days)


# Correction of values
weather.corrected = weather.all.days |> rowwise() |>
  mutate(SLP = ifelse(SLP == 9999.9, NA, SLP)) |>
  mutate(STP = ifelse(STP == 9999.9, NA, STP)) |>
  mutate(SNDP = ifelse(SNDP == 999.9, 0, SNDP)) |>
  mutate(MAX = as.numeric(str_remove_all(MAX, "\\*"))) |>
  mutate(MAX = ifelse(MAX == 9999.9, NA, MAX)) |>
  mutate(MIN = as.numeric(str_remove_all(MIN, "\\*"))) |>
  mutate(MIN = ifelse(MIN == 9999.9, NA, MIN)) |>
  mutate(PRCP = as.numeric(str_remove_all(PRCP, "[ABCDEFGHI]"))) |>
  mutate(PRCP = ifelse(PRCP == 99.99, 0, PRCP))

# Interpolating (linearly) values for the 3 missing phoenix days
phx.oct.nums = which(is.na(weather.corrected$TEMP))
weather.corrected[phx.oct.nums,]

for (i in c(5:21)){
  sept30.ind = phx.oct.nums[1] - 1
  oct3.ind = phx.oct.nums[2] + 1
  oct6.ind = phx.oct.nums[3] - 1
  oct8.ind = phx.oct.nums[3] + 1
  
  # Oct 1
  weather.corrected[phx.oct.nums[1], i] = round(
    (weather.corrected[oct3.ind, i] - weather.corrected[sept30.ind, i])/3 + 
             weather.corrected[sept30.ind, i], 1)
  
  # Oct 2
  weather.corrected[phx.oct.nums[2], i] = round(
    2*(weather.corrected[oct3.ind, i] - weather.corrected[sept30.ind, i])/3 + 
      weather.corrected[sept30.ind, i], 1)
  
  # Oct 7
  weather.corrected[phx.oct.nums[3], i] = round(
    (weather.corrected[oct8.ind, i] - weather.corrected[oct6.ind, i])/2 + 
      weather.corrected[oct6.ind, i], 1)
}

view(weather.corrected)

# Few more NA values to interpolate and impute
summary(weather.corrected$SLP) # 35 NA values
summary(weather.corrected$STP) # 189 NA values
summary(weather.corrected$MAX) # 2 NA values

# Interpolating (linearly) values for the 2 missing max temperatures 
# WBAN 3017 on 1/16 and 4/18
max.missing = which(is.na(weather.corrected$MAX))
weather.corrected[max.missing,]

weather.corrected[max.missing[1],]$MAX = 
  mean( c(weather.corrected[max.missing[1]-1,]$MAX, 
          weather.corrected[max.missing[1]+1,]$MAX) )

weather.corrected[max.missing[2],]$MAX = 
  mean( c(weather.corrected[max.missing[2]-1,]$MAX, 
          weather.corrected[max.missing[2]+1,]$MAX) )

weather.corrected[max.missing,]
view(weather.corrected)

weather.pressure.fixing = weather.corrected

# Which are missing from STP and SLP
stp.missing = which(is.na(weather.pressure.fixing$STP))
slp.missing = which(is.na(weather.pressure.fixing$SLP))


# Ratio (within wban region) estimation of STP using given value of SLP
just.stp = setdiff(stp.missing, slp.missing)

for (i in just.stp){
  wban = weather.pressure.fixing[i,]$WBAN
  filtered = weather.pressure.fixing |> filter(WBAN == wban & !is.na(STP))
  ratio = mean(filtered$STP/filtered$SLP)
  
  weather.pressure.fixing[i,]$STP = round(weather.pressure.fixing[i,]$SLP * ratio, 1)
}

# Ratio (within wban region) estimation of SLP using given value of STP
just.slp = setdiff(slp.missing, stp.missing)

for (i in just.slp){
  wban = weather.pressure.fixing[i,]$WBAN
  filtered = weather.pressure.fixing |> filter(WBAN == wban & !is.na(SLP))
  ratio = mean(filtered$SLP/filtered$STP)
  
  weather.pressure.fixing[i,]$SLP = round(weather.pressure.fixing[i,]$STP * ratio, 1)
}

view(weather.pressure.fixing)

# Now the only missing left have both pressure variables missing
missing = which(is.na(weather.pressure.fixing$STP))
missing
which(is.na(weather.pressure.fixing$SLP))


# Mean imputation
for (i in missing){
  wban = weather.pressure.fixing[i,]$WBAN
  filtered = weather.pressure.fixing |> filter(WBAN == wban & !is.na(SLP))
  weather.pressure.fixing[i,]$SLP = round(mean(filtered$SLP), 1)
  weather.pressure.fixing[i,]$STP = round(mean(filtered$STP), 1)
}

view(weather.pressure.fixing)

weather.final = weather.pressure.fixing
sum(is.na(weather.final))


### Joining weather to the flight data ###

data.depdelay90 = data.day.before |> 
  mutate(DepDel90 = ifelse(DepartureDelayGroups >= 6, 1, 0))

data.depdelay60 = data.depdelay90 |> 
  mutate(DepDel60 = ifelse(DepartureDelayGroups >= 4, 1, 0))

data.weather.daybefore = data.depdelay60 |> 
  left_join(weather.final |> rename(wban=WBAN, previousday.year=YEAR,
                                    previousday.month=MO, previousday.day=DA), 
            by = join_by(wban, previousday.year, previousday.month, previousday.day))

data.with.weather = data.weather.daybefore |> 
  left_join(weather.final |> rename(wban=WBAN, Year=YEAR, Month=MO, DayofMonth=DA), 
            by = join_by(wban, Year, Month, DayofMonth))


data.weather.daybefore[floor(runif(1, 1, 2900000)),] |> 
  select(previousday.year, previousday.month, previousday.day, wban, TEMP, DEWP, SLP, PRCP)

# https://www.ncei.noaa.gov/pub/data/gsod/GSOD_DESC.txt data dictionary for weather variables

data.final = data.with.weather |> 
  rename(TEMP = TEMP.x, DEWP = DEWP.x, SLP = SLP.x, STP = STP.x, VISIB = VISIB.x, 
         WDSP = WDSP.x, MXSPD = MXSPD.x, MAX = MAX.x, MIN = MIN.x, PRCP = PRCP.x,
         SNDP = SNDP.x, Fog = Fog.x, Rain = Rain.x, Snow = Snow.x, Hail = Hail.x,
         Thunder = Thunder.x, Tornado = Tornado.x,
         TEMP.today = TEMP.y, DEWP.today = DEWP.y, SLP.today = SLP.y, 
         STP.today = STP.y, VISIB.today = VISIB.y, WDSP.today = WDSP.y, 
         MXSPD.today = MXSPD.y, MAX.today = MAX.y, MIN.today = MIN.y, 
         PRCP.today = PRCP.y, SNDP.today = SNDP.y, Fog.today = Fog.y, 
         Rain.today = Rain.y, Snow.today = Snow.y, Hail.today = Hail.y,
         Thunder.today = Thunder.y, Tornado.today = Tornado.y)
colnames(data.final)


## Holiday data ##

# BTS holiday definitions
holiday_period <- c("2024-01-01","2024-01-02","2024-01-03",
                    "2024-02-15","2024-02-16","2024-02-17","2024-02-18","2024-02-19","2024-02-20",
                    "2024-03-24","2024-03-25","2024-03-26","2024-03-27","2024-03-28","2024-03-29","2024-03-30","2024-03-31","2024-04-01","2024-04-02","2024-04-03","2024-04-04","2024-04-05","2024-04-06","2024-04-07",
                    "2024-05-20","2024-05-21","2024-05-22","2024-05-23","2024-05-24","2024-05-25","2024-05-26","2024-05-27","2024-05-28","2024-05-29",
                    "2024-06-28","2024-06-29","2024-06-30","2024-07-01","2024-07-02","2024-07-03","2024-07-04","2024-07-05","2024-07-06","2024-07-07",
                    "2024-08-28","2024-08-29","2024-08-30","2024-08-31","2024-09-01","2024-09-02","2024-09-03","2024-09-04",
                    "2024-11-22","2024-11-23","2024-11-24","2024-11-25","2024-11-26","2024-11-27","2024-11-28","2024-11-29","2024-11-30","2024-12-01","2024-12-02","2024-12-03",
                    "2024-12-14","2024-12-15","2024-12-16","2024-12-17","2024-12-18","2024-12-19","2024-12-20","2024-12-21","2024-12-22","2024-12-23","2024-12-24","2024-12-25","2024-12-26","2024-12-27","2024-12-28","2024-12-29","2024-12-30","2024-12-31")

data.final = data.final |>
  mutate(holiday = ifelse(FlightDate %in% holiday_period, 1, 0))

removed.columns = c(0,8,9,12:14,18:23,27:29,48:50,58,65:109)
removed.columns = removed.columns+1

data.final = data.final[,-removed.columns]
colnames(data.final)

# Write a csv
setwd("C:/Users/jdany/data501")
write.csv(data.final, file = "data_final.csv", row.names = FALSE)
