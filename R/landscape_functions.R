# Shared helpers to build fire-spread landscapes.
#
# Two kinds of landscape are built in this repo, from the same core recipe:
#
#   * fire-wise landscapes — data_prep/landscapes_preparation.R. One per focal
#     fire, used to FIT the spread model. They carry fire-wise data: the
#     ignition point and the observed burned polygon (the fire's FWI travels in
#     the fires table, not inside the landscape).
#
#   * simulation landscapes — data_prep/landscapes_simulation.R. Regional tiles
#     over the Barberá et al. (2025) study area, plus PNNH, used to SIMULATE
#     many new fires. No ignition point, no burned polygon, no fire-wise FWI:
#     ignitions are drawn by the simulator and FWI is a fire-level covariate
#     sampled there too.
#
# Everything the two share lives here. Source after
# R/flammability_indices_functions.R (this file uses vfi_calc/tfi_calc) and
# R/config.R, with library(terra) and library(FireSpread) loaded.


# Constants ---------------------------------------------------------------

# Layer order expected by the FireSpread engine:
#   veg     {0: wet forest, 1: subalpine, 2: dry forest, 3: shrubland,
#            4: grassland, 99: non-burnable}
#   vfi     vegetation flammability index, standardized
#   tfi     topographic flammability index, standardized
#   elevation  m a.s.l., raw — the slope term is scaled through its coefficient
#              instead (fi_params$slope_term_sd), not through the layer
#   wdir       wind direction (radians, direction the wind comes FROM)
#   wspeed     wind speed, scaled by wind_sd (below)
#
# These exact names are indexed by the consumers (`terrain_variables <-
# c("elevation", "wdir", "wspeed")` in spread/ and fire_regime/), so they are
# part of the landscape file format — do not rename them.
land_names <- c("veg", "vfi", "tfi", "elevation", "wdir", "wspeed")

# Reduced layer set, for landscapes that are never handed to the engine: the
# spread model's validation scores an observed fire's edge with a conditional
# logit on the non-directional predictors only, so `veg`, `vfi` and `tfi` are
# all it reads (R/spread_validation_functions.R -> donor_strata()). Landscapes
# with this layer set are built by passing `wind = NULL` to build_landscape().
land_names_reduced <- c("veg", "vfi", "tfi")

n_veg_types <- 5

# SD of the WindNinja wind speed (m/s) pooled over the 57 focal-fire
# landscapes. It is the scale the spread model was FITTED under, so every
# landscape — focal fire, PNNH or simulation tile — must divide wind speed by
# this same number. Recomputing it from a different set of landscapes would
# silently rescale the fitted wind coefficient.
wind_sd <- 1.464333

# Value written wherever a predictor is missing. Such cells are also marked
# non-burnable, so the engine never reads them (it skips non-burnable
# neighbours before touching any layer) — the number is only a C++-safe
# stand-in for NA.
na_fill <- -9999


# Vegetation crosswalk ----------------------------------------------------

#' Vegetation-class crosswalk, with the urban class resolved
#'
#' Reads the vegetation equivalence table and adds the two code columns the
#' landscape builder needs, both keyed by the raster's own `cnum1` codes:
#'   `cnum_spread` — FireSpread codes, 0:4 burnable and 99 non-burnable.
#'   `cnum_fi`     — flammability-index classes, 1:5 (6 = no VFI defined).
#'
#' @param urban_as how to treat the Urban class.
#'   "forest": urban becomes wet forest, so its burn probability changes
#'     markedly with NDVI. This is what the focal-fire (fitting) landscapes use.
#'   "nonburnable": urban cannot burn. This is what the simulation landscapes
#'     use — over a 600-km region containing Bariloche, Esquel and El Bolsón,
#'     letting fire run through towns would inflate simulated fire sizes.
#' @param xlsx path to the equivalence table (sheet "Sheet2").
veg_crosswalk <- function(urban_as = c("forest", "nonburnable"),
                          xlsx = config$veg_equiv_xlsx) {
  urban_as <- match.arg(urban_as)

  dveg <- readxl::read_excel(xlsx, sheet = "Sheet2")
  urban <- dveg$class1 == "Urban"

  # cnum2 is 1:5 for the burnable classes and 6 for non-burnable ones
  dveg$cnum_fi <- dveg$cnum2
  dveg$cnum_spread <- ifelse(dveg$cnum2 == 6, 99, dveg$cnum2 - 1)

  if (urban_as == "forest") {
    dveg$cnum_fi[urban] <- 1      # wet forest
    dveg$cnum_spread[urban] <- 0  # wet forest, 0-indexed
    dveg$class2[urban] <- "Wet forest"
  } else {
    dveg$cnum_fi[urban] <- 6
    dveg$cnum_spread[urban] <- 99
  }

  return(dveg)
}


# Circular mean, to summarize wind directions
# https://stackoverflow.com/questions/32404222/circular-mean-in-r
mean_circular_deg <- function(x) {  # x in degrees, result in [0, 360)
  conv <- 2 * pi / 360
  mm <- atan2(sum(sin(conv * x)), sum(cos(conv * x))) / conv
  return((mm + 360) %% 360)
}


# WindNinja ---------------------------------------------------------------

#' Write an elevation raster for WindNinja
#'
#' WindNinja refuses a DEM with holes, so NA cells are filled with the mean
#' elevation. Returns the path written.
write_elevation_windninja <- function(x, path, overwrite = FALSE) {
  r <- x[["elevation"]]
  v <- values(r)
  if (anyNA(v)) r <- subst(r, NA, mean(v, na.rm = TRUE))
  writeRaster(r, path, overwrite = overwrite)
  return(path)
}

#' Run WindNinja over one elevation raster, at a single direction and speed
#'
#' Writes a config file next to the DEM, calls `WindNinja_cli`, and deletes the
#' config. WindNinja drops its output in the DEM's own folder, named
#' `<dem>_<direction>_<speed>_<ascii_resolution>m_{ang,vel}.asc` — the direction
#' is rounded in ways that are awkward to predict, so read the outputs back with
#' `read_windninja()` (which globs) rather than rebuilding the name here.
#'
#' `mesh_resolution` is the RAM knob: 90 m is fine for focal-fire landscapes,
#' but region-sized DEMs (PNNH, the simulation tiles) need 120 m.
#'
#' `momentum_flag` is deliberately absent: it is only recognized by NINJAFOAM
#' (momentum-solver) builds, and `domainAverageInitialization` uses the
#' conservation-of-mass solver regardless. See docs/migration.md TODO #3.
run_windninja <- function(elev_path,
                          direction,
                          speed = 4,
                          mesh_resolution = 90,
                          ascii_resolution = 30,
                          num_threads = 15,
                          vegetation = "trees") {

  cfg_path <- file.path(dirname(elev_path),
                        paste0("spread_config_", basename(elev_path), ".cfg"))

  cat(file = cfg_path, sep = "\n",
      paste("num_threads                =", num_threads),
      "initialization_method      = domainAverageInitialization",
      paste("input_speed                =", speed),
      "input_speed_units          = mps",
      "output_speed_units         = mps",
      "input_wind_height          = 10.0",
      "units_input_wind_height    = m",
      "output_wind_height         = 10.0",
      "units_output_wind_height   = m",
      paste("vegetation                 =", vegetation),
      paste("mesh_resolution            =", mesh_resolution),
      "units_mesh_resolution      = m",
      "output_buffer_clipping     = 0.0",
      "write_ascii_output         = true",
      paste("ascii_out_resolution       =", ascii_resolution),
      "units_ascii_out_resolution = m",
      paste("elevation_file             =", elev_path),
      paste("input_direction            =", direction))

  status <- system(paste0("WindNinja_cli --config_file=", cfg_path))
  unlink(cfg_path)

  if (status != 0) {
    stop("WindNinja_cli failed (status ", status, ") on ", elev_path)
  }

  return(invisible(elev_path))
}

#' Read the wind direction/speed rasters WindNinja wrote for one DEM
#'
#' Globs `<dem base>_<dir>_<speed>_<res>m_{ang,vel}.asc` in the DEM's folder, so
#' it does not depend on how WindNinja rounded the direction into the filename.
#' Returns a two-layer SpatRaster: `direction` (degrees) and `speed` (m/s).
read_windninja <- function(elev_path) {
  dir_out <- dirname(elev_path)
  base <- tools::file_path_sans_ext(basename(elev_path))

  find_one <- function(kind) {
    pat <- paste0("^", base, "_[0-9.]+_[0-9.]+_[0-9]+m_", kind, "\\.asc$")
    hits <- list.files(dir_out, pattern = pat)
    if (length(hits) != 1) {
      stop("Expected exactly 1 WindNinja '", kind, "' output for ", base,
           ", found ", length(hits),
           ". Delete stale runs or re-run run_windninja().")
    }
    return(file.path(dir_out, hits))
  }

  wind <- c(rast(find_one("ang")), rast(find_one("vel")))
  names(wind) <- c("direction", "speed")
  return(wind)
}


# Landscape building ------------------------------------------------------

#' Build the 6-layer landscape raster the FireSpread engine consumes
#'
#' The shared core of every landscape in this repo. What differs between the
#' fire-wise and the simulation landscapes is handled by the callers: which
#' raster stack comes in, whether NDVI was detrended, how urban is coded
#' (`dveg`), and whether fire-wise elements are computed afterwards.
#'
#' @param stack SpatRaster with layers `veg`, `elevation`, `slope`, `aspect`.
#' @param wind SpatRaster with layers `direction` (degrees) and `speed` (m/s),
#'   on any grid — it is projected onto `stack`. `NULL` builds the reduced
#'   `land_names_reduced` landscape instead (no wind field, no elevation
#'   layer): all the validation's edge analysis reads, and the reason the 184
#'   fires without an ignition point need no WindNinja run.
#' @param dveg crosswalk from `veg_crosswalk()`.
#' @param ndvi numeric vector, one value per cell of `stack`, already detrended
#'   to the 2022 scale if the source year is not 2022.
#' @param na_warn_prop warn if more than this proportion of cells had to be
#'   turned non-burnable because a predictor was missing.
#' @param label name used in that warning.
#' @return SpatRaster with layers `land_names` (or `land_names_reduced` when
#'   `wind` is NULL), ready for `land_cube()`. The proportion of NA-masked
#'   cells is attached as attribute `na_prop`.
build_landscape <- function(stack, wind, dveg, ndvi,
                            na_warn_prop = 0.02,
                            label = NULL) {

  needed <- c("veg", "elevation", "slope", "aspect")
  if (!all(needed %in% names(stack))) {
    stop("stack is missing layer(s): ",
         paste(setdiff(needed, names(stack)), collapse = ", "))
  }
  stopifnot(length(ndvi) == ncell(stack))

  ## Vegetation
  veg_raw <- values(stack[["veg"]])[, 1]

  veg_spread <- dveg$cnum_spread[match(veg_raw, dveg$cnum1)]
  veg_spread[is.na(veg_spread)] <- 99   # unmapped codes and NA are non-burnable

  veg_fi <- dveg$cnum_fi[match(veg_raw, dveg$cnum1)]
  veg_fi[is.na(veg_fi)] <- 6

  burnable <- veg_spread != 99

  ## Flammability indices.
  # Only computed on burnable cells: VFI is undefined for class 6, and the
  # engine never reads a non-burnable cell's layers, so 0 there is arbitrary
  # but keeps the NA mask below about *predictors*, not about vegetation.
  vtopo <- values(stack[[c("elevation", "slope", "aspect")]])

  vfi <- tfi <- numeric(length(veg_spread))
  vfi[burnable] <- vfi_calc(veg_fi[burnable], ndvi[burnable])
  tfi[burnable] <- tfi_calc(vtopo[burnable, "elevation"],
                            vtopo[burnable, "aspect"],
                            vtopo[burnable, "slope"])

  ## Wind, projected onto the landscape grid, and the full engine layer order.
  # Without wind there is no elevation layer either: it is only there for the
  # engine's directional slope term, and a cell whose elevation is missing
  # already loses its `tfi`, so the NA mask below is unchanged by dropping it.
  if (is.null(wind)) {
    vv <- cbind(veg_spread, vfi, tfi)
    colnames(vv) <- land_names_reduced
  } else {
    wind_local <- project(wind, stack, method = "cubicspline")
    vwind <- values(wind_local)

    vv <- cbind(veg_spread,
                vfi,
                tfi,
                vtopo[, "elevation"],
                vwind[, "direction"] * pi / 180,
                vwind[, "speed"] / wind_sd)
    colnames(vv) <- land_names
  }

  ## Any cell with a missing predictor becomes non-burnable
  na_cells <- which(!stats::complete.cases(vv))
  vv[na_cells, "veg"] <- 99
  vv[is.na(vv)] <- na_fill

  na_prop <- length(na_cells) / nrow(vv)
  if (na_prop > na_warn_prop) {
    warning("Many NA in landscape",
            if (is.null(label)) "" else paste0(" ", label),
            ": ", round(na_prop * 100, 2), "% of cells")
  }

  rall <- rast(stack, nlyrs = ncol(vv))
  values(rall) <- vv
  names(rall) <- colnames(vv)

  attr(rall, "na_prop") <- na_prop
  return(rall)
}

#' Count landscape cells by vegetation type
#'
#' `burned` is an optional 0/1 matrix matching the landscape array's first two
#' dimensions; when given, burned cells are counted per type as well.
count_veg <- function(land_arr, burned = NULL) {
  veg_vec <- as.vector(land_arr[, , "veg"])
  available <- sapply(1:n_veg_types, function(k) sum(veg_vec == (k - 1)))

  if (is.null(burned)) return(list(counts_veg_available = available))

  burned_vec <- as.vector(burned)
  burnt <- sapply(1:n_veg_types,
                  function(k) sum((veg_vec == (k - 1)) * burned_vec))
  return(list(counts_veg = burnt, counts_veg_available = available))
}

#' Fire-wise elements of a focal-fire landscape
#'
#' Everything a landscape needs to be *fitted against* and that a simulation
#' landscape has no counterpart for: the observed burned area and the ignition
#' point. Row/column indices come back 0-indexed, for C++.
#'
#' @param land_arr the landscape array from `land_cube()`.
#' @param burned_img single-layer SpatRaster, 1 on burned cells.
#' @param ignition_point SpatVector of one or more ignition points, already
#'   projected onto the landscape.
#' @param template SpatRaster giving the landscape's geometry.
fire_elements <- function(land_arr, burned_img, ignition_point, template,
                          label = NULL) {

  burned_layer <- land_cube(burned_img)[, , 1]
  burned_layer[is.na(burned_layer)] <- 0

  burned_cells <- which(values(burned_img)[, 1] == 1)
  burned_ids <- t(rowColFromCell(template, burned_cells))
  rownames(burned_ids) <- c("row", "col")

  cc <- crds(ignition_point)
  ig_rowcol <- rbind(row = rowFromY(template, cc[, "y"]),
                     col = colFromX(template, cc[, "x"]))
  if (anyNA(ig_rowcol)) {
    stop("Ignition point out of range",
         if (is.null(label)) "" else paste0(", fire ", label))
  }

  out <- c(list(burned_layer = burned_layer,
                burned_ids = burned_ids - 1,  # 0-indexing!
                ig_rowcol = ig_rowcol - 1),   # 0-indexing!
           count_veg(land_arr, burned_layer))

  return(out)
}

