# raimbow-whaleRisk

<!-- badges: start -->
<!-- badges: end -->

This repository contains code for calculating, evaluating, and visualizing whale risk for RAIMBOW project

## File descriptions

<!-- section break -->
### Analysis files (markdown files)
* Entanglement_gridID.Rmd: Determine grid cell values, for report location and gear set county, for CA DC humpback entanglements with known gear set/time.

* Entanglement_report_mnpred.Rmd: Compare entnglement report locations with humpback predictions for Karin.

* Entanglements_timeseries.Rmd: Examine relationship between risk values and entanglement reports, including using lookback window.

* Mn_multipanel_prey_compare.Rmd: Creating a multipanel of Mn predictions for Karin to compare with multipanel prey plots from Santora et al 2020. 

* Whale_risk.Rmd: Calculates (humpback) whale risk of entanglement for each grid cell as: humpback density * fishing measure. This file then saves the humpback (density), fishing (total sum), and risk (density) values as an RDATA file for use in subsequent files.

* Whale_risk_timeseries.Rmd: Using RDATA file generated by Whale_risk.Rmd, summarizes and plots humpback whale risk of entanglement by region over time. Note that file has been updated to use 'long' data to make future adaptations/code adjustments easier

* Whale_risk_timeseries_base.Rmd: A look at how risk would change if all humpback or fishing values were 'baseline' values, meaning the average of the values for the 2009-2010 to 2012-2013 fishing seasons.

* Whale_risk_maps.Rmd: Generates heat maps of data saved in Whale_risk.Rmd.

*_county_: Analyses (described above) but using CA counties instead of CA regions.

<!-- section break -->
### Analysis files (other)
* JS_OceanVisions: Code used to create plots of Jameal's April 2019 OceanVisions presentation

* VMS_nonconfidential_duplicates.R: Identify duplicate rows in CA-only, non-confidential data

<!-- section break -->
### Helper files
* plot_raimbow.R: Functions for plotting objects (specifically maps); functions fairly specific to raimbow analyses

* User_script_local.R: Script for determining whom is running the code (user info used to set appropriate file paths); sourced in relevant files

* Whale_risk_timeseries_funcs.R: Functions for creating time series plots.

* whalepreds_aggregate: Summarize whale predictions by specified time interval. Do not edit; any edits should be done in [the whale-model-prep repository](https://github.com/smwoodman/whale-model-prep) and copied over
