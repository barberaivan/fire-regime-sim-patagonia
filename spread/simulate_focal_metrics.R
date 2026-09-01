# Model-fit metrics for the 57 focal fires — the input to paper Fig. 6.
#
# For every focal fire, simulate it `nsim` times with its own FITTED random
# effect and `nsim` times with a NEWLY SIMULATED one, always from the same
# ignition point on the same landscape, and reduce each simulated fire to a row
# of metrics. The figure then asks, per metric, whether the OBSERVED value is a
# plausible draw from that fire's own simulated distribution (a DHARMa scaled
# residual), and plots the 57 residuals as a uniform Q-Q.
#
# This supersedes the `metrics_table.rds` written by the "Assessing model fit"
# section of spread/hierarchical_fit.R, which carried only size and size by
# vegetation class. Fig. 6 also needs SHAPE, and shape needs each simulated
# fire's burned cells, which that table never stored. Everything is recomputed
# here in one pass so that every panel of the figure comes from the same
# simulations:
#
#   overlap                  as in hierarchical_fit.R, kept as a cross-check
#   size, size by veg (5)    the six size metrics of the old table
#   compactness              4*pi*area / perimeter^2
#   orientation, axis_dev    deviation from the fire's own wind axis, 0-90 deg
#   elongation, perimeter    free with the shape computation, not in the figure
#
# THE WIND AXIS IS PER FIRE, not the fixed 293 degrees used for the whole-record
# validation (spread/figure_validation_metrics.R). These 57 fires each have
# their own wind direction from the climatic table, and their landscapes were
# built with it, so the stricter reference is available here. It is the circular
# mean of `wdir` over the OBSERVED fire's burned cells: fixed per fire, so the
# observed fire and its 4000 simulations are all scored against the same axis,
# which is what makes the residual meaningful. The landscape-wide mean and both
# `rbar`s are saved beside it for reporting.
#
# Cost: 57 fires x 2 x `nsim` simulations. Fork-parallel over simulations, one
# fire at a time, the same shape as spread/validation_simulate.R. Roughly ten
# minutes on 14 cores at nsim = 2000, dominated by the largest fires.
#
# Inputs:  files/hierarchical_model/spread_model_samples.rds
#          data/focal_fires/landscapes/*.rds
#          data/climatic_data_by_fire_fwi-fortnight-cumulative_FWIZ2.csv
# Output:  files/hierarchical_model/focal_metrics.rds

library(FireSpread)
library(parallel)

source(file.path("R", "focal_simulation_functions.R"))
source(file.path("R", "spread_validation_functions.R"))   # fire_shape, circ_mean

# Settings ----------------------------------------------------------------

nsim <- 2000                 # per fire and per random-effect mode
cores <- 14
chunk_size <- 100            # simulations per parallel chunk
seed <- 20260901

lands_dir <- file.path("data", "focal_fires", "landscapes")
fit_dir <- file.path("files", "hierarchical_model")
out_file <- file.path(fit_dir, "focal_metrics.rds")

n_veg <- 5
nd_variables <- c("vfi", "tfi")
terrain_variables <- c("elevation", "wdir", "wspeed")
upper_limit <- 1

veg_labels <- c("wet", "subalpine", "dry", "shrubland", "grassland")
shape_metrics <- c("compactness", "orientation", "axis_dev", "elongation",
                   "perimeter_cells")
met_names <- c("overlap", "size", paste0("size_", veg_labels), shape_metrics)
nmet <- length(met_names)

fi_params <- readRDS(file.path("data", "flammability_indices",
                               "flammability_indices.rds"))
bounds <- focal_par_bounds(fi_params)
par_names <- bounds$par_names

#' Deviation of a fire's principal axis from a reference axis, in 0-90 degrees
#'
#' Both are bearings mod 180, so 0 means the fire runs along the axis and 90
#' means it runs across it.
axis_deviation <- function(orientation, axis_deg) {
  d <- abs(orientation - axis_deg %% 180)
  pmin(d, 180 - d)
}


# One simulated fire ------------------------------------------------------

#' @param p one parameter vector, named as `par_names`.
#' @param fd the fire's data: veg/nd/terrain matrices, ignition cells, and the
#'   observed burn for the overlap.
#' @param axis_deg the fire's wind axis, degrees.
one_sim <- function(p, fd, axis_deg) {
  fire <- simulate_fire_compare_veg(
    layer_vegetation = fd$veg,
    layer_nd = fd$nd,
    layer_terrain = fd$terrain,
    coef_intercepts = rep(p["intercept"], n_veg),
    coef_nd = p[nd_variables],
    coef_terrain = p[c("slope", "wind")],
    ignition_cells = fd$ig,          # already 0-indexed on disk
    upper_limit = upper_limit,
    steps = p["steps"],
    n_veg = n_veg
  )

  out <- stats::setNames(rep(NA_real_, nmet), met_names)
  out["overlap"] <- overlap_spatial(fire, fd$obs)
  out["size"] <- sum(fire$counts_veg)
  out[paste0("size_", veg_labels)] <- fire$counts_veg

  sh <- fire_shape(t(fire$burned_ids) + 1L)   # FireSpread is zero-indexed
  out["compactness"] <- sh["compactness"]
  out["orientation"] <- sh["orientation"]
  out["elongation"] <- sh["elongation"]
  out["perimeter_cells"] <- sh["perimeter_cells"]
  out["axis_dev"] <- axis_deviation(sh["orientation"], axis_deg)
  out
}

#' `one_sim()` over a matrix of parameter vectors, fork-parallel
#'
#' Chunked and dynamically dispatched: fire cost is driven by `steps`, which
#' varies by orders of magnitude within a fire's own posterior, so a static
#' split would let one unlucky worker set the wall clock.
sim_metrics <- function(pars, fd, axis_deg) {
  grp <- split(seq_len(nrow(pars)),
               ceiling(seq_len(nrow(pars)) / chunk_size))
  res <- mclapply(grp, function(g) {
    t(vapply(g, function(i) one_sim(pars[i, ], fd, axis_deg),
             numeric(nmet)))
  }, mc.cores = cores, mc.preschedule = FALSE)
  bad <- vapply(res, inherits, logical(1), "try-error")
  if (any(bad)) stop(sum(bad), " chunks failed: ", res[bad][[1]])
  do.call("rbind", res)
}


# Run ---------------------------------------------------------------------

set.seed(seed)

draws <- readRDS(file.path(fit_dir, "spread_model_samples.rds"))
npost <- dim(draws$fixef)[3]
fire_ids <- dimnames(draws$ranef)[[2]]
J <- length(fire_ids)
fwi_z <- focal_fwi_z(fire_ids)
stopifnot(J == 57, !anyNA(fwi_z))

sim_table <- array(
  NA_real_, dim = c(nsim * 2, nmet, J),
  dimnames = list(iter = c(paste0("fit_", 1:nsim), paste0("sim_", 1:nsim)),
                  metric = met_names, fire = fire_ids))

obs_table <- matrix(NA_real_, J, nmet,
                    dimnames = list(fire_ids, met_names))
veg_available <- matrix(NA_real_, J, n_veg,
                        dimnames = list(fire_ids, veg_labels))
wind_table <- matrix(NA_real_, J, 4,
                     dimnames = list(fire_ids,
                                     c("axis_deg", "rbar_burn",
                                       "land_deg", "rbar_land")))

t_start <- Sys.time()
for (j in seq_len(J)) {
  f <- fire_ids[j]
  l <- readRDS(file.path(lands_dir, paste0(f, ".rds")))
  land <- l$landscape

  fd <- list(
    veg = matrix(as.integer(land[, , "veg"]), dim(land)[1], dim(land)[2]),
    nd = land[, , nd_variables],
    terrain = land[, , terrain_variables],
    ig = l$ig_rowcol,
    obs = l[c("burned_layer", "burned_ids")]
  )

  # The observed fire, measured with exactly the functions the simulations use.
  idx_obs <- t(l$burned_ids) + 1L
  sh_obs <- fire_shape(idx_obs)
  wdir <- land[, , "wdir"]
  w_burn <- circ_mean(wdir[idx_obs])
  w_land <- circ_mean(wdir)
  axis_deg <- unname(w_burn["mean"]) * 180 / pi
  wind_table[j, ] <- c(axis_deg, unname(w_burn["rbar"]),
                       unname(w_land["mean"]) * 180 / pi,
                       unname(w_land["rbar"]))

  obs_table[j, "overlap"] <- 1
  obs_table[j, "size"] <- sum(l$counts_veg)
  obs_table[j, paste0("size_", veg_labels)] <- l$counts_veg
  obs_table[j, "compactness"] <- sh_obs["compactness"]
  obs_table[j, "orientation"] <- sh_obs["orientation"]
  obs_table[j, "elongation"] <- sh_obs["elongation"]
  obs_table[j, "perimeter_cells"] <- sh_obs["perimeter_cells"]
  obs_table[j, "axis_dev"] <- axis_deviation(sh_obs["orientation"], axis_deg)
  veg_available[j, ] <- l$counts_veg_available

  ids <- sample.int(npost, nsim, replace = FALSE)   # shared by the two modes
  t0 <- Sys.time()
  sim_table[1:nsim, , j] <-
    sim_metrics(ranef_fitted(draws, f, ids, bounds), fd, axis_deg)
  sim_table[(nsim + 1):(2 * nsim), , j] <-
    sim_metrics(ranef_simulated(draws, f, ids, bounds, fwi_z[f]), fd, axis_deg)

  cat(sprintf("%2d/%d %-22s %7.0f cells | %4.1f min | overlap %.2f/%.2f | q %.2f/%.2f\n",
              j, J, f, obs_table[j, "size"],
              as.numeric(difftime(Sys.time(), t0, units = "mins")),
              median(sim_table[1:nsim, "overlap", j]),
              median(sim_table[(nsim + 1):(2 * nsim), "overlap", j]),
              mean(sim_table[1:nsim, "size", j]) / obs_table[j, "size"],
              mean(sim_table[(nsim + 1):(2 * nsim), "size", j]) /
                obs_table[j, "size"]))

  rm(l, land, fd); gc()
}

saveRDS(list(sim = sim_table, obs = obs_table, wind = wind_table,
             veg_available = veg_available, nsim = nsim, seed = seed,
             cell_area_ha = 0.09),
        out_file)
cat("\nwrote", out_file, "in",
    round(as.numeric(difftime(Sys.time(), t_start, units = "mins")), 1),
    "min\n")


# Checks ------------------------------------------------------------------

# 1. The observed sizes must reproduce `size_obs.rds`, which the old table was
#    built with. This also proves the two share a fire ORDER: `size_obs` has no
#    row names, and everything downstream indexes it positionally.
size_obs_old <- readRDS(file.path(fit_dir, "size_obs.rds"))
d_size <- max(abs(obs_table[, c("size", paste0("size_", veg_labels))] -
                    size_obs_old), na.rm = TRUE)
cat("check | max |obs size - size_obs.rds| =", d_size,
    if (isTRUE(d_size == 0)) "(identical, same fire order)\n" else "  <-- LOOK\n")

# 2. The medians of the re-simulated distributions must land near the old
#    table's. The draws differ, so these are close but not equal.
mt <- readRDS(file.path(fit_dir, "metrics_table.rds"))
old_fit <- grep("^fit_", dimnames(mt)$iter)
old_sim <- grep("^sim_", dimnames(mt)$iter)
cmp <- rbind(
  old = c(overlap = median(apply(mt[old_fit, "overlap", ], 2, mean)),
          q_fit = median(apply(mt[old_fit, "size", ], 2, mean) /
                           size_obs_old[, 1]),
          q_sim = median(apply(mt[old_sim, "size", ], 2, mean) /
                           size_obs_old[, 1])),
  new = c(overlap = median(apply(sim_table[1:nsim, "overlap", ], 2, mean)),
          q_fit = median(apply(sim_table[1:nsim, "size", ], 2, mean) /
                           obs_table[, "size"]),
          q_sim = median(apply(sim_table[(nsim + 1):(2 * nsim), "size", ], 2,
                               mean) / obs_table[, "size"])))
cat("check | median over fires, old table vs this run:\n")
print(round(cmp, 3))

# 3. Simulated fires of fewer than 3 cells have no principal axis, so
#    `orientation` and `axis_dev` are NA by construction. Report how much of
#    the simulated set that removes — the figure drops them per fire.
na_ori <- mean(is.na(sim_table[, "orientation", ]))
cat("check | simulations with no orientation (< 3 cells):",
    sprintf("%.2f %%\n", 100 * na_ori))
