# Fire-wise landscapes — the landscapes used to FIT the spread model.
#
# One landscape per focal fire, built from that fire's GEE export. Besides the
# spread predictors, each one carries the fire-wise data the fit needs: the
# ignition point and the observed burned area. (The fire's FWI is fire-level
# too, but it travels in the fires table read by spread/hierarchical_fit.R, not
# inside the landscape.)
#
# Landscapes to *simulate* new fires — regional tiles and PNNH, which have no
# ignition point and no observed fire — are built by landscapes_simulation.R.
# Both scripts share the recipe in R/landscape_functions.R.
#
# Two stages, toggled below:
#   1. export each fire's elevation and run WindNinja over it (slow, ~1 min per
#      fire; only needed to regenerate the wind layers from scratch);
#   2. build and save the landscapes.

library(terra)
library(tidyverse)
library(lubridate)
library(FireSpread)    # land_cube
source(file.path("R", "config.R"))
source(file.path("R", "flammability_indices_functions.R"))  # vfi_calc, tfi_calc
source(file.path("R", "landscape_functions.R"))

# Stages to run
do_windninja <- FALSE   # TRUE only to regenerate the wind layers
do_landscapes <- TRUE

# WindNinja settings for focal fires. Fire-sized DEMs fit a 90 m mesh; the
# region-sized ones in landscapes_simulation.R do not.
wn_speed <- 4           # m/s, ~ the regional average (TerraClimate)
wn_mesh <- 90           # m
wn_threads <- 15

gee_dir <- file.path("data", "focal_fires", "raw_gee")
windninja_dir <- config$windninja_dir
out_dir <- file.path("data", "focal_fires", "landscapes")


# Fires and their raw images ----------------------------------------------

fnames <- list.files(gee_dir, pattern = "\\.tif$")
fire_ids <- sub("^fire_data_raw_", "", tools::file_path_sans_ext(fnames))
n_fires <- length(fire_ids)

# Raw GEE stacks. terra keeps these on disk, so holding all 57 is cheap.
raw_imgs <- lapply(file.path(gee_dir, fnames), rast)
names(raw_imgs) <- fire_ids

# Two fires were split in two because the wind changed direction mid-fire, so
# they get one landscape per half but share a single row of climatic data.
split_fires <- c("2015_47N" = "2015_47", "2015_47S" = "2015_47",
                 "2011_19E" = "2011_19", "2011_19W" = "2011_19")

fires <- data.frame(
  fire_id_spread = fire_ids,
  fire_id = ifelse(fire_ids %in% names(split_fires),
                   split_fires[fire_ids], fire_ids),
  elev_file = file.path(windninja_dir, paste0(fire_ids, ".tif"))
)

# Wind direction to blow over each landscape (degrees, where the wind comes from)
wind_data <- read.csv("data/climatic_data_by_fire_FWI-wind_corrected.csv")
stopifnot(all(fires$fire_id %in% wind_data$fire_id))
fires$direction <- wind_data$direction_use[match(fires$fire_id, wind_data$fire_id)]


# Stage 1 — elevation exports and WindNinja -------------------------------

if (do_windninja) {
  for (i in 1:n_fires) {
    cat(i, "/", n_fires, "-", fires$fire_id_spread[i], "\n")
    write_elevation_windninja(raw_imgs[[i]], fires$elev_file[i],
                              overwrite = TRUE)
    run_windninja(fires$elev_file[i],
                  direction = fires$direction[i],
                  speed = wn_speed,
                  mesh_resolution = wn_mesh,
                  num_threads = wn_threads)
  }
}

# Wind speed is standardized by `wind_sd`, frozen in R/landscape_functions.R
# because it is the scale the spread model was fitted under. Check the current
# WindNinja outputs still reproduce it — a mismatch means the wind layers were
# regenerated with different settings, and the fitted wind coefficient no longer
# applies.
if (do_windninja) {
  speeds <- unlist(lapply(fires$elev_file,
                          function(p) values(read_windninja(p)$speed)))
  wind_sd_now <- sd(speeds)
  cat("wind_sd: frozen", wind_sd, "| recomputed", wind_sd_now, "\n")
  if (abs(wind_sd_now - wind_sd) > 1e-4) {
    warning("Recomputed wind_sd differs from the frozen constant. ",
            "Do not rescale it without refitting the spread model.")
  }
}


# Fire-wise data ----------------------------------------------------------

# Ignition points. Those of 2014_1 and 2008_5 (Ñorquinco and Lolog) were edited
# because these fires had a change of wind: the point used is not the real
# ignition point, but is coherent with the dominant wind direction. The original
# points end in "_original" and are not in the kml file.
points_raw <- vect(file.path("data", "ignition_points_checked.shp"))
stopifnot(all(fire_ids %in% points_raw$Name))
points <- project(points_raw, raw_imgs[[1]])

# Fire dates, needed to detrend NDVI to its 2022 equivalent
fwi_raw <- read.csv(file.path(
  "data", "climatic_data_by_fire_fwi-fortnight-cumulative.csv"
))
fires$date <- as.Date(fwi_raw$date[match(fires$fire_id, fwi_raw$fire_id)],
                      format = "%Y-%m-%d")
# Fire year runs July-June, and FireSpread uses the NDVI of the previous summer.
fires$fire_year <- ifelse(month(fires$date) >= 7,
                          year(fires$date) + 1, year(fires$date))
fires$ndvi_year <- fires$fire_year - 1


# Build landscapes --------------------------------------------------------

# Urban is taken as forest here, so its burn probability changes markedly with
# NDVI. (The simulation landscapes make it non-burnable instead.)
dveg <- veg_crosswalk("forest")

elem_names <- c("landscape", "ig_rowcol",
                "burned_layer", "burned_ids",
                "counts_veg", "counts_veg_available",
                "landscape_img",
                "fire_id", "fire_id_spread")
# `landscape` holds vegetation too, but the spread function takes it separately.
# `landscape_img` keeps the predictors on their original scale, for maps.
# `fire_id_spread` identifies the landscape (split fires have two);
# `fire_id` identifies the fire in the climatic tables.

if (do_landscapes) {

lands <- vector("list", n_fires)
names(lands) <- fire_ids

for (i in 1:n_fires) {
  cat(i, "/", n_fires, "-", fire_ids[i], "\n")

  img <- raw_imgs[[i]]

  ## Predictors on their original scale, kept for plotting
  landscape_img <- img[[c("veg", "ndvi_prev", "elevation", "slope",
                          "aspect", "burned")]]
  names(landscape_img) <- c("veg", "ndvi_prev_dt", "elevation", "slope",
                            "aspect", "burned")

  ## NDVI, detrended to its 2022 equivalent
  ndvi <- ndvi_detrend(ndvi_focal = values(img[["ndvi_prev"]])[, 1],
                       year = fires$ndvi_year[i],
                       ndvi_22 = values(img[["ndvi_22"]])[, 1])
  values(landscape_img$ndvi_prev_dt) <- ndvi

  ## The six spread layers
  wind <- read_windninja(fires$elev_file[i])
  rall <- build_landscape(img, wind, dveg, ndvi, label = fire_ids[i])
  land_arr <- land_cube(rall)

  ## Fire-wise elements
  extras <- fire_elements(land_arr,
                          burned_img = landscape_img$burned,
                          ignition_point = points[points$Name == fire_ids[i]],
                          template = img,
                          label = fire_ids[i])

  lands[[i]] <- c(list(landscape = land_arr,
                       landscape_img = landscape_img,
                       fire_id = fires$fire_id[i],
                       fire_id_spread = fires$fire_id_spread[i]),
                  extras)[elem_names]
}

# Warnings expected here (many NA in landscape): 2015_47S and 2015_50.

# Check every ignition point falls in a burned and burnable cell
for (i in 1:n_fires) {
  ig <- lands[[i]]$ig_rowcol + 1  # undo 0-indexing
  ok <- sapply(1:ncol(ig), function(p) {
    lands[[i]]$landscape[ig[1, p], ig[2, p], "veg"] < 99 &&
      lands[[i]]$burned_layer[ig[1, p], ig[2, p]] == 1
  })
  if (!all(ok)) {
    stop("Ignition point problems, fire_id: ", fire_ids[i], ", i: ", i)
  }
}

format(object.size(lands), units = "Mb")  # ~2600 Mb


# Save landscapes ---------------------------------------------------------

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
for (i in 1:n_fires) {
  saveRDS(lands[[i]], file.path(out_dir,
                                paste0(lands[[i]]$fire_id_spread, ".rds")))
}

}


# Relative abundance of veg types in landscapes ---------------------------
# Exploratory: how many vegetation types each landscape actually contains,
# which bounds what the fire-wise fits can identify.

nv <- 7
veg_counts <- matrix(0, n_fires, nv)
colnames(veg_counts) <- dveg$class1[1:nv]
rownames(veg_counts) <- fire_ids

for (f in 1:n_fires) {
  tt <- table(as.vector(values(raw_imgs[[f]]$veg)))
  class_present <- as.numeric(names(tt))
  class_eval <- class_present[class_present %in% 1:nv]
  veg_counts[f, class_eval] <- tt[as.character(class_eval)]
}

veg_props <- t(apply(veg_counts, 1, function(x) x / sum(x)))

par(mfrow = c(2, 4))
for (v in 1:nv) {
  hist(veg_props[, v], breaks = seq(0, 1, by = 0.1),
       main = colnames(veg_props)[v],
       xlim = c(0, 1), xlab = "Relative abundance\nin landscape")
}
par(mfrow = c(1, 1))

# > 5 % in how many fires?
t(t(apply(veg_props, 2, function(x) sum(x < 0.05))))

# Condense araucaria and cypres as dry forest, and plantation as shrubland
veg_props_sub <- cbind(
  veg_props[, c("Wet forest", "Subalpine forest")],
  "Dry forest" = rowSums(veg_props[, c("Araucaria forest", "Cipres forest")]),
  "Shrubland" = rowSums(veg_props[, c("Shrubland", "Plantation")]),
  veg_props[, "Grassland"]
)

# Number of veg types with more than 5 % cover by landscape
veg_num <- t(t(apply(veg_props_sub, 1, function(x) sum(x >= 0.05))))
table(veg_num)

# Check landscape size of those with five
fire_size <- rowSums(veg_counts)
fire_size_rel <- fire_size / max(fire_size)
barplot(fire_size_rel)

fire_size_rel[veg_num == 5]
# most of them are small
