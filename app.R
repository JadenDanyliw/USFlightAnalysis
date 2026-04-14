library(shiny)
library(stringr)
library(geosphere)
library(measurements)
library(ranger)
library(arrow)
library(shinyWidgets)

# due to RAM issues, converted the csv to parquet file as it takes up significantly less space
metadata <- read_parquet("airports.parquet", 
                         col_select = c("iata_code", "iso_region", 
                                        "latitude_deg", "longitude_deg"))
# Similarly, it took up way too much space to read in the whole flight file
# Extracted the unique choices for each of the inputs to create a dropdown menu without having to do this manually
choices <- readRDS("choices.rds")

# chosen random forest model for the app
RF_model <- readRDS("rfmodel1_75tree.rds")

######################### Functions to be used #################################
deg_to_direction <- function(degrees){
  directions <- c("N","NE","E","SE","S","SW","W","NW","N")
  index = floor((degrees + 22.5) %% 360 / 45) + 1
  return(directions[index])
}

holiday_period <- c("2026-01-01","2026-01-02","2026-01-03","2026-01-04",
                    "2026-01-05",
                    "2026-02-12","2026-02-13","2026-02-14","2026-02-15",
                    "2026-02-16","2026-02-17",
                    "2026-03-29","2026-03-30","2026-03-31","2026-04-01",
                    "2026-04-02","2026-04-03","2026-04-04","2026-04-05",
                    "2026-04-06","2026-04-07","2026-04-08","2026-04-09",
                    "2026-04-10","2026-04-11","2026-04-12",
                    "2026-05-18","2026-05-19","2026-05-20","2026-05-21",
                    "2026-05-22","2026-05-23","2026-05-24","2026-05-25",
                    "2026-05-26","2026-05-27",
                    "2026-07-26","2026-07-27","2026-06-28","2026-06-29",
                    "2026-06-30","2026-07-01","2026-07-02","2026-07-03",
                    "2026-07-04","2026-07-05",
                    "2026-09-02","2026-09-03","2026-09-04","2026-09-05",
                    "2026-09-06","2026-09-07","2026-09-08","2026-09-09",
                    "2026-11-20","2026-11-21","2026-11-22","2026-11-23",
                    "2026-11-24","2026-11-25","2026-11-26","2026-11-27",
                    "2026-11-28","2026-11-29","2026-11-30","2026-12-01",
                    "2026-12-16","2026-12-17","2026-12-18","2026-12-19",
                    "2026-12-20","2026-12-21","2026-12-22","2026-12-23",
                    "2026-12-24","2026-12-25","2026-12-26","2026-12-27",
                    "2026-12-28","2026-12-29","2026-12-30","2026-12-31")

weeks = data.frame(num = 1:7,
                   days = c("Mon","Tue","Wed","Thu","Fri","Sat","Sun"))

# https://shiny.posit.co/r/getstarted/build-an-app/reactive-flow/ui-inputs.html
# https://shiny.posit.co/

############# Setting up the R shiny format for user inputs ####################
user_inputs <- fluidPage(
  titlePanel("Departure Delay Prediction"),
  setBackgroundColor("#E7F1F5"),
  
  sidebarLayout(
    sidebarPanel(
      style = "background-color: #C3DCE6; border: 1px solid #9CBDCB",
      # Numeric flight inputs, with value set to a default of that variable's mean
      numericInput("CRSElapsedTime", "Scheduled Elapsed Time (min):", 
                   value = 152, min = 1),
      numericInput("airport_crowd", "Airport Crowd Level:", 
                   value = 39, min = 0, step = 1),
      # 24 hour time as shown when booking
      textInput("deptime", "Departure Time (HH:MM):", value = "13:00"), 
      
      # Categorical flight variables
      dateInput("date", "Select a date:", value = Sys.Date()),
      selectInput("Origin", "Origin Airport:",
                  choices = sort(unique(choices$origin_choices))),
      selectInput("Dest", "Destination Airport:",
                  choices = sort(unique(choices$dest_choices))),
      selectInput("Reporting_Airline", "Reporting Airline:",
                  choices = sort(unique(choices$airline_choices))),
      
      # Numeric weather inputs, again we set to their means as default
      numericInput("DEWP", "Dew Point (F):", value = 45),
      numericInput("MAX", "Max Temperature (F):", value = 75),
      numericInput("MIN", "Min Temperature (F):", value = 53),
      numericInput("TEMP", "Average Temperature (F):", value = 63),
      numericInput("STP", "Station Pressure (mb):", value = 976),
      numericInput("SLP", "Sea Level Pressure (mb):", value = 1015),
      numericInput("WDSP", "Mean Wind Speed (kn):", value = 7),
      numericInput("MXSPD", "Max Wind Speed (kn):", value = 14),
      numericInput("VISIB", "Visibility (mi):", value = 9),
      numericInput("PRCP", "Precipitation (in):", value = 0),
      numericInput("SNDP", "Snow Depth (in):", value = 0),
      
      # Binary weather indicators
      selectInput("Rain", "Rain:", choices = c(0,1)),
      selectInput("Thunder", "Thunder:", choices = c(0,1)),
      selectInput("Fog", "Fog:", choices = c(0,1)),
      selectInput("Snow", "Snow:", choices = c(0,1)),
      selectInput("Hail", "Hail:", choices = c(0,1)),
      
      actionButton("predict", "Predict Delay Probability")
    ),
    
    # random forest output 
    mainPanel(
      h3("Predicted Probability of Delay >15 Minutes:"),
      textOutput("prob")
    )
  )
)

server <- function(input, output) {
  
  observeEvent(input$predict, {
    
    ############# Everything else that didn't prompt for user input ##############
    # origin -> Origin, OriginState 
    originstate = str_sub(metadata[metadata$iata_code == input$Origin,]$iso_region, 4)
    lat1 = metadata[metadata$iata_code == input$Origin,]$latitude_deg
    long1 = metadata[metadata$iata_code == input$Origin,]$longitude_deg
    
    # destination -> Dest, DestState, direction, distance
    deststate = str_sub(metadata[metadata$iata_code == input$Dest,]$iso_region, 4)
    lat2 = metadata[metadata$iata_code == input$Dest,]$latitude_deg
    long2 = metadata[metadata$iata_code == input$Dest,]$longitude_deg
    
    direct = deg_to_direction(bearing(c(long1, lat1), c(long2, lat2)))
    
    distance.m = distHaversine(c(long1, lat1), c(long2, lat2))
    distance.mi = conv_unit(distance.m, "m", "mi")
    
    # DepartureTime -> DepTimeBlock
    dep.hour = as.numeric(str_split(input$deptime, ":")[[1]][1])
    if (dep.hour < 6) {
      deptimeblk = "0001-0559"
    } else if (dep.hour < 10) {
      deptimeblk = paste0("0", dep.hour, "00-0", dep.hour, "59")
    } else {
      deptimeblk = paste0(dep.hour, "00-", dep.hour, "59")
    }
    
    # Date -> Month, Quarter, DayofMonth, DayOfWeek, holiday
    date.split = str_split(as.character(input$date), "-")[[1]]
    month = as.numeric(date.split[2])
    dayofmonth = as.numeric(date.split[3])
    quarter = ceiling(month / 3)
    
    weekday = weekdays(input$date, abbreviate = TRUE)
    dayofweek = weeks[weeks$days == weekday,]$num

    hol = ifelse(as.character(input$date) %in% holiday_period, 1, 0)
    
    ############# combining the data from the inputs and the calculated data #######
    new.data <- data.frame(
      Quarter = quarter,
      Month = month,
      DayofMonth = dayofmonth,
      DayOfWeek = dayofweek,
      Reporting_Airline = input$Reporting_Airline,
      Origin = input$Origin,
      OriginState = originstate,
      Dest = input$Dest,
      DestState = deststate,
      DepTimeBlk = deptimeblk,
      CRSElapsedTime = input$CRSElapsedTime,
      Distance = distance.mi,
      direction = direct,
      airport_crowd = input$airport_crowd,
      TEMP = input$TEMP,
      DEWP = input$DEWP,
      SLP = input$SLP,
      STP = input$STP,
      VISIB = input$VISIB,
      WDSP = input$WDSP,
      MXSPD = input$MXSPD,
      MAX = input$MAX,
      MIN = input$MIN,
      PRCP = input$PRCP,
      SNDP = input$SNDP,
      Fog = input$Fog,
      Rain = input$Rain,
      Snow = input$Snow,
      Hail = input$Hail,
      Thunder = input$Thunder,
      holiday = hol
    )
    
    # Predict the probability of delay >15 mins
    pred <- predict(RF_model, data = new.data)
    prob <- pred$predictions[,2]
    output$prob <- renderText(paste(round(prob, 4), "✈️"))
  })
}
shinyApp(ui = user_inputs, server = server)
