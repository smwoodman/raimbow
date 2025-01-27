#fuel prices

#-------------------------------------------------------------------------------------------------

library(tidyverse)
library(sf)
library(viridis)
library(here)
library(rnaturalearth)
library(fasterize)
library(sp)
library(magrittr)
library(raster)
select <- dplyr::select
library(scales)
library(gridExtra)
library(nngeo)
library(scales)
library(stringr)
library(lubridate)

#-------------------------------------------------------------------------------------------------

#fuel price data is form here: https://www.psmfc.org/efin/data/fuel.html#Data

#fuel prices only checked once month, so can't get separate values for each half month step
#need to apply each month's price to both half month steps

#for now downloaded OR and WA
fuel_OR <- read_csv(here('DCRB_sdmTMB', 'data', 'fuel','fuelor.csv'))
fuel_WA <- read_csv(here('DCRB_sdmTMB', 'data', 'fuel','fuelwa.csv'))

fuel_or_wa_raw <- rbind(fuel_OR, fuel_WA)

fuel_or_wa <- fuel_or_wa_raw %>% 
  #drop out some useless years
  filter(YEAR %in% c(2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020))

fuel_or_wa_v2 <- transform(fuel_or_wa, month_name = month.name[MONTH])

fuel_or_wa_v3 <- fuel_or_wa_v2 %>% 
  mutate(season_start = ifelse(MONTH == 12, YEAR, YEAR-1)) %>% 
  mutate(season_end = ifelse(MONTH == 12, YEAR+1, YEAR)) %>% 
  mutate(season = paste0(season_start,"-",season_end)) %>% 
  select(-season_start, -season_end, -notes) 

# if pricettl and pricegal are 0, they are actually NA, no info was available
fuel_or_wa_v4 <- fuel_or_wa_v3 %>% 
  mutate_at(c('pricettl','pricegal'), ~na_if(., 0))
  
#for each ports where fuel price info collected, assign PacFIn port group code (see e.g. distance to port script)
unique(fuel_or_wa_v4$portname)
#port name                port group
# "Astoria"               CLO
# "Brookings"             BRA
# "Florence"              CBA
# "Gold Beach"            BRA
# "Newport"               NPA
# "Winchester Bay"        CBA
# "Tillamook/Garabaldi"   TLA
# "Anacortes"             NPS
# "Bellingham Bay"        NPS
# "Blaine"                NPS
# "Everett"               SPS
# "Ilwaco/Chinook"        CLW
# "Neah Bay"              NPS
# "Olympia"               SPS
# "Port Angeles"          NPS
# "Seattle"               SPS
# "Shelton"               SPS
# "Tacoma"                SPS
# "Port Townsend"         NPS
# "West Port"             CWA

fuel_or_wa_v5 <- fuel_or_wa_v4 %>% 
  mutate(PACFIN_GROUP_PORT_CODE = case_when(
    portname %in% c('Brookings','Gold Beach') ~ 'BRA',
    portname %in% c('Florence','Winchester Bay') ~ 'CBA',
    portname %in% c('Astoria') ~ 'CLO',
    portname %in% c('Ilwaco/Chinook') ~ 'CLW',
    portname %in% c('West Port') ~ 'CWA',
    portname %in% c('Newport') ~ 'NPA',
    portname %in% c('Anacortes','Bellingham Bay','Blaine', 'Neah Bay','Port Angeles','Port Townsend') ~ 'NPS',
    portname %in% c('Everett','Olympia','Seattle','Shelton', 'Tacoma') ~ 'SPS',
    portname %in% c('Tillamook/Garabaldi') ~ 'TLA'
  ))



#find average fuel price within each month as can't do half month step)
#for each port group (see port grouping e.g. herehttps://www.psmfc.org/efin/docs/2020FuelPriceReport.pdf -- did it based on PacFin see dist to port code) 
#that data is available
fuel_price_month_step_portgroup <- fuel_or_wa_v5 %>% 
  group_by(season, month_name, PACFIN_GROUP_PORT_CODE) %>% #don't include dock code here ##STATE, port, portname
  summarise(
            #avg_pricettl = mean(pricettl, na.rm = TRUE),
            avg_pricegal = mean(pricegal, na.rm = TRUE)
            )

#25 cases (month and port combos)  where no fuel price available
#TLA port group the one that mostly has NA - may have stopped collecting fuel data from there
#use state average? or nearby port group average? --> nearby portgroup as state can be very variable
#there are more NAs in the avg_pricettl variable, so probably better to just stick to avg_pricegal

fuel_price_month_step_portgroup_noNAs <- fuel_price_month_step_portgroup %>% 
  filter(!is.na(avg_pricegal)) 

fuel_price_month_step_portgroup_NAs <- fuel_price_month_step_portgroup %>% 
  filter(is.na(avg_pricegal)) %>% 
  select(-avg_pricegal) %>% 
  mutate(PACFIN_GROUP_PORT_CODE2 = case_when(
    PACFIN_GROUP_PORT_CODE == 'BRA' ~ 'CBA',
    PACFIN_GROUP_PORT_CODE == 'CBA' ~ 'NPA',
    PACFIN_GROUP_PORT_CODE == 'CLO' ~ 'CLW',
    PACFIN_GROUP_PORT_CODE == 'CLW' ~ 'CLO',
    PACFIN_GROUP_PORT_CODE == 'CWA' ~ 'CLW',
    PACFIN_GROUP_PORT_CODE == 'NPA' ~ 'TLA',
    PACFIN_GROUP_PORT_CODE == 'NPS' ~ 'SPS',
    PACFIN_GROUP_PORT_CODE == 'SPS' ~ 'NPA',
    PACFIN_GROUP_PORT_CODE == 'TLA' ~ 'CLO'
  )) %>% inner_join(fuel_price_month_step_portgroup, by=c("PACFIN_GROUP_PORT_CODE2"= "PACFIN_GROUP_PORT_CODE", "season", "month_name")) %>% 
  #one more case of NA as in the same month (May 2020) both CLO and CLW don't have fuel price
  mutate(avg_pricegal = case_when(
    is.na(avg_pricegal) & PACFIN_GROUP_PORT_CODE == 'CLO' ~ 1.49,
    is.na(avg_pricegal) & PACFIN_GROUP_PORT_CODE == 'CLW' ~ 1.19,
    !is.na(avg_pricegal) ~ avg_pricegal 
  )) %>% 
  select(-PACFIN_GROUP_PORT_CODE2)

fuel_price_month_step_portgroup_fixed <- rbind(fuel_price_month_step_portgroup_noNAs,fuel_price_month_step_portgroup_NAs)





### go to bottom to do fuel pricing with the same proportion of pots to port groups as with dist to port







##OLD
# #read in proportion of pots to port groups by half month
# #re-did this using landing date based half month - outputs are in folder 'v2'
# proportion_pots_to_port_group_by_halfmonth <- read_rds(here::here('DCRB_sdmTMB', 'data', "proportion_pots_to_port_group_by_halfmonth_based_on_landing_date.rds")) %>% 
#   #this needs a column for month as fuel price is by month not half-month
#   mutate(half_month_dummy = half_month_landing_date) %>% 
#   separate(col=half_month_dummy, into=c('month_name', 'period'), sep='_') %>% 
#   select(-period)
# 
# 
# #join fuel price to df with proportion of pots from grid to port group
# proportion_pots_to_port_group_by_halfmonth_fuel_price <- proportion_pots_to_port_group_by_halfmonth %>% 
#   left_join(fuel_price_month_step_portgroup_fixed, by=c('season', 'month_name','PACFIN_GROUP_PORT_CODE'))
# #some NAs - e.g. BRA - Brooking dropped from fuel price survey in 2009  & Gold Beach stopped selling diesel in 2012
# #same as above, if NA, use price of that month from closest port group
# 
# proportion_pots_to_port_group_by_halfmonth_fuel_price_noNAs <- proportion_pots_to_port_group_by_halfmonth_fuel_price %>% 
#   filter(!is.na(avg_pricegal)) 
# 
# proportion_pots_to_port_group_by_halfmonth_fuel_price_NAs <- proportion_pots_to_port_group_by_halfmonth_fuel_price %>% 
#   filter(is.na(avg_pricegal)) %>% 
#   #drop couple columns to avoid repeating columns in left_join
#   select(-avg_pricegal) %>% 
#   mutate(PACFIN_GROUP_PORT_CODE2 = case_when(
#     PACFIN_GROUP_PORT_CODE == 'BRA' ~ 'CBA',
#     PACFIN_GROUP_PORT_CODE == 'CBA' ~ 'NPA',
#     PACFIN_GROUP_PORT_CODE == 'CLO' ~ 'CLW',
#     PACFIN_GROUP_PORT_CODE == 'CLW' ~ 'CLO',
#     PACFIN_GROUP_PORT_CODE == 'CWA' ~ 'CLW',
#     PACFIN_GROUP_PORT_CODE == 'NPA' ~ 'TLA',
#     PACFIN_GROUP_PORT_CODE == 'NPS' ~ 'SPS',
#     PACFIN_GROUP_PORT_CODE == 'SPS' ~ 'NPA',
#     PACFIN_GROUP_PORT_CODE == 'TLA' ~ 'CLO'
#   )) %>% 
#   inner_join(fuel_price_month_step_portgroup_fixed, by=c("PACFIN_GROUP_PORT_CODE2"= "PACFIN_GROUP_PORT_CODE", "season", "month_name")) %>% 
#   select(-PACFIN_GROUP_PORT_CODE2)
# 
# 
# proportion_pots_to_port_group_by_halfmonth_fuel_price_fixed <- rbind(proportion_pots_to_port_group_by_halfmonth_fuel_price_noNAs,proportion_pots_to_port_group_by_halfmonth_fuel_price_NAs)
# 
# 
# 
# 
# #--------------------------------------------
# #adjust for inflation, all $ in dollars of that specific year etc
# 
# cpi_raw <- read_csv(here('wdfw', 'data', 'cpi_2021.csv'),col_types='idc')
# 
# # add a conversion factor to 2020 $$
# cpi <- cpi_raw %>% 
#   mutate(convert2020=1/(annual_average/258.8)) %>% 
#   filter(year>2006) %>% 
#   filter(year<2021) %>% 
#   dplyr::select(year,convert2020) 
# 
# 
# #this df needs a 'year' column so can join with cpi
# proportion_pots_to_port_group_by_halfmonth_fuel_price_fixed_v2 <- proportion_pots_to_port_group_by_halfmonth_fuel_price_fixed %>% 
#   mutate(season2 = season) %>% 
#   separate(season2, into = c("season_start", "season_end"), sep = "-") %>% 
#   mutate(year = ifelse(month_name == "December", season_start, season_end)) %>% 
#   select(-season_start, -season_end) 
# 
# proportion_pots_to_port_group_by_halfmonth_fuel_price_fixed_v2$year <- as.numeric(proportion_pots_to_port_group_by_halfmonth_fuel_price_fixed_v2$year)
# 
# 
# proportion_pots_to_port_group_by_halfmonth_fuel_price_fixed_adj_inf <- proportion_pots_to_port_group_by_halfmonth_fuel_price_fixed_v2 %>% 
#   left_join(cpi, by = c('year')) %>% 
#   mutate(avg_pricegal_adj = avg_pricegal * convert2020) %>% 
#   #drop columns no longer needed
#   select(-(month_name:convert2020))
# 
# 
# #--------------------------------------------------------
# #weight port group specific fuel price by proportion of pots in grid
# 
# weighted_fuel_price <- proportion_pots_to_port_group_by_halfmonth_fuel_price_fixed_adj_inf %>% 
#   mutate(price_multiply_prop = avg_pricegal_adj * prop_pots_to_port_group) %>% 
#   group_by(GRID5KM_ID, season, half_month_landing_date) %>% 
#   summarise(weighted_fuel_pricegal = sum(price_multiply_prop)) %>% 
#   rename(half_month = half_month_landing_date)
# 
# weighted_fuel_price$half_month <- as.factor(weighted_fuel_price$half_month)
# 
# #------------------------------------------------
# ## THIS IS ACTUALLY NOT NEEDED
# # #join to grid to see if all study area grids have fuel price
# # #in each half-month step
# # 
# # study_area <- read_rds(here::here('DCRB_sdmTMB','data','study_area_grids_with_all_season_halfmonth_combos_sf.rds')) %>% 
# #   select(-NGDC_GRID,-AREA)
# # 
# # lvls <- sort(unique(c(levels(weighted_fuel_price$half_month), 
# #                       levels(study_area$half_month))))
# # weighted_fuel_price$half_month <- factor(weighted_fuel_price$half_month, levels=lvls)
# # study_area$half_month <- factor(study_area$half_month, levels=lvls)
# # 
# # 
# # study_area_grids_fuelprice <- study_area %>% 
# #   left_join(weighted_fuel_price, by=c('GRID5KM_ID', 'season', 'half_month')) %>%
# #   mutate(half_month_dummy=half_month) %>% 
# #   separate(col=half_month_dummy, into=c('month_name', 'period'), sep='_') %>% 
# #   select(-period)
# 
# 
# #------------------------------------------------
# ## THIS IS ACTUALLY NOT NEEDED
# # #the rasters 
# # library(fasterize)
# # 
# # subset <- study_area_grids_fuelprice %>% 
# #   filter(season=="2019-2020", month_name=="December")
# # 
# # fuel_raster_20192020_December <- fasterize(subset,
# #                          raster = raster(subset,res=5000,
# #                                          crs=crs(subset)),
# #                          field="weighted_fuel_pricegal")
# # 
# # plot(fuel_raster_20192020_December)
# # 
# # writeRaster(fuel_raster_20192020_December,'fuel_raster_20192020_December.tif',options=c('TFW=YES'))
# # 
# # #get dist to port into a raster
# # #bring to GIS
# # #use Raster --> Analysis --> fill nodata to interpolate
# # #use the interpolated value in grids that were NA 9had no point data)
# # 
# 
# #--------------------------
# ## THIS IS ACTUALLY NOT NEEDED
# # #try IDW in R -- https://rpubs.com/Dr_Gurpreet/interpolation_idw_R
# # 
# # library(spatstat)
# # library(rosm)
# # 
# # # testtest <- study_area %>% select(GRID5KM_ID,geometry())
# # # study_area_raster <- fasterize(testtest ,
# # #                      raster = raster(testtest ,res=5000,
# # #                      crs=crs(testtest )),
# # #                      field="GRID5KM_ID")
# # # extract_bbox(study_area_raster)
# # # #min        max
# # # #x -125.41597 -123.38897
# # # #y   41.96825   48.52388
# # 
# # 
# # #create observation window
# # obs_window <- owin(xrange=c(-125.41597,-123.38897), yrange=c(41.96825,48.52388))
# # 
# # #get point observations
# # #weighted_fuel_price
# # grid_centroids <- read_csv(here::here('DCRB_sdmTMB','data','dist to ports','grid_centroids.csv'))
# # 
# # weighted_fuel_price_points <- weighted_fuel_price %>% 
# #   left_join(grid_centroids) %>%
# #   mutate(half_month_dummy=half_month) %>% 
# #   separate(col=half_month_dummy, into=c('month_name', 'period'), sep='_') %>% 
# #   select(-period)
# # 
# # # weighted_fuel_price_points_sf <- st_as_sf(weighted_fuel_price_points, 
# # #                                           coords = c("grd_x", "grd_y"),
# # #                                           crs = 4326
# # #                                           )
# # 
# # 
# # subset <- weighted_fuel_price_points %>% 
# #   filter(season=="2019-2020", half_month=="December_2")
# #   
# # 
# # #create point pattern object
# # ppp_test <- ppp(subset$grd_x,
# #                 subset$grd_y,
# #                 marks=subset$weighted_fuel_pricegal,
# #                 window=obs_window)
# # 
# # #idw object
# # idw_test <- idw(ppp_test, power=0.05, at="pixels")
# # idw_test_points <- idw(ppp_test, power=0.05, at="points")
# # 
# # #visualisation of interpolated results
# # plot(idw_test,
# #      col=heat.colors(20), 
# #      main="Interpolated based on IDW method \n (Power = 0.05)") 
# # 
# # plot(idw_test_points, 
# #      col=heat.colors(64))
# 
# #-------------------------
# #https://www.youtube.com/watch?v=9whoSguh7Z4
# 
# #specify points where want to estimate/interpolate the variable (the unknown points)
# # that would be the grid centroids
# grid_centroids <- read_csv(here::here('DCRB_sdmTMB','data','dist to ports','grid_centroids.csv'))
# grid_centroids_sf <- st_as_sf(grid_centroids, 
#                                            coords = c("grd_x", "grd_y"),
#                                            crs = 4326
#                                            )
# plot(grid_centroids_sf)
# 
# 
# library(gstat)
# 
# 
# #data to be used for interpolation
# weighted_fuel_price_points <- weighted_fuel_price %>% 
#      left_join(grid_centroids) 
#   
# weighted_fuel_price_points_sf <- st_as_sf(weighted_fuel_price_points, 
#                                            coords = c("grd_x", "grd_y"),
#                                            crs = 4326
#                                            )
# 
# 
# 
# ##This is where need to loop through all season and half-month combos
# subset <- weighted_fuel_price_points_sf %>% 
#   filter(season=="2019-2020", half_month=="September_1")
# plot(subset)
# 
# 
# #locations specifies the dataset. idp = alpha, how important are we going to make distance
# test_idw <- gstat::idw(formula=weighted_fuel_pricegal~1, 
#                        locations = subset, 
#                        newdata=grid_centroids_sf, 
#                        idp =1) #idp default is 1
# #var1.pred = the interpolated value at the point
# #for those points that were the input, the interpolated var1.pred is exactly the same as the input value
# 
# 
# test_join <- st_join(test_idw, grid_centroids_sf) %>% 
#   #after this don't need geometry column, only grid ID
#   #and also don't need var1.var column
#   select(var1.pred, GRID5KM_ID) %>% 
#   st_set_geometry(NULL) %>% 
#   rename(weighted_fuel_pricegal = var1.pred) %>% 
#   #but do need columns denoting season and half-month - these would need to be added here
#   mutate(season = "2019-2020", half_month="September_1") %>% 
#   #reorder columns
#   select(GRID5KM_ID, season, half_month, weighted_fuel_pricegal)
# 
# #now would just need to loop this heaps of times....
# #start a dummy df into which rbind all idw data (at each season - half-month combo)?
# 
# # columns <- c("GRID5KM_ID", "season", "half_month", "weighted_fuel_pricegal")
# # dummy_df <- data.frame(matrix(nrow = 0, ncol = length(columns))) 
# # colnames(dummy_df) = columns
# # df_fuel_price <- dummy_df 
# 
# df_fuel_price <- df_fuel_price %>% 
#   rbind(test_join)
# 
# unique(df_fuel_price$half_month)
# 
# 
# 
# 
# #note that e.g. 2007-2008, 2008-2009 is OR data only so ends in August_1 (fishery closes 14 Aug); 
# #2012-2013, 2013-2014 starts late (December_2)
# #2014-2015 doesn't have August_2, but has August_1 and September_1
# #2015-2016 starts January_1, 2017-2018 starts January_2, 2018-2019 starts January_1, matches data from DFWs
# 
# 
# #interpolated_fuel_price_2019_2020 <-  df_fuel_price
# #nrow(interpolated_fuel_price_2019_2020)
# #write_rds(interpolated_fuel_price_2019_2020,here::here('DCRB_sdmTMB', 'data', 'fuel', 'v2', "interpolated_fuel_price_2019_2020.rds"))
# 
# 
# #------------------------------
# #2014-2015 season had no pots in August_2, but as fishery (in WA) was open
# #we need fuel prices for grid cells in that month for the presence/absence model
# #note that don't want to run this again and duplicate August_2
# interpolated_fuel_price_2014_2015 <- read_rds(here::here('DCRB_sdmTMB', 'data', "fuel",'v2',"interpolated_fuel_price_2014_2015.rds"))
# #interpolated_fuel_price_2014_2015
# 
# interpolated_fuel_price_2014_2015_august1_september1 <- interpolated_fuel_price_2014_2015 %>% 
#   filter(half_month=='August_1' | half_month=='September_1') %>% 
#   group_by(GRID5KM_ID) %>% 
#   summarise(weighted_fuel_pricegal = mean(weighted_fuel_pricegal)) %>% 
#   mutate(season = "2014-2015", half_month = "August_2") %>% 
#   select(GRID5KM_ID, season, half_month, weighted_fuel_pricegal) %>% 
#   ungroup()
#   
# interpolated_fuel_price_2014_2015 <- rbind(interpolated_fuel_price_2014_2015, interpolated_fuel_price_2014_2015_august1_september1)
# #write_rds(interpolated_fuel_price_2014_2015,here::here('DCRB_sdmTMB', 'data', "fuel",'v2', "interpolated_fuel_price_2014_2015.rds"))
# 
# #------------------------------
# #2013-2014 needs fuel price for December_1 -- use data for December_2
# interpolated_fuel_price_2013_2014
# 
# interpolated_fuel_price_2013_2014_december_fix <- interpolated_fuel_price_2013_2014 %>% 
#   filter(half_month=="December_2") %>% 
#   mutate(half_month = str_replace(half_month, "December_2", "December_1"))
# 
# interpolated_fuel_price_2013_2014 <- rbind(interpolated_fuel_price_2013_2014, interpolated_fuel_price_2013_2014_december_fix)
# #write_rds(interpolated_fuel_price_2013_2014,here::here('DCRB_sdmTMB', 'data', "fuel",'v2', "interpolated_fuel_price_2013_2014.rds"))
# 
# 
# #2017-2018 needs fuel price for January_1 -- use data for January_2
# interpolated_fuel_price_2017_2018
# 
# interpolated_fuel_price_2017_2018_january_fix <- interpolated_fuel_price_2017_2018 %>% 
#   filter(half_month=="January_2") %>% 
#   mutate(half_month = str_replace(half_month, "January_2", "January_1"))
# 
# interpolated_fuel_price_2017_2018 <- rbind(interpolated_fuel_price_2017_2018, interpolated_fuel_price_2017_2018_january_fix)
# #write_rds(interpolated_fuel_price_2017_2018,here::here('DCRB_sdmTMB', 'data', "fuel",'v2', "interpolated_fuel_price_2017_2018.rds"))
# 
# #------------------------------
#  
# interpolated_fuel_price_all <- rbind(interpolated_fuel_price_2007_2008,
#                                      interpolated_fuel_price_2008_2009,
#                                      interpolated_fuel_price_2009_2010,
#                                      interpolated_fuel_price_2010_2011,
#                                      interpolated_fuel_price_2011_2012,
#                                      interpolated_fuel_price_2012_2013,
#                                      interpolated_fuel_price_2013_2014,
#                                      interpolated_fuel_price_2014_2015,
#                                      interpolated_fuel_price_2015_2016,
#                                      interpolated_fuel_price_2016_2017,
#                                      interpolated_fuel_price_2017_2018,
#                                      interpolated_fuel_price_2018_2019,
#                                      interpolated_fuel_price_2019_2020
#                                      )
# 
# #write_rds(interpolated_fuel_price_all,here::here('DCRB_sdmTMB', 'data', "fuel",'v2', "interpolated_fuel_price_all.rds"))
# 
# #------------------------------
# 
# 
# 
# study_area_grids_with_all_season_halfmonth_combos_wind_SST_fixed_depth_faults_canyon_escarp_portdist <- read_rds(here::here('DCRB_sdmTMB', 'data', "study_area_grids_with_all_season_halfmonth_combos_wind_SST_fixed_depth_faults_canyon_escarp_portdist_IDWinR.rds"))
# 
# 
# study_area_grids_with_all_season_halfmonth_combos_wind_SST_fixed_depth_faults_canyon_escarp_portdist_fuel <- study_area_grids_with_all_season_halfmonth_combos_wind_SST_fixed_depth_faults_canyon_escarp_portdist %>% 
#   left_join(interpolated_fuel_price_all, by=c('GRID5KM_ID', 'season', 'half_month'))
# #the cases where grid has NA for fuel price should be cases where grids were closed (season closures etc)
# #these should get removed when get around to dealing with open/closed areas (grids)
# #not all NAs are during closed periods - so needs fixing
# #discrepancy is likely due to half_monthly by landing day or Set Date
# 
# #df_NAs <- study_area_grids_with_all_season_halfmonth_combos_wind_SST_fixed_depth_faults_canyon_escarp_portdist_fuel %>% 
# #  filter(is.na(weighted_fuel_pricegal))
# #df_noNAs <- study_area_grids_with_all_season_halfmonth_combos_wind_SST_fixed_depth_faults_canyon_escarp_portdist_fuel %>% 
# #  filter(!is.na(weighted_fuel_pricegal))
# 
# #distinct_season_halfmonth_with_NAs <- df_NAs %>% 
# #  distinct(season, half_month)
# #season    half_month 
# #2007-2008 August_2   
# #2007-2008 September_1
# #2008-2009 August_2   
# #2008-2009 September_1
# #2012-2013 December_1 
# #2013-2014 December_1 
# #2015-2016 December_1 
# #2015-2016 December_2 
# #2016-2017 December_1 
# #2017-2018 December_1 
# #2017-2018 December_2 
# #2017-2018 January_1  
# #2018-2019 December_1 
# #2018-2019 December_2 
# #2019-2020 December_1
# 
# #we can ignore 2007-2008 and 2008-2009 as those will get dropped from the analysis
# #some other cases are when fishery fully closed, so fix only times when fishery is open
# #actually only 2 specific cases when fishery open but NAs for fuel price
# # season    half_month
# # 2013-2014 December_1
# # 2017-2018 January_1 
# #fill these with the second half of that month (fuel price is monthly)
# #code for this is above
# 
# 
# #write_rds(study_area_grids_with_all_season_halfmonth_combos_wind_SST_fixed_depth_faults_canyon_escarp_portdist_fuel,here::here('DCRB_sdmTMB', 'data', "study_area_grids_with_all_season_halfmonth_combos_wind_SST_fixed_depth_faults_canyon_escarp_portdist_fuel.rds"))
# 









### do fuel pricing with the same proportion of pots to port groups as with dist to port

#prop pots to port group done across full data set
proportion_pots_to_port_group <- read_rds(here::here('DCRB_sdmTMB', 'data', "proportion_pots_to_port_group_across_all_data.rds")) %>% 
  ungroup()
#but if join that to fuel prices, end up missing some cases where e.g. fuel surveys ended
#proportion_pots_to_port_group is missing 2 grids: 121931 122578
#for 121931 use prop pots to port from 121933: CWA = 9.644169e-01, NPS = 3.558309e-02
#for 122578 use prop pots to port from 122579: CLW = 0.2112838131, CWA = 0.7692591820

df_fix_NAs <- data.frame (GRID5KM_ID  = c(121931,121931,122578,122578),
                          PACFIN_GROUP_PORT_CODE = c("CWA", "NPS", "CLW", "CWA"),
                          prop_pots_to_port_group = c(9.644169e-01, 3.558309e-02, 0.2112838131, 0.7692591820)
                          )

proportion_pots_to_port_group <- rbind(proportion_pots_to_port_group, df_fix_NAs)





restricted_study_area <- read_sf(here::here('DCRB_sdmTMB','data', 'restricted_study_area.shp')) %>% 
  st_set_geometry(NULL) 

df_full_final_raw <- read_rds(here::here('DCRB_sdmTMB', 'data','df_full_final_raw.rds')) 
restricted_study_area_grids <- sort(unique(restricted_study_area$GRID5KM_ID))
df_full_final_in_restricted_study_area <- df_full_final_raw %>% filter(GRID5KM_ID %in% restricted_study_area_grids) 




####test
proportion_pots_to_port_group_restricted_study_area <- df_full_final_in_restricted_study_area %>% 
  left_join(proportion_pots_to_port_group, by=c('GRID5KM_ID'))

proportion_pots_to_port_group_restricted_study_area_fuel_price  <- proportion_pots_to_port_group_restricted_study_area %>% 
  left_join(fuel_price_month_step_portgroup_fixed, by=c('season', 'month_name', 'PACFIN_GROUP_PORT_CODE'))


proportion_pots_to_port_group_restricted_study_area_fuel_price_noNAs <- proportion_pots_to_port_group_restricted_study_area_fuel_price %>%  
  filter(!is.na(avg_pricegal)) 

proportion_pots_to_port_group_restricted_study_area_fuel_price_NAs <- proportion_pots_to_port_group_restricted_study_area_fuel_price %>% 
  filter(is.na(avg_pricegal)) %>% 
  select( -avg_pricegal) %>% 
  mutate(PACFIN_GROUP_PORT_CODE2 = case_when(
    PACFIN_GROUP_PORT_CODE == 'BRA' ~ 'CBA',
    PACFIN_GROUP_PORT_CODE == 'CBA' ~ 'NPA',
    PACFIN_GROUP_PORT_CODE == 'CLO' ~ 'CLW',
    PACFIN_GROUP_PORT_CODE == 'CLW' ~ 'CLO',
    PACFIN_GROUP_PORT_CODE == 'CWA' ~ 'CLW',
    PACFIN_GROUP_PORT_CODE == 'NPA' ~ 'TLA',
    PACFIN_GROUP_PORT_CODE == 'NPS' ~ 'SPS',
    PACFIN_GROUP_PORT_CODE == 'SPS' ~ 'NPA',
    PACFIN_GROUP_PORT_CODE == 'TLA' ~ 'CLO'
  )) %>% 
  inner_join(fuel_price_month_step_portgroup_fixed, by=c("PACFIN_GROUP_PORT_CODE2"= "PACFIN_GROUP_PORT_CODE", "season", "month_name")) %>% 
  select(-PACFIN_GROUP_PORT_CODE2)

proportion_pots_to_port_group_fuel_price_fixed <- rbind(proportion_pots_to_port_group_restricted_study_area_fuel_price_noNAs, proportion_pots_to_port_group_restricted_study_area_fuel_price_NAs)



cpi_raw <- read_csv(here('wdfw', 'data', 'cpi_2021.csv'),col_types='idc')

# add a conversion factor to 2020 $$
cpi <- cpi_raw %>% 
  mutate(convert2020=1/(annual_average/258.8)) %>% 
  filter(year>2006) %>% 
  filter(year<2021) %>% 
  dplyr::select(year,convert2020)


proportion_pots_to_port_group_fuel_price_fixed_v2 <- proportion_pots_to_port_group_fuel_price_fixed %>% 
  mutate(season2 = season) %>% 
  separate(season2, into = c("season_start", "season_end"), sep = "-") %>% 
  mutate(year = ifelse(month_name == "December", season_start, season_end)) %>% 
  select(-season_start, -season_end)

proportion_pots_to_port_group_fuel_price_fixed_v2$year <- as.numeric(proportion_pots_to_port_group_fuel_price_fixed_v2$year)

proportion_pots_to_port_group_fuel_price_adj_inf <- proportion_pots_to_port_group_fuel_price_fixed_v2 %>% 
  left_join(cpi, by = c('year')) %>% 
  mutate(avg_pricegal_adj = avg_pricegal * convert2020) %>% 
  #drop columns no longer needed
  select(- avg_pricegal, -year, - convert2020) #%>% 
  #distinct #add a distinct command to remove duplication



#weight port group specific fuel price by proportion of pots in grid

weighted_fuel_price <- proportion_pots_to_port_group_fuel_price_adj_inf    %>% 
  ungroup() %>% 
  mutate(price_multiply_prop = avg_pricegal_adj * prop_pots_to_port_group) %>% 
  group_by(GRID5KM_ID, season, half_month) %>% 
  summarise(weighted_fuel_pricegal = sum(price_multiply_prop)) %>% 
  rename(weighted_fuel_pricegal_v2 = weighted_fuel_pricegal)


write_rds(weighted_fuel_price,here::here('DCRB_sdmTMB', 'data',  "weighted_fuel_price_fix.rds"))


#this part will be done in prep for sdmTMb script
# testtest7 <- df_full_final_in_restricted_study_area %>% left_join(weighted_fuel_price)
# View(testtest7 %>% filter(open_closed=="open"))

####









#------------------------------
#------------------------------
# #can also download and use monthly state fuel prices
# fuel_state_averages_raw <- read_csv(here('DCRB_sdmTMB', 'data', 'fuel','state_averages.csv'))
# 
# fuel_state_averages <- fuel_state_averages_raw %>% 
#   #drop out alaska
#   filter(STATE != 'AK') %>% 
#   #drop out some useless years
#   filter(YEAR %in% c(2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020))
# 
# fuel_state_averages_v2 <- transform(fuel_state_averages, month_name = month.name[MONTH])
# 
# fuel_state_averages_v3 <- fuel_state_averages_v2 %>% 
#   mutate(season_start = ifelse(MONTH == 12, YEAR, YEAR-1)) %>% 
#   mutate(season_end = ifelse(MONTH == 12, YEAR+1, YEAR)) %>% 
#   mutate(season = paste0(season_start,"-",season_end)) %>% 
#   select(-season_start, -season_end) 
# 






