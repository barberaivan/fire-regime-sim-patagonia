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


#' Donor-centred strata of a fire, with the spread model's own predictors
#'
#' One stratum per burned cell that has at least one burnable unburned
#' neighbour; the stratum's members are that cell's burnable neighbours, and the
#' response is whether each of them burned. This is literally the simulator's
#' own Bernoulli trial set, and holding the donor fixed within a stratum is what
#' identifies the target-cell predictors while conditioning out everything about
#' the fire, the donor and the weather.
#'
#' Predictors match `spread_one_cell_prob()` exactly: `vfi`/`tfi` at the target
#' cell, `slope = sin(atan(dz / dist))` counted only uphill, and
#' `wind = cos(angle_k - wdir_source) * wspeed_source`. The shared intercept is
#' conditioned out by the stratum.
#'
#' Strata whose members all burned, or none of which burned, carry no
#' conditional information and are dropped.
#'
#' @param idx n x 2 integer matrix of burned {row, col}.
#' @param land named list of landscape matrices: veg, vfi, tfi, elevation,
#'   wdir, wspeed (see `land_matrices()`).
#' @param max_strata subsample donors to at most this many. The regression gains
#'   almost nothing past a couple of thousand strata and the largest fires have
#'   hundreds of thousands.
#' @return list with `strat` (integer stratum id), `y` (burned) and `x`
#'   (n x 4 predictor matrix), or NULL if the fire has no usable edge.
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
  ele <- land$elevation[b$r1:b$r2, b$c1:b$c2]
  wdr <- land$wdir[b$r1:b$r2, b$c1:b$c2]
  wsp <- land$wspeed[b$r1:b$r2, b$c1:b$c2]
  don <- cbind(di, dj)

  parts <- vector("list", 8)
  for (k in 1:8) {
    tg <- cbind(di + nb_moves["row", k], dj + nb_moves["col", k])
    keep <- veg[tg] != 99
    if (!any(keep)) next
    dz <- ele[tg] - ele[don]
    parts[[k]] <- cbind(
      strat = sel, y = as.integer(B[tg]),
      vfi = vfi[tg], tfi = tfi[tg],
      slope = ifelse(dz > 0, sin(atan(dz / nb_dist[k])), 0),
      wind = cos(nb_angle[k] - wdr[don]) * wsp[don])[keep, , drop = FALSE]
  }
  d <- do.call(rbind, parts)
  d <- d[rowSums(!is.finite(d)) == 0, , drop = FALSE]
  if (nrow(d) < 40L) return(NULL)

  # keep only strata with a mixed response
  mixed <- stats::ave(d[, "y"], d[, "strat"], FUN = function(z) length(unique(z))) > 1
  d <- d[mixed, , drop = FALSE]
  if (nrow(d) < 40L || length(unique(d[, "strat"])) < 10L) return(NULL)

  list(strat = d[, "strat"], y = d[, "y"], x = d[, 3:6, drop = FALSE])
}


#' Conditional logit over donor strata
#'
#' A thin wrapper on `survival::clogit`. Strata here have up to eight members
#' and often several cases, where the exact conditional likelihood and the
#' Breslow/Efron approximations genuinely differ, so this uses the exact method
#' rather than a hand-rolled approximation — at ~0.1 s per fire including
#' extraction it is affordable, and it keeps the statistic standard.
#'
#' Fires whose strata separate return large coefficients; they are flagged
#' rather than dropped, since the same thing happens to observed fires with few
#' strata and the analysis conditions on fire size anyway.
edge_clogit <- function(s) {
  d <- data.frame(y = s$y, strat = s$strat, s$x)
  fit <- try(survival::clogit(y ~ vfi + tfi + slope + wind + strata(strat),
                              data = d, method = "exact"), silent = TRUE)
  nm <- c("vfi", "tfi", "slope", "wind")
  if (inherits(fit, "try-error")) {
    out <- c(stats::setNames(rep(NA_real_, 4), nm), converged = 0)
  } else {
    out <- c(coef(fit)[nm], converged = as.numeric(!is.null(fit$iter)))
  }
  c(out,
    n_strata = length(unique(s$strat)),
    n_rows = nrow(s$x),
    stats::setNames(apply(s$x, 2, stats::sd), paste0("sdx_", nm)))
}


#' Shape metrics from the burned cells
#'
#' All in raster space, all sub-millisecond. `orientation` is the bearing of the
#' leading principal axis in degrees (mod 180), directly comparable to the fixed
#' 293-degree wind the landscapes were built with: fire runs along the
#' 113/293 axis, so orientation near 113 means wind-aligned.
fire_shape <- function(idx, cell_area_ha = 0.09) {
  n <- nrow(idx)
  if (n == 0) return(NULL)
  xy <- cbind(as.numeric(idx[, 2]), -as.numeric(idx[, 1]))   # east, north

  elong <- orient <- fill <- NA_real_
  if (n >= 3) {
    e <- eigen(stats::cov(xy), symmetric = TRUE)
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
    hull_fill = fill)
}


#' Split a landscape array into the named matrices the functions above want,
#' without copying the data more than once.
land_matrices <- function(land_array) {
  ln <- dimnames(land_array)[[3]]
  stats::setNames(lapply(ln, function(l) land_array[, , l]), ln)
}
