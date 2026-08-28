# The observed side of the spread model's pattern-oriented validation.
#
# Runs exactly the same measurements the simulated fires got in
# spread/validation_simulate.R — `fire_shape()` for the shape metrics and
# `donor_strata()` + `edge_clogit()` for the per-fire spatial signature — over
# every mapped fire, and saves one row per fire. That symmetry is the whole
# point of the protocol: the two sides must be the same function.
#
# The observed set comes from two sources, and both are already on disk:
#   * the 57 focal fires — data/focal_fires/landscapes/*.rds, the very arrays
#     the spread model was fitted on (6 layers, wind included);
#   * the 184 fires with no ignition point — data/signature_landscapes/
#     landscapes/*.rds, the reduced 3-layer landscapes built by
#     data_prep/landscapes_preparation.R.
# Together they are the 241 features of patagonian_fires_spread.
#
# What is NOT computed here, deliberately: anything directional. `elong_wind`
# on the simulated side is measured against each fire's own WindNinja field,
# and the 184 have no wind layer. The observed counterpart is `elong_fixed`,
# elongation along the fixed 293 degrees every landscape in this repo was
# driven with — which is why validation_simulate.R saved the covariance entries
# too, so the simulated fires can be given the same treatment post hoc.
#
# Runtime: a few minutes, dominated by reading the 57 big focal landscapes.

library(survival)
source(file.path("R", "spread_validation_functions.R"))

# Settings ----------------------------------------------------------------

seed <- 20260828       # donor_strata() subsamples donors
max_strata <- 1500     # as in spread/validation_simulate.R
wind_bearing <- 293 * pi / 180   # the fixed direction the landscapes were built with
out_dir <- file.path("files", "spread_validation")

focal_dir <- file.path("data", "focal_fires", "landscapes")
sig_dir <- file.path("data", "signature_landscapes", "landscapes")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
set.seed(seed)

# The fires ---------------------------------------------------------------

focal_ids <- sub("\\.rds$", "", list.files(focal_dir, pattern = "\\.rds$"))
sig_ids <- sub("\\.rds$", "", list.files(sig_dir, pattern = "\\.rds$"))

if (length(sig_ids) == 0) {
  stop("No reduced landscapes in ", sig_dir,
       " — run data_prep/landscapes_preparation.R with do_signature <- TRUE")
}
stopifnot(!any(focal_ids %in% sig_ids))

fires <- data.frame(
  fire_id = c(focal_ids, sig_ids),
  source = rep(c("focal", "signature"), c(length(focal_ids), length(sig_ids))),
  path = c(file.path(focal_dir, paste0(focal_ids, ".rds")),
           file.path(sig_dir, paste0(sig_ids, ".rds")))
)
n_fires <- nrow(fires)
cat(n_fires, "mapped fires:", length(focal_ids), "focal +",
    length(sig_ids), "reduced\n")

# Two fires were split in two for the fit, so they have two landscapes but one
# row in the climatic tables. And two fires carry a different year label in
# `patagonian_fires_spread` than in the base mapped record the climatic tables
# were keyed on — same fires, different id string (docs/spread.md -> "How many
# fires?"). Both are aliases to resolve before the FWI join; fires the table
# genuinely does not cover keep NA, and there are six of those.
split_fires <- c("2015_47N" = "2015_47", "2015_47S" = "2015_47",
                 "2011_19E" = "2011_19", "2011_19W" = "2011_19",
                 "1999_1546963766" = "2000_1546963766",
                 "2014_-1075171770" = "2016_-1075171770")
fires$fire_id_climate <- ifelse(fires$fire_id %in% names(split_fires),
                                split_fires[fires$fire_id], fires$fire_id)
fwi_tab <- read.csv(file.path("data",
  "climatic_data_by_fire_fwi-fortnight-cumulative_FWIZ2.csv"))
fires$fwi <- fwi_tab$fwi_fort_expquad[match(fires$fire_id_climate,
                                            fwi_tab$fire_id)]
cat("FWI available for", sum(!is.na(fires$fwi)), "of", n_fires, "landscapes",
    "| without:", paste(fires$fire_id[is.na(fires$fwi)], collapse = ", "), "\n")


# Measure -----------------------------------------------------------------

cl_names <- c("vfi", "tfi", "converged", "n_strata", "n_rows",
              "sdx_vfi", "sdx_tfi")

shape_rows <- vector("list", n_fires)
sig_rows <- vector("list", n_fires)

t0 <- Sys.time()
for (i in seq_len(n_fires)) {
  cat(i, "/", n_fires, "-", fires$fire_id[i], "")
  l <- readRDS(fires$path[i])

  idx <- t(l$burned_ids) + 1L          # stored 0-indexed, for C++
  land <- land_matrices(l$landscape)   # extra layers are ignored downstream

  shape <- fire_shape(idx)
  shape <- c(shape,
             elong_fixed = elongation_along(shape["cov_ee"], shape["cov_nn"],
                                            shape["cov_en"], wind_bearing))
  shape_rows[[i]] <- shape

  st <- donor_strata(idx, land, max_strata = max_strata)
  sig_rows[[i]] <- if (is.null(st)) {
    stats::setNames(rep(NA_real_, length(cl_names)), cl_names)
  } else edge_clogit(st)

  cat("- ", round(shape["area_ha"]), " ha, b_vfi ",
      round(sig_rows[[i]]["vfi"], 2), "\n", sep = "")
  rm(l, land); gc(verbose = FALSE)
}
cat("measured in", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1),
    "min\n")

meta <- fires[, c("fire_id", "fire_id_climate", "source", "fwi")]

shape_tab <- cbind(meta, as.data.frame(do.call(rbind, shape_rows)))
sig <- as.data.frame(do.call(rbind, sig_rows))
names(sig)[1:2] <- c("b_vfi", "b_tfi")
sig_tab <- cbind(meta, area_ha = shape_tab$area_ha,
                 size_cells = shape_tab$size_cells, sig)

saveRDS(sig_tab, file.path(out_dir, "observed_signature.rds"))
saveRDS(shape_tab, file.path(out_dir, "observed_shape.rds"))


# Report ------------------------------------------------------------------

cat("\n-- signature --\n")
cat("fitted:", sum(!is.na(sig_tab$b_vfi)), "of", n_fires,
    "| converged:", sum(sig_tab$converged == 1, na.rm = TRUE),
    "| no usable edge (donor_strata NULL):", sum(is.na(sig_tab$b_vfi)), "\n")
cat("by source:\n")
print(table(sig_tab$source, fitted = !is.na(sig_tab$b_vfi)))

size_class <- cut(sig_tab$area_ha, c(0, 100, 1000, Inf),
                  labels = c("< 100 ha", "100-1000 ha", "> 1000 ha"))

summarise <- function(x, g) {
  ok <- !is.na(x)
  data.frame(n = tapply(ok, g, sum),
             median = round(tapply(x, g, median, na.rm = TRUE), 3),
             q25 = round(tapply(x, g, quantile, .25, na.rm = TRUE), 2),
             q75 = round(tapply(x, g, quantile, .75, na.rm = TRUE), 2),
             frac_pos = round(tapply(x, g, function(z) mean(z > 0, na.rm = TRUE)), 2))
}

for (nm in c("b_vfi", "b_tfi")) {
  cat("\n", nm, " — all ", n_fires, " fires\n", sep = "")
  print(summarise(sig_tab[[nm]], size_class))
  cat("  overall median", round(median(sig_tab[[nm]], na.rm = TRUE), 3),
      "| frac > 0", round(mean(sig_tab[[nm]] > 0, na.rm = TRUE), 2), "\n")
  f <- sig_tab$source == "focal"
  cat("  57 focal only: median", round(median(sig_tab[[nm]][f], na.rm = TRUE), 3),
      "| IQR [", paste(round(quantile(sig_tab[[nm]][f], c(.25, .75), na.rm = TRUE), 2),
                       collapse = ", "),
      "] | frac > 0", round(mean(sig_tab[[nm]][f] > 0, na.rm = TRUE), 2), "\n")
  cat("  57 focal, by size class:\n")
  print(summarise(sig_tab[[nm]][f], size_class[f]))
}

cat("\n-- shape --\n")
print(round(sapply(shape_tab[, c("area_ha", "elongation", "elong_fixed",
                                 "compactness", "hull_fill")],
                   quantile, c(.05, .25, .5, .75, .95), na.rm = TRUE), 3))
ori <- shape_tab$orientation
aligned <- pmin(abs(ori - 113), 180 - abs(ori - 113)) <= 30
cat("orientation within 30 deg of the 113/293 axis:",
    round(mean(aligned, na.rm = TRUE) * 100, 1), "% of",
    sum(!is.na(ori)), "fires\n")
cat("  by size class:\n")
print(round(tapply(aligned, size_class, mean, na.rm = TRUE) * 100, 1))
cat("  elongation median by size class:\n")
print(round(tapply(shape_tab$elongation, size_class, median, na.rm = TRUE), 2))

cat("\nsaved", file.path(out_dir, "observed_signature.rds"), "and",
    file.path(out_dir, "observed_shape.rds"), "\n")
