# Landscapes to SIMULATE new fires — no ignition point, no observed fire.
#
# Two sets, built from the same recipe as the fire-wise landscapes
# (R/landscape_functions.R), minus everything that is fire-specific:
#
#   1. Study-area tiles. The whole study area of Barberá et al. (2025) — the
#      patagonian fires mapping project — cut into K latitudinal pieces of equal
#      latitudinal length, each exported as a rectangle. These are what the
#      spread paper's fire-size-distribution validation simulates over.
#      Consecutive tiles do not overlap: they meet at a shared edge on the 30 m
#      grid, so no pixel belongs to two tiles, and a fire reaching a tile's
#      border is cut short by it — something the simulation has to deal with.
#      The tiling is decided in GEE, by
#      ~/dev/fire_spread-gee/"Landscapes export for simulation (study area tiles)",
#      which fits each rectangle inside the region where the NDVI and vegetation
#      assets have data. R cannot reproduce that, so it reads the rectangles
#      back from the exports themselves (below).
#
#   2. PNNH. The national park landscape, used by fire_regime/ for the regime
#      simulations and probability maps. Kept here unchanged (it predates the
#      tiles) so all "simulate new fires" landscapes live in one script.
#
# Differences from the fire-wise landscapes (data_prep/landscapes_preparation.R):
#   * urban is non-burnable, not forest — over a 600-km region containing
#     Bariloche, Esquel and El Bolsón, letting fire run through towns would
#     inflate the simulated size distribution;
#   * NDVI is a single recent year taken as-is. The fire-wise landscapes detrend
#     the previous summer's NDVI to its 2022 equivalent; here the tiles simply
#     export 2022, which is that same scale, so no detrending is needed.
#   * one fixed wind direction and speed for the whole region, as for PNNH.

library(terra)
library(tidyverse)
library(FireSpread)    # land_cube
source(file.path("R", "config.R"))
source(file.path("R", "flammability_indices_functions.R"))  # vfi_calc, tfi_calc
source(file.path("R", "landscape_functions.R"))

# Stages to run
do_tiles_windninja <- FALSE   # TRUE only to regenerate the tiles' wind layers
do_tiles <- TRUE
do_pnnh <- FALSE              # already built; TRUE only to rebuild

# Tiling. Must match K in the GEE script; the tiles it writes are ~150 km tall
# and as wide as the study area is there, all at or below the PNNH landscape's
# size, which WindNinja already handles. Raise K there (and here) if a tile
# stops fitting in memory.
K <- 4

# Wind. 293 degrees is the circular mean of the 57 focal fires' directions, and
# what the PNNH wind field was built with; over all 232 mapped fires it is 290,
# and it barely moves between tiles (289-291, checked below), so one fixed
# direction is defensible over the whole 600 km. 4 m/s is the regional average
# wind speed. Region-sized DEMs do not fit a 90 m mesh — 120 m is what PNNH
# needed and what the tiles use.
wn_direction <- 293
wn_speed <- 4
wn_mesh <- 120
wn_threads <- 6

sim_dir <- file.path("data", "simulation_landscapes")
gee_dir <- file.path(sim_dir, "raw_gee")
wind_dir <- file.path(sim_dir, "wind")
out_dir <- file.path(sim_dir, "landscapes")

# Urban is non-burnable in every landscape built here
dveg <- veg_crosswalk("nonburnable")


# Study-area tiles --------------------------------------------------------

study_area <- vect(file.path("data", "patagonian_fires", "study_area.shp"))

# GEE writes one file per tile (or several, if it had to split the export).
tile_stack <- function(k) {
  files <- list.files(gee_dir, full.names = TRUE,
                      pattern = sprintf("^study_area_tile_%d_.*\\.tif$", k))
  if (length(files) == 0) stop("No GEE export found for tile ", k)
  img <- if (length(files) == 1) rast(files) else vrt(files)
  band_names <- c("veg", "ndvi", "elevation", "slope", "aspect")
  if (nlyr(img) != length(band_names)) {
    stop("Tile ", k, " has ", nlyr(img), " bands, expected ",
         length(band_names), " (", paste(band_names, collapse = ", "), ")")
  }
  names(img) <- band_names
  return(img)
}

# The tile rectangles are read off the exports (only their headers, not their
# values), which is where the tiling lives now.
tile_rect <- function(k) {
  img <- tile_stack(k)
  r <- as.polygons(ext(img), crs = crs(img))
  r$tile <- k
  r$width_km <- (xmax(img) - xmin(img)) / 1000
  r$height_km <- (ymax(img) - ymin(img)) / 1000
  r$megapixels_30m <- ncell(img) / 1e6
  return(r)
}

tiles <- vect(lapply(1:K, tile_rect))
as.data.frame(tiles)

# Keep the tile rectangles next to the landscapes: later scripts need them to
# know where on the ground each tile — and each fire simulated in it — sits.
dir.create(sim_dir, showWarnings = FALSE, recursive = TRUE)
writeVector(tiles, file.path(sim_dir, "study_area_tiles.shp"), overwrite = TRUE)

# How much of the study area is actually tiled. Not automatically all of it:
# the tiles are cropped to where the NDVI and vegetation assets have data.
sa_proj <- project(study_area, crs(tiles))
cat("study area covered by the tiles:",
    round(sum(expanse(intersect(sa_proj, aggregate(tiles)))) /
          sum(expanse(sa_proj)) * 100, 1), "%\n")

## Is one fixed wind direction defensible over 600 km of latitude?
# Circular mean of the observed direction of the mapped fires, by tile:
# 290, 289, 291, 291 — yes.
wind_data <- read.csv("data/climatic_data_by_fire_FWI-wind_corrected.csv")
fires_map <- project(
  vect(file.path("data", "patagonian_fires", "patagonian_fires.shp")),
  crs(tiles)
)
fires_map$direction <- wind_data$direction_use[match(fires_map$fire_id,
                                                     wind_data$fire_id)]
fires_map <- fires_map[!is.na(fires_map$direction), ]

fire_tile <- terra::extract(tiles, centroids(fires_map))
fire_tile$direction <- fires_map$direction[fire_tile$id.y]
fire_tile %>%
  filter(!is.na(tile)) %>%
  group_by(tile) %>%
  summarise(n = n(), direction_mean = mean_circular_deg(direction))
# Overall:
mean_circular_deg(fires_map$direction)   # 290


## Stage 1 — elevation exports and WindNinja

tile_elev <- file.path(wind_dir, paste0("tile_", 1:K, "_elevation_30m.tif"))

if (do_tiles_windninja) {
  dir.create(wind_dir, showWarnings = FALSE, recursive = TRUE)
  for (k in 1:K) {
    cat("tile", k, "/", K, "\n")
    write_elevation_windninja(tile_stack(k), tile_elev[k], overwrite = TRUE)
    run_windninja(tile_elev[k],
                  direction = wn_direction,
                  speed = wn_speed,
                  mesh_resolution = wn_mesh,
                  num_threads = wn_threads)
  }
}


## Stage 2 — build and save the tile landscapes

if (do_tiles) {

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

for (k in 1:K) {
  cat("tile", k, "/", K, "\n")

  img <- tile_stack(k)
  wind <- read_windninja(tile_elev[k])

  # NDVI is exported for 2022, the scale the fire-wise landscapes are detrended
  # to, so it is used as it comes.
  ndvi <- values(img[["ndvi"]])[, 1]

  rall <- build_landscape(img, wind, dveg, ndvi, label = paste("tile", k))
  land_arr <- land_cube(rall)

  land <- c(list(landscape = land_arr,
                 tile = k,
                 n_tiles = K,
                 # geometry, to map simulated fires back to the ground and to
                 # sample ignition points in space
                 template = wrap(rall[["veg"]]),
                 na_prop = attr(rall, "na_prop")),
            count_veg(land_arr))

  cat("  ", paste(dim(land_arr)[1:2], collapse = " x "), "cells,",
      format(object.size(land_arr), units = "Gb"), ",",
      round(sum(land$counts_veg_available) / prod(dim(land_arr)[1:2]) * 100, 1),
      "% burnable\n")

  saveRDS(land, file.path(out_dir, sprintf("study_area_tile_%d.rds", k)))
  rm(img, wind, ndvi, rall, land_arr, land); gc()
}

}


# PNNH --------------------------------------------------------------------

# The smaller of the two PNNH exports: besides being smaller than the large
# buffer, its NDVI is from 2021, which avoids the low values around the
# Steffen-Martin fire of 2022.
#
# Two variants are saved, differing only in how urban is coded. fire_regime/
# reads the urban-non-burnable one. Both are saved as the bare landscape array
# (not the list the tiles use) because that is what fire_regime/simulate.R
# expects.

if (do_pnnh) {

pnnh_dir <- file.path("data", "pnnh_images")
pnnh_rast <- rast(file.path(pnnh_dir, "pnnh_data_spread_buffered_30m.tif"))
pnnh_elev <- file.path(pnnh_dir, "pnnh_data_spread_elevation_30m.tif")

if (!file.exists(pnnh_elev)) {
  write_elevation_windninja(pnnh_rast, pnnh_elev)
  run_windninja(pnnh_elev,
                direction = wn_direction,
                speed = wn_speed,
                mesh_resolution = wn_mesh,
                num_threads = wn_threads)
}

pnnh_wind <- read_windninja(pnnh_elev)
pnnh_ndvi <- values(pnnh_rast[["ndvi"]])[, 1]

for (urban_as in c("forest", "nonburnable")) {
  rall <- build_landscape(pnnh_rast, pnnh_wind, veg_crosswalk(urban_as),
                          pnnh_ndvi, label = paste("PNNH, urban as", urban_as))
  land_arr <- land_cube(rall)

  outfile <- if (urban_as == "forest") {
    "pnnh_spread_landscape.rds"
  } else {
    "pnnh_spread_landscape_urban-nonburnable.rds"
  }
  saveRDS(land_arr, file.path(pnnh_dir, outfile))

  print(apply(land_arr, 3, function(x) summary(as.vector(x))))
  rm(rall, land_arr); gc()
}

}
