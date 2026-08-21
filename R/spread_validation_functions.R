# Shared functions for the spread model's pattern-oriented validation
# (spread/validation_*.R). Everything here works identically on an observed
# fire (rasterized polygon + its landscape) and on a simulated one (the
# simulator's output + the clipped landscape it ran on), which is the whole
# point: the two protocols must be the same function.
#
# All of them take the burned cells as an n x 2 {row, col} matrix rather than a
# burn mask, because both callers already have one — FireSpread returns
# `burned_ids`, and the focal-fire landscapes store it too — and scanning a
# multi-million-cell mask to recover it is the most expensive thing in here.

# Neighbourhood constants, copied from FireSpread's src/spread_functions.cpp.
# Position k (1-indexed here, 0-indexed there) means target = source + moves[k].
#   0 1 2
#   3   4
#   5 6 7
nb_moves <- rbind(row = c(-1L, -1L, -1L,  0L, 0L,  1L, 1L, 1L),
                  col = c(-1L,  0L,  1L, -1L, 1L, -1L, 0L, 1L))
nb_dist <- c(30 * sqrt(2), 30, 30 * sqrt(2),
             30,               30,
             30 * sqrt(2), 30, 30 * sqrt(2))
nb_angle <- c(pi * 3 / 4, pi, pi * 5 / 4,
              pi / 2,         pi * 3 / 2,
              pi / 4,     0,  pi * 7 / 4)
# moves[k] == -moves[9-k] and nb_angle[k] == nb_angle[9-k] +- pi, so 9-k is the
# reverse direction: used to score a pair's burned member as if the fire had
# travelled the other way.
nb_rev <- 8:1


#' Bounding box of a fire, padded by one cell and clipped to the landscape
fire_box <- function(idx, n_row, n_col, pad = 1L) {
  list(r1 = max(min(idx[, 1]) - pad, 1L), r2 = min(max(idx[, 1]) + pad, n_row),
       c1 = max(min(idx[, 2]) - pad, 1L), c2 = min(max(idx[, 2]) + pad, n_col))
}


#' Donor-centred strata of a fire, with the non-directional predictors
#'
#' One stratum per burned cell that has at least one burnable unburned
#' neighbour; the stratum's members are that cell's burnable neighbours, and the
#' response is whether each of them burned. This is the simulator's own
#' Bernoulli trial set, and holding the donor fixed within a stratum conditions
#' out everything about the fire, the donor and the weather. The shared
#' intercept is conditioned out by the stratum too.
#'
#' **Only `vfi` and `tfi`, at the target cell.** The slope and wind terms of
#' `spread_one_cell_prob()` are directional — they depend on which cell the fire
#' actually came from — and for an observed fire the burn order is unknown, so
#' the donor is a guess at the arrival direction rather than a measurement.
#' Including them would compare a quantity we can compute for simulated fires
#' against one we cannot compute for observed ones. Their omission costs
#' nothing: an edge-based contrast has no power for them anyway (around a
#' perimeter the donor→receiver direction is the outward normal, hence
#' isotropic, and an edge donor's burned neighbours are systematically the ones
#' the fire arrived from). Wind and slope are tested through fire shape instead.
#'
#' Because the predictors no longer depend on the donor, the landscape needs
#' only `veg`, `vfi` and `tfi` — no elevation and no wind field. That is what
#' makes it feasible to build reduced landscapes for all mapped fires, not just
#' the 57 with a known ignition point.
#'
#' Strata whose members all burned, or none of which burned, carry no
#' conditional information and are dropped.
#'
#' @param idx n x 2 integer matrix of burned {row, col}.
#' @param land named list of landscape matrices: veg, vfi, tfi (see
#'   `land_matrices()`). Extra layers are ignored.
#' @param max_strata subsample donors to at most this many. The regression gains
#'   almost nothing past a couple of thousand strata and the largest fires have
#'   hundreds of thousands.
#' @return list with `strat` (integer stratum id), `y` (burned) and `x`
#'   (n x 2 predictor matrix), or NULL if the fire has no usable edge.
donor_strata <- function(idx, land, max_strata = 1500) {
  n_row <- nrow(land$veg); n_col <- ncol(land$veg)
  if (nrow(idx) == 0) return(NULL)
  b <- fire_box(idx, n_row, n_col)
  nr <- b$r2 - b$r1 + 1L; nc <- b$c2 - b$c1 + 1L
  if (nr < 3L || nc < 3L) return(NULL)

  B <- matrix(FALSE, nr, nc)
  B[cbind(idx[, 1] - b$r1 + 1L, idx[, 2] - b$c1 + 1L)] <- TRUE
  veg <- land$veg[b$r1:b$r2, b$c1:b$c2]

  ii <- 2:(nr - 1L); jj <- 2:(nc - 1L)
  free <- matrix(FALSE, length(ii), length(jj))
  for (k in 1:8) {
    ti <- ii + nb_moves["row", k]; tj <- jj + nb_moves["col", k]
    free <- free | (!B[ti, tj] & veg[ti, tj] != 99)
  }
  sel <- which(B[ii, jj] & free)
  if (length(sel) < 20L) return(NULL)
  if (length(sel) > max_strata) sel <- sample(sel, max_strata)

  di <- ((sel - 1L) %% length(ii)) + 2L
  dj <- ((sel - 1L) %/% length(ii)) + 2L

  vfi <- land$vfi[b$r1:b$r2, b$c1:b$c2]
  tfi <- land$tfi[b$r1:b$r2, b$c1:b$c2]

  parts <- vector("list", 8)
  for (k in 1:8) {
    tg <- cbind(di + nb_moves["row", k], dj + nb_moves["col", k])
    keep <- veg[tg] != 99
    if (!any(keep)) next
    parts[[k]] <- cbind(
      strat = sel, y = as.integer(B[tg]),
      vfi = vfi[tg], tfi = tfi[tg])[keep, , drop = FALSE]
  }
  d <- do.call(rbind, parts)
  d <- d[rowSums(!is.finite(d)) == 0, , drop = FALSE]
  if (nrow(d) < 40L) return(NULL)

  # keep only strata with a mixed response
  mixed <- stats::ave(d[, "y"], d[, "strat"], FUN = function(z) length(unique(z))) > 1
  d <- d[mixed, , drop = FALSE]
  if (nrow(d) < 40L || length(unique(d[, "strat"])) < 10L) return(NULL)

  list(strat = d[, "strat"], y = d[, "y"], x = d[, 3:4, drop = FALSE])
}


#' Conditional logit over donor strata — vfi and tfi together
#'
#' A thin wrapper on `survival::clogit`. Strata here have up to eight members
#' and often several cases, where the exact conditional likelihood and the
#' Breslow/Efron approximations genuinely differ, so this uses the exact method
#' rather than a hand-rolled approximation — at ~0.1 s per fire including
#' extraction it is affordable, and it keeps the statistic standard.
#'
#' Multiple regression, not one predictor at a time: `vfi` and `tfi` are
#' correlated through vegetation and topography, and the univariate coefficients
#' would each absorb part of the other's effect.
#'
#' Coefficients are returned **on the original predictor scale**. The fit itself
#' standardizes the predictors per fire, purely for numerical conditioning, and
#' back-transforms by dividing by the scale. Centring cancels in a conditional
#' likelihood (a constant shifts every member of a stratum equally), so only the
#' scale has to be undone. `sdx_*` is kept so a standardized version can still
#' be reconstructed downstream if it is ever wanted for plotting.
#'
#' Fires whose strata separate return large coefficients; they are flagged
#' rather than dropped, since the same thing happens to observed fires with few
#' strata and the analysis conditions on fire size anyway.
edge_clogit <- function(s) {
  nm <- c("vfi", "tfi")
  sdx <- apply(s$x, 2, stats::sd)
  sdx[!is.finite(sdx) | sdx <= 0] <- 1
  xs <- scale(s$x, center = TRUE, scale = sdx)

  d <- data.frame(y = s$y, strat = s$strat, xs)
  fit <- try(survival::clogit(y ~ vfi + tfi + strata(strat),
                              data = d, method = "exact"), silent = TRUE)
  if (inherits(fit, "try-error")) {
    out <- c(stats::setNames(rep(NA_real_, 2), nm), converged = 0)
  } else {
    out <- c(coef(fit)[nm] / sdx[nm],          # back to the original scale
             converged = as.numeric(!is.null(fit$iter)))
  }
  c(out,
    n_strata = length(unique(s$strat)),
    n_rows = nrow(s$x),
    stats::setNames(sdx[nm], paste0("sdx_", nm)))
}


#' Shape metrics from the burned cells
#'
#' All in raster space, all sub-millisecond. `elongation` is direction-free —
#' the ratio of the two principal axes, whatever way the fire happens to point —
#' and `orientation` is the bearing of the leading axis in degrees (mod 180).
#' The observed fires without an ignition point have no wind layer, so those two
#' are all their side of the comparison can offer: alignment has to be judged
#' against the fixed 293-degree wind the landscapes were built with (fire runs
#' along the 113/293 axis, so orientation near 113 means wind-aligned).
#'
#' `cov_ee`/`cov_nn`/`cov_en` are the burned cells' covariance entries in
#' east/north cell units. They are returned so that elongation along *any*
#' reference axis can be recomputed afterwards with `elongation_along()` without
#' re-running the simulation — the fixed 293 degrees for comparability with the
#' observed fires, or a simulated fire's own mean wind.
fire_shape <- function(idx, cell_area_ha = 0.09) {
  n <- nrow(idx)
  if (n == 0) return(NULL)
  xy <- cbind(as.numeric(idx[, 2]), -as.numeric(idx[, 1]))   # east, north

  elong <- orient <- fill <- NA_real_
  sxx <- syy <- sxy <- NA_real_
  if (n >= 3) {
    S <- stats::cov(xy)
    sxx <- S[1, 1]; syy <- S[2, 2]; sxy <- S[1, 2]
    e <- eigen(S, symmetric = TRUE)
    lam <- pmax(e$values, 0)
    if (lam[2] > 0) elong <- sqrt(lam[1] / lam[2])
    v <- e$vectors[, 1]
    orient <- (90 - atan2(v[2], v[1]) * 180 / pi) %% 180
    # The convex hull is contained in the per-row extreme burned cells, so
    # chull on those (a few thousand points) is exact and keeps big fires cheap.
    # Take the cells' outer corners rather than their centres, otherwise the
    # hull is smaller than the cells it contains and the fill ratio exceeds 1.
    ext <- tapply(xy[, 1], xy[, 2], range, simplify = FALSE)
    xmin <- vapply(ext, `[`, numeric(1), 1L) - 0.5
    xmax <- vapply(ext, `[`, numeric(1), 2L) + 0.5
    yy <- as.numeric(names(ext))
    xy_h <- cbind(rep(c(xmin, xmax), each = 2),
                  rep(rep(yy, 2), each = 2) + c(-0.5, 0.5))
    h <- xy_h[grDevices::chull(xy_h), , drop = FALSE]
    if (nrow(h) >= 3) {
      h <- rbind(h, h[1, ])
      a <- abs(sum(h[-nrow(h), 1] * h[-1, 2] - h[-1, 1] * h[-nrow(h), 2])) / 2
      if (a > 0) fill <- n / a
    }
  }

  # Perimeter: burned-cell faces exposed to non-burned, in cells.
  r1 <- min(idx[, 1]); c1 <- min(idx[, 2])
  B <- matrix(FALSE, max(idx[, 1]) - r1 + 3L, max(idx[, 2]) - c1 + 3L)
  B[cbind(idx[, 1] - r1 + 2L, idx[, 2] - c1 + 2L)] <- TRUE
  ii <- 2:(nrow(B) - 1L); jj <- 2:(ncol(B) - 1L)
  core <- B[ii, jj]
  per <- sum(core & !B[ii - 1L, jj]) + sum(core & !B[ii + 1L, jj]) +
         sum(core & !B[ii, jj - 1L]) + sum(core & !B[ii, jj + 1L])

  c(size_cells = n,
    area_ha = n * cell_area_ha,
    perimeter_cells = per,
    compactness = if (per > 0) 4 * pi * n / per^2 else NA_real_,
    elongation = elong,
    orientation = orient,
    hull_fill = fill,
    cov_ee = sxx,
    cov_nn = syy,
    cov_en = sxy)
}


#' Elongation along a given reference axis
#'
#' Takes the covariance entries `fire_shape()` returns and the axis' compass
#' bearing in radians, and gives the spread along that axis over the spread
#' across it. Unlike `fire_shape()`'s `elongation`, this one is signed by
#' direction: a value below 1 means the fire is stretched *across* the axis, and
#' it can never exceed the direction-free `elongation`, which it equals only when
#' the fire's own principal axis happens to coincide with the reference.
#'
#' The axis is unsigned, so it makes no difference whether `bearing` is the
#' direction the wind comes from or the one it blows toward.
elongation_along <- function(cov_ee, cov_nn, cov_en, bearing) {
  if (anyNA(c(cov_ee, cov_nn, cov_en, bearing))) return(NA_real_)
  u <- c(sin(bearing), cos(bearing))          # compass bearing -> (east, north)
  w <- c(u[2], -u[1])                         # the perpendicular
  S <- matrix(c(cov_ee, cov_en, cov_en, cov_nn), 2, 2)
  v_along <- drop(t(u) %*% S %*% u)
  v_across <- drop(t(w) %*% S %*% w)
  if (v_across <= 0 || v_along < 0) return(NA_real_)
  unname(sqrt(v_along / v_across))
}


#' Circular mean of an angle field, with its concentration
#'
#' `angles` in radians. Returns the mean direction in radians on [0, 2*pi) and
#' `rbar`, the mean resultant length: 1 if every cell points the same way, near 0
#' if the field is so terrain-scattered that no single direction represents it.
#' NA cells (the landscapes carry a few tenths of a percent) are dropped.
circ_mean <- function(angles) {
  s <- mean(sin(angles), na.rm = TRUE)
  cc <- mean(cos(angles), na.rm = TRUE)
  if (is.na(s) || is.na(cc)) return(c(mean = NA_real_, rbar = NA_real_))
  c(mean = atan2(s, cc) %% (2 * pi), rbar = sqrt(s^2 + cc^2))
}


#' Split a landscape array into the named matrices the functions above want,
#' without copying the data more than once.
land_matrices <- function(land_array) {
  ln <- dimnames(land_array)[[3]]
  stats::setNames(lapply(ln, function(l) land_array[, , l]), ln)
}
