# Ignition candidates for the spread model's validation simulation.
#
# Run once. For each study-area tile it writes
#   * cells:  the eligible ignition cells (tile ∩ study area ∩ burnable), as a
#             2-column integer matrix of {row, col} sorted by row, so that the
#             cells admitting a given margin in the row direction form one
#             contiguous slice;
#   * n_valid: how many eligible cells survive eroding the tile by s cells on
#             every side, for s = 0 … steps_max.
#
# `n_valid` is what makes the simulation unbiased. A fire is simulated only on a
# sublandscape that lets it reach its full `steps` budget in every direction, so
# it can never be cut short by a tile border — but that rule removes cells near
# the borders, and it removes more of them the larger `steps` is. Redrawing the
# ignition cell until it fits would therefore reject large-`steps` fires more
# often and silently shrink the simulated size distribution. Instead the driver
# draws `steps` first and then picks the tile with probability proportional to
# n_valid[[k]][s], which is exactly "uniform over every eligible cell in the
# whole study area that admits margin s" and leaves the marginal distribution of
# `steps` untouched.
#
# Burnability is read from the landscape arrays rather than the raw GEE
# exports, because build_landscape() also turns cells with a missing predictor
# non-burnable, and those must not be ignition candidates either.

library(terra)
source(file.path("R", "config.R"))

K <- 4
steps_max <- 2000   # Umax in spread/hierarchical_fit.R; stepsU never exceeds it

land_dir <- file.path("data", "simulation_landscapes", "landscapes")
out_dir <- file.path("files", "spread_validation")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

study_area <- vect(file.path("data", "patagonian_fires", "study_area.shp"))

ig <- vector("list", K)

for (k in 1:K) {
  cat("tile", k, "/", K, "\n")
  land <- readRDS(file.path(land_dir, sprintf("study_area_tile_%d.rds", k)))
  veg <- land$landscape[, , "veg"]
  R <- nrow(veg); C <- ncol(veg)

  # Study-area mask on the tile's own grid, from the saved template.
  tmpl <- unwrap(land$template)
  sa <- project(study_area, crs(tmpl))
  inside <- matrix(values(rasterize(sa, tmpl, field = 1, background = 0))[, 1],
                   R, C, byrow = TRUE) == 1

  elig <- (veg != 99) & inside
  elig[is.na(elig)] <- FALSE
  rm(land, veg, tmpl, inside); gc()

  # n_valid[s + 1] = eligible cells in the rectangle eroded by s, via an
  # integral image so the whole curve costs one pass over the tile.
  I <- apply(apply(elig, 2, cumsum), 1, cumsum)
  I <- t(I)
  box <- function(r1, r2, c1, c2) {
    if (r1 > r2 || c1 > c2) return(0)
    I[r2, c2] -
      (if (r1 > 1) I[r1 - 1, c2] else 0) -
      (if (c1 > 1) I[r2, c1 - 1] else 0) +
      (if (r1 > 1 && c1 > 1) I[r1 - 1, c1 - 1] else 0)
  }
  s_seq <- 0:steps_max
  n_valid <- vapply(s_seq, function(s) box(1 + s, R - s, 1 + s, C - s), numeric(1))
  rm(I); gc()

  # Eligible cells, sorted by row.
  w <- which(elig)                       # column-major
  cells <- cbind(row = ((w - 1L) %% R) + 1L,
                 col = ((w - 1L) %/% R) + 1L)
  cells <- cells[order(cells[, "row"]), ]
  storage.mode(cells) <- "integer"
  rm(elig, w); gc()

  ig[[k]] <- list(tile = k, n_row = R, n_col = C,
                  cells = cells, n_valid = n_valid,
                  # row_start[i] = index of the first cell with row >= i, so the
                  # driver can slice by margin without searching.
                  row_index = findInterval(0:R, cells[, "row"]))

  cat("  ", R, "x", C, "cells;", format(nrow(cells), big.mark = ","),
      "eligible (", round(nrow(cells) * 0.09 / 100), "km2 );",
      "retained at steps 200/716/1167:",
      paste(round(n_valid[c(201, 717, 1168)] / n_valid[1], 3), collapse = " / "), "\n")
  gc()
}

names(ig) <- paste0("tile_", 1:K)
saveRDS(ig, file.path(out_dir, "ignition_cells.rds"))

tot <- sum(sapply(ig, function(z) nrow(z$cells)))
cat("\ntotal eligible:", format(tot, big.mark = ","), "cells =",
    round(tot * 0.09 / 100), "km2\n")
cat("tile shares:",
    paste(round(sapply(ig, function(z) nrow(z$cells)) / tot * 100, 1), collapse = " / "),
    "%\n")
