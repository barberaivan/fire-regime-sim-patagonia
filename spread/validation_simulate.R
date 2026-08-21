# Simulate fires over the study-area tiles for the spread model's validation.
#
# Target: `n_target` fires of at least 10 ha, the threshold below which the
# Barberá et al. (2025) mapping does not record fires, so smaller simulated
# fires have no observed counterpart and are discarded. Because they are
# discarded, the run proceeds in passes: each pass draws proposals, and passes
# continue until the target is met. Sub-threshold fires are not thrown away
# silently — their sizes are kept, so the acceptance rate itself is reportable.
#
# Sampling, per proposal (see spread/validation_ignition_cells.R for why the
# order matters):
#   1. FWI      resampled with replacement from the 233 mapped fires
#   2. draw     a posterior index, uniform over the merged 12000 draws
#   3. params   a NEW fire drawn from the population multivariate logit-normal,
#               not any fitted fire's random effect
#   4. tile     with probability proportional to the eligible cells that admit
#               a margin of `steps`
#   5. cell     uniform among those cells
# The fire is then simulated on the (2*steps+1)^2 sublandscape centred on the
# ignition cell. FireSpread spreads to the 8 neighbours per step, so after
# `steps` steps the burned set cannot leave that square: no fire is ever cut
# short by a tile border.
#
# No steps-intercept shift is applied. The -0.95 used in fire_regime/ is a
# recalibration of the regime simulator, not part of the spread model, and
# applying it here would make the validation circular.

library(FireSpread)
library(survival)
library(parallel)
source(file.path("R", "spread_validation_functions.R"))

# Settings ----------------------------------------------------------------

n_target <- 50000        # fires >= 10 ha wanted
min_area_ha <- 10
cores <- 14
chunk_size <- 200        # fires per parallel task; small enough that the rare
                         # very slow fire does not set the wall clock
fwi_mode <- "resample"   # "resample" from the observed fires. A uniform-FWI
                         # variant, for the FWI-stratified test, is a possible
                         # later addition; see docs/spread.md.
seed <- 20260820
max_strata <- 1500
out_dir <- file.path("files", "spread_validation")

n_veg <- 5
par_names <- c("intercept", "vfi", "tfi", "slope", "wind", "steps")
n_coef <- length(par_names)
nd_variables <- c("vfi", "tfi")
terrain_variables <- c("elevation", "wdir", "wspeed")
upper_limit <- 1
ext_alpha <- 50; ext_beta <- 30; stepsL <- 2
slope_sd <- 0.1891275    # fi_params$slope_term_sd, as in spread/hierarchical_fit.R
Lpar <- c(-ext_alpha, rep(0, n_coef - 2), stepsL)
Upar <- c(ext_alpha, rep(ext_beta, n_coef - 2), NA)
names(Lpar) <- names(Upar) <- par_names
Upar["slope"] <- ext_beta / slope_sd

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
set.seed(seed)

# Inputs ------------------------------------------------------------------

draws <- readRDS(file.path("files", "hierarchical_model", "spread_model_samples.rds"))
fwi_scale <- readRDS(file.path("files", "hierarchical_model", "fwi_mean_sd_spread.rds"))
ig <- readRDS(file.path(out_dir, "ignition_cells.rds"))

# The two fires that were split in two share one FWI value, so the csv's 233
# rows are the 233 distinct fires; resample those, not the 235 model rows.
fwi_obs <- read.csv(file.path("data",
  "climatic_data_by_fire_fwi-fortnight-cumulative_FWIZ2.csv"))$fwi_fort_expquad
fwi_z <- (fwi_obs - fwi_scale$fwi_mean) / fwi_scale$fwi_sd

n_post <- dim(draws$fixef)[3]
K <- length(ig)
n_valid <- sapply(ig, function(z) z$n_valid)      # (steps_max + 1) x K
steps_max <- nrow(n_valid) - 1L


# Proposal drawing --------------------------------------------------------

# Everything random is drawn here, in the master, so a worker is a pure
# function of its chunk and results do not depend on how chunks get scheduled.
draw_proposals <- function(n) {
  post <- sample.int(n_post, n, replace = TRUE)
  fwi_id <- sample.int(length(fwi_z), n, replace = TRUE)
  z <- fwi_z[fwi_id]

  # Population mean and covariance vary by draw, so group proposals sharing a
  # posterior index and generate each group in one multivariate call.
  coefs <- matrix(NA_real_, n, n_coef, dimnames = list(NULL, par_names))
  for (i in unique(post)) {
    w <- which(post == i)
    mu <- cbind(1, z[w]) %*% t(draws$fixef[1:n_coef, c("a", "b"), i])
    sds <- sqrt(draws$fixef[1:n_coef, "s2", i])
    V <- diag(sds) %*% draws$rho[, , i] %*% diag(sds)
    U <- Upar; U["steps"] <- draws$stepsU[i]
    raw <- mgcv::rmvn(length(w), mu, V)
    if (length(w) == 1) raw <- matrix(raw, nrow = 1)
    for (p in 1:n_coef) coefs[w, p] <- plogis(raw[, p]) * (U[p] - Lpar[p]) + Lpar[p]
  }
  steps <- pmin(floor(coefs[, "steps"]), steps_max)

  # Tile with probability proportional to the eligible cells admitting margin
  # `steps`, then a cell uniform among them. This keeps the marginal
  # distribution of `steps` exactly as drawn.
  nv <- n_valid[steps + 1L, , drop = FALSE]
  cum <- t(apply(nv, 1, cumsum))
  tile <- max.col(cum >= runif(n) * cum[, K], "first")

  ig_row <- integer(n); ig_col <- integer(n)
  for (k in seq_len(K)) {
    w <- which(tile == k)
    if (length(w) == 0) next
    cells <- ig[[k]]$cells; ridx <- ig[[k]]$row_index
    R <- ig[[k]]$n_row; C <- ig[[k]]$n_col
    for (a in w) {
      s <- steps[a]
      lo <- ridx[s + 1L] + 1L          # first cell with row >= s + 1
      hi <- ridx[min(R - s, R) + 1L]   # last cell with row <= R - s
      repeat {
        j <- lo + sample.int(hi - lo + 1L, 1L) - 1L
        if (cells[j, 2] > s && cells[j, 2] <= C - s) break
      }
      ig_row[a] <- cells[j, 1]; ig_col[a] <- cells[j, 2]
    }
  }

  data.frame(post = post, fwi_id = fwi_id, fwi_z = z, coefs,
             steps = steps, tile = tile, ig_row = ig_row, ig_col = ig_col,
             chunk_seed = sample.int(.Machine$integer.max, n))
}


# One fire ----------------------------------------------------------------

simulate_one <- function(p, land) {
  s <- p$steps
  r1 <- p$ig_row - s; r2 <- p$ig_row + s
  c1 <- p$ig_col - s; c2 <- p$ig_col + s

  # Subset the three simulator arguments straight out of the tile array (an
  # intermediate [r1:r2, c1:c2, ] cube would double the copying) and hand the
  # vegetation over as integer, which is what the C++ signature wants.
  veg <- land[r1:r2, c1:c2, "veg"]
  veg <- matrix(as.integer(veg), nrow(veg), ncol(veg))
  nd <- land[r1:r2, c1:c2, nd_variables]
  terrain <- land[r1:r2, c1:c2, terrain_variables]

  fire <- simulate_fire_compare(
    layer_vegetation = veg,
    layer_nd = nd,
    layer_terrain = terrain,
    coef_intercepts = rep(p$intercept, n_veg),
    coef_nd = c(p$vfi, p$tfi),
    coef_terrain = c(p$slope, p$wind),
    ignition_cells = matrix(c(s, s), ncol = 1),   # zero-indexed centre
    upper_limit = upper_limit,
    steps = s
  )

  size <- ncol(fire$burned_ids)
  if (size * 0.09 < min_area_ha) return(list(small = size))

  idx <- t(fire$burned_ids) + 1L      # FireSpread is zero-indexed
  # The signature uses only the non-directional predictors, so the reduced
  # landscape is all donor_strata() needs.
  land_sub <- list(veg = veg, vfi = nd[, , "vfi"], tfi = nd[, , "tfi"])

  shape <- fire_shape(idx)

  # Wind, and elongation relative to it. WindNinja steers the field by terrain,
  # so a fire's own wind is not the fixed 293 degrees the tiles were driven with
  # and has to be averaged out of the landscape it burned. Two averages: over the
  # burned cells, the wind the fire actually experienced and the axis
  # `elong_wind` is measured against; and over the whole sublandscape, which is
  # fixed before the fire runs and so is free of any feedback from its shape.
  # `rbar` says how much either mean is worth — a scattered field has no
  # meaningful direction. Only the simulated fires get these; the 184 observed
  # fires with no ignition point were exported without a wind layer, which is why
  # `elongation` (direction-free) is kept alongside.
  wdir_m <- terrain[, , "wdir"]
  wind_burn <- circ_mean(wdir_m[idx])
  wind_land <- circ_mean(wdir_m)
  wind <- c(
    elong_wind = elongation_along(shape["cov_ee"], shape["cov_nn"],
                                  shape["cov_en"], wind_burn["mean"]),
    wdir_burn_deg = unname(wind_burn["mean"]) * 180 / pi,
    wdir_burn_rbar = unname(wind_burn["rbar"]),
    wdir_land_deg = unname(wind_land["mean"]) * 180 / pi,
    wdir_land_rbar = unname(wind_land["rbar"]),
    wspeed_burn = mean(terrain[, , "wspeed"][idx], na.rm = TRUE)
  )

  st <- donor_strata(idx, land_sub, max_strata = max_strata)
  cl <- if (is.null(st)) {
    stats::setNames(rep(NA_real_, 7),
                    c("vfi", "tfi", "converged", "n_strata", "n_rows",
                      "sdx_vfi", "sdx_tfi"))
  } else edge_clogit(st)
  names(cl)[1:2] <- paste0("b_", names(cl)[1:2])

  list(row = c(unlist(p[c("post", "fwi_id", "fwi_z", par_names, "tile",
                          "ig_row", "ig_col")]),
               shape, wind, cl))
}

run_chunk <- function(rows, land) {
  set.seed(rows$chunk_seed[1])
  out <- vector("list", nrow(rows))
  small <- integer(0)
  for (i in seq_len(nrow(rows))) {
    r <- simulate_one(rows[i, ], land)
    if (!is.null(r$small)) small <- c(small, r$small) else out[[i]] <- r$row
  }
  out <- out[!vapply(out, is.null, logical(1))]
  list(kept = if (length(out)) do.call(rbind, out) else NULL, small = small)
}


# Passes ------------------------------------------------------------------

kept <- list(); small <- list()
n_kept <- 0L; n_prop <- 0L; pass <- 0L
accept <- 0.37   # pilot estimate, refined after the first pass

while (n_kept < n_target) {
  pass <- pass + 1L
  need <- n_target - n_kept
  n_draw <- ceiling(need / accept * 1.1)
  cat("\n== pass", pass, ": drawing", format(n_draw, big.mark = ","),
      "proposals for", format(need, big.mark = ","), "more fires\n")

  prop <- draw_proposals(n_draw)

  for (k in seq_len(K)) {
    rows <- prop[prop$tile == k, ]
    if (nrow(rows) == 0) next
    cat("  tile", k, ":", nrow(rows), "fires ... ")
    land <- readRDS(file.path("data", "simulation_landscapes", "landscapes",
                              sprintf("study_area_tile_%d.rds", k)))$landscape
    gc()

    # Longest-first: the slowest 1% of fires take about half the total CPU, so
    # the biggest chunks must start before the workers run out of work.
    ord <- order(rows$steps, decreasing = TRUE)
    rows <- rows[ord, ]
    grp <- split(seq_len(nrow(rows)),
                 ceiling(seq_len(nrow(rows)) / chunk_size))
    t0 <- Sys.time()
    res <- mclapply(grp, function(g) run_chunk(rows[g, ], land),
                    mc.cores = cores, mc.preschedule = FALSE)
    cat(round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")

    bad <- vapply(res, inherits, logical(1), "try-error")
    if (any(bad)) warning(sum(bad), " chunks failed on tile ", k)
    res <- res[!bad]
    kept <- c(kept, lapply(res, `[[`, "kept"))
    small <- c(small, lapply(res, `[[`, "small"))
    rm(land, res); gc()
  }

  n_prop <- n_prop + n_draw
  n_kept <- sum(vapply(kept, function(z) if (is.null(z)) 0L else nrow(z), integer(1)))
  accept <- max(n_kept / n_prop, 0.05)
  cat("  kept so far:", format(n_kept, big.mark = ","), "of",
      format(n_prop, big.mark = ","), "proposals (", round(accept * 100, 1), "%)\n")
}

sim <- as.data.frame(do.call(rbind, kept))
small <- unlist(small)

saveRDS(list(fires = sim,
             small_sizes = small,
             n_proposals = n_prop,
             settings = list(n_target = n_target, min_area_ha = min_area_ha,
                             fwi_mode = fwi_mode, seed = seed,
                             max_strata = max_strata)),
        file.path(out_dir, "simulated_fires.rds"))

cat("\ndone:", format(nrow(sim), big.mark = ","), "fires >=", min_area_ha, "ha from",
    format(n_prop, big.mark = ","), "proposals;",
    format(length(small), big.mark = ","), "below threshold (",
    round(mean(small == 1) * 100, 1), "% of those burned a single cell)\n")
print(round(quantile(sim$area_ha, c(.05, .25, .5, .75, .95, .99, 1)), 1))
