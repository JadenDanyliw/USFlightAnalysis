# USFlightAnalysis

This repository contains all of the R code used in the Weather and Operational Interactive Analysis of United States Domestic Flight Delays Across Holiday Seasons report by Jaden Danyliw, Jensen MacLean, and Danielle Malzar. Due to file size restrictions, any file or dataset larger than 25 MB is inlcuded seperately in a **Google Drive** folder at the following link: https://drive.google.com/drive/u/0/folders/1Jn7yFeZERiRduMNEtbZlgfOSQeZVvuYR

## Dataset Descriptions

12 monthly flight performance datasets for January - December 2024 are contained in the "flights.zip" folder in **Google Drive** in the format "2024_MM_OTRCOTP.csv" where MM denotes the month of flight data. These were dowloaded from the Bureau of Transportation Statistics (BTS) website, https://www.transtats.bts.gov/DL_SelectFields.aspx?gnoyr_VQ=FGJ&QO_fu146_anzr=, where select variables can be chosen for dowloads by month. During preliminary data aquisition, we chose to include every variable just in case.

31 yearly Global Surface Summary of the Day (GSOD) weather datasets are included in this repository in the format "XXXXX-YY.csv", where XXXXX represents the unique WBAN identifier for the airport weather station of the data and YY represents the year after 2000. Specifically included are 2 datasets for each of the 15 chosen airports in our analysis (2023 and 2024), along with the supplementary "23104-24.csv" from Chandler Municipal Airport used for estimating missing Pheonix Sky Harbor International Airport weather days in early October, 2024. These were downloaded from National Oceanic and Atmospheric Administration (NOAA) website at https://www.ncei.noaa.gov/pub/data/gsod/2024 and https://www.ncei.noaa.gov/pub/data/gsod/2023 on March 12, 2026. As of April 14, 2026, this particular section of the website is either undergoing maintenance or has been taken down for an unknown reason. Thus, the raw data files in the format "UUUUUU-XXXXX-YYYY.op" are included in the repository in the "raw_weather_data" folder as well, where UUUUUU represents the USAF number of the weather station, and XXXXX and YYYY are respectively the WBAN number and year. Each original fixed-length text .op files were opened in Microsoft Excel, and split by known variable character lengths to create more usable .csv files and renamed manually to complete the file conversion process. An alternative data source that we have found within the NCEI NOAA website is https://www.ncei.noaa.gov/data/global-summary-of-the-day/access/2024/, which contains files in the format "UUUUUUXXXXX.csv" in year-specific folders, such as 2024.

The "airports.csv" airport metadata dataset was obtained from OurAirports at https://ourairports.com/data/airports.csv, which contains location and identification valuable for data merging. Included in this repository

The "master-location-identifier.csv" dataset was obatined from WeatherGraphics at https://www.weathergraphics.com/identifiers/, which contains identification and WBAN corresponding to airports valuable for data merging. Included in this repository

## 2024combining.R

This included R code takes each of the 12 monthly BTS On-Time Performance datasets and combines them into one file, requiring all 12 datasets in the working directory. This dataset is exported as "2024combined.csv", which is included in **Google Drive** 

## newdatacleaning.R

This included R code completes the cleaning process outlined in Section 2.2 of the report. This involves:
- Exclusion of cancelled and diverted flights, along with flights with delays of more than 120 minutes or less than -15 minutes
- Filtering airport metadata
- Joining WBAN stations to metadata
- Joining WBAN stations to each flight
- Filling in missing weather data values through ratio estimation, linear interpolation and mean imputation
- Joining flights with previous-day and flight-day weather data
- Creation of direction, airport crowdedness, and holiday indicator variables.

Requires all 31 GSOD weather .csv files, "2024combined.csv", "airports.csv", and "master-location-identifier.csv" in the working directory. Exports the final dataset as "data_final.csv", which is included in **Google Drive**.

## RQ2.R

This included R code performs the statistical modelling techniques for research question 2, outlined in Sections 2.5 and 3.2 of the report. This includes the one-sided two-sample z-test for proportions and the fixed effect model estimation. Requires "data_final.csv" in the working directory.

## randomforest.R

This included R code performs the probability Random Forest modelling procedure and analysis outlined in Sections 2.5 and 3.3 of the report. This involves:
- Training and testing data split
- 5-fold cross-validation for model parameter tuning
- Creation of Model 1 (300 tree bootstrap replacement sampling)
- Creation of Model 2 (300 tree balanced bootstrap replacement sampling)
- Creation of Model 3 (75 tree bootstrap replacement sampling)
- ROC curves
- Threshold metric comparisons for classification
- Variable importance plots

Requires "data_final.csv" in the working directory. Exports Model 3 as an RDS file "rfmodel1_75tree.rds", which is included in **Google Drive**.

## app.R

This included R code is the code to create the R Shiny application for real-time use of Model 3. Included is user input fields, calculation of variables needed for the model based on inputted values (such as distance, holiday, departure hour block), probability prediction using Model 3, and output. Requires "rfmodel1_75tree.rds", "choices.rds" (describes the available choices for users in drop-down menus) and "airports.parquet" (airport metadata) to be in the working directory. To run locally, click "Run App" in the top right of the Source pane in RStudio with the aforementioned working directory setup, or go to https://danyliw-maclean-malzar-data-501.shinyapps.io/flight_prediction/ to run over the web. Instructions for inputting variables are found in Tableau research question 3 analysis at https://public.tableau.com/app/profile/jensen.maclean/viz/data_501/RQ3.
