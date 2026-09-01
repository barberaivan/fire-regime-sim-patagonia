# Shared setup for the spread paper's MODEL figures — Figs. 2, 3 and 4 and the
# supplementary S1-S5 (spread/figure_spread_curves.R, figure_params_fwi.R,
# figure_vegetation_effect.R, figure_flammability_indices.R,
# figure_parameter_correlations.R, figure_focal_fit.R).
#
# Every one of those figures used to live inside spread/hierarchical_fit.R, a
# 3000-line fitting script that has to be run top to bottom before any of its
# plotting blocks will evaluate. They are here instead because a figure should
# be re-drawable in seconds from what the fit already wrote to
# files/hierarchical_model/, without re-fitting anything and without the ~40
# packages the fit loads. What each figure needs from disk is listed in its own
# header; this file holds only the pieces they share.
#
# Two conventions the paper figures follow and this file encodes:
#
#   * PARAMETER NAMES are the manuscript's, not the code's. The code calls them
#     intercept / vfi / tfi / slope / wind / steps; the paper calls them
#     beta_0 ... beta_4 and kappa (spread-paper.tex, Eqn 3 and the paragraph
#     after it). `par_labels()` is the one place that mapping is written.
#   * FWI IS SHOWN AT ITS ORIGINAL SCALE. The fit standardizes FWI across the
#     235 fires, so a model-internal FWI of 0 is an anomaly of +0.86, not an
#     average fire day. Every axis and legend that names an FWI value uses
#     `fwi_to_original()` and reads in anomaly units, so Figs. 2, 3 and 4 can
#     be compared to each other and to the text.
#
# The parameter bounds, `invlogit_scaled2()` and the per-fire FWI lookup come
# from R/focal_simulation_functions.R, which these scripts also source.

#' Posterior summary of a vector of draws
#'
#' Byte-for-byte the `summarise()` of spread/hierarchical_fit.R, renamed so it
#' does not mask `dplyr::summarise()` in scripts that load the tidyverse.
#' Returns a named vector: mean, HDIs at 80/90/95 %, and equal-tailed
#' quantiles at the same levels plus the median.
summarise_post <- function(x) {
  q <- stats::quantile(x, probs = c(0.025, 0.05, 0.1, 0.5, 0.9, 0.95, 0.975),
                       method = 8)
  names(q) <- c("eti_lower_95", "eti_lower_90", "eti_lower_80", "median",
                "eti_upper_80", "eti_upper_90", "eti_upper_95")

  hdi_95 <- bayestestR::hdi(x, ci = 0.95)
  hdi_90 <- bayestestR::hdi(x, ci = 0.90)
  hdi_80 <- bayestestR::hdi(x, ci = 0.80)

  hdis <- c(
    "hdi_lower_95" = hdi_95$CI_low, "hdi_lower_90" = hdi_90$CI_low,
    "hdi_lower_80" = hdi_80$CI_low,
    "hdi_upper_80" = hdi_80$CI_high, "hdi_upper_90" = hdi_90$CI_high,
    "hdi_upper_95" = hdi_95$CI_high
  )

  c("mean" = mean(x), hdis, q)
}


#' The plot theme every figure in the spread paper uses
#'
#' Copied from spread/hierarchical_fit.R so the paper figures keep the look of
#' the thesis ones: no panel border, no grid, a thin axis line, white strips.
#' Applied on top of `theme_bw()`, which the scripts set with `theme_set()`.
nice_theme <- function() {
  ggplot2::theme(
    panel.border = ggplot2::element_blank(),
    panel.grid = ggplot2::element_blank(),

    axis.line = ggplot2::element_line(linewidth = 0.3),

    axis.text = ggplot2::element_text(size = 9),
    axis.title = ggplot2::element_text(size = 11),

    strip.text = ggplot2::element_text(size = 11),
    strip.background = ggplot2::element_rect(fill = "white", color = "white")
  )
}

# The dark strip of the faceted figures (Figs. 6, S2, S3), so the paper's
# figures agree on it.
strip_bgcol <- "#1a1a1a"

# The five vegetation classes, in the order every array in this project stores
# them, with the labels the paper prints.
veg_names <- c("wet", "subalpine", "dry", "shrubland", "grassland")
veg_levels <- c("Wet forest", "Subalpine forest", "Dry forest", "Shrubland",
                "Grassland")


#' Manuscript labels for the six spread parameters
#'
#' The code's names in, printable labels out. Symbols as in spread-paper.tex:
#' beta_0 the intercept, beta_1 VFI, beta_2 TFI, beta_3 slope, beta_4 wind,
#' kappa the number of steps. The gloss in brackets is kept because a reader
#' meeting a bare subscripted beta in a six-panel figure has to go back to the
#' equation to know which is which.
#'
#' Written with literal Unicode subscripts rather than as plotmath, because
#' plotmath drops the space between an expression and the string after it when
#' the text is ROTATED — which is exactly what a left-placed facet strip does,
#' so `beta[0]~"(intercept)"` comes out with the subscript sitting on the
#' bracket. The cost is that the figures must be written through a device that
#' can draw U+2080-2084; `save_fig()` uses cairo for that.
#'
#' @param x code names, defaulting to all six in model order.
par_labels <- function(x = c("intercept", "vfi", "tfi", "slope", "wind",
                             "steps")) {
  map <- c(intercept = "\u03b2\u2080 (intercept)",
           vfi       = "\u03b2\u2081 (VFI)",
           tfi       = "\u03b2\u2082 (TFI)",
           slope     = "\u03b2\u2083 (slope)",
           wind      = "\u03b2\u2084 (wind)",
           steps     = "\u03ba (steps)")
  unname(map[x])
}


#' The FWI scaling the fit used
#'
#' @return list with `fwi_mean`, `fwi_sd`, as written by
#'   spread/hierarchical_fit.R.
fwi_scale <- function(file = file.path("files", "hierarchical_model",
                                       "fwi_mean_sd_spread.rds")) {
  readRDS(file)
}


#' Standardized FWI back to the anomaly scale the paper reports
#'
#' The inverse of the fit's `(fwi - mean) / sd`. Note the two scales are easy
#' to confuse: FWI was ALREADY a pixel-level standardized anomaly before the
#' fit standardized it again across fires, so "0" means different things on the
#' two of them (a model-internal 0 is an anomaly of about +0.86).
fwi_to_original <- function(z, scale = fwi_scale()) {
  z * scale$fwi_sd + scale$fwi_mean
}


#' Standardized FWI of all 235 fires in the fit, in the fit's own order
#'
#' `fwi_all` in spread/hierarchical_fit.R: the 57 fires with an ignition point
#' first (the rows of `draws$ranef`), then the 178 without (the rows of
#' `draws$steps`). Reconstructed from the posterior object's dimnames rather
#' than re-derived from the climatic tables, so it cannot drift out of step
#' with the fit that is actually on disk.
#'
#' Only its range and quantiles are used by the figures — that is what sets the
#' x range of Fig. 3 and the three FWI levels of Figs. 2 and S2.
spread_fwi_all <- function(draws) {
  ids <- c(dimnames(draws$ranef)[[2]], dimnames(draws$steps)[[1]])
  z <- focal_fwi_z(ids)          # handles the split fires' id aliases
  if (anyNA(z)) {
    stop("no FWI for ", sum(is.na(z)), " of the fit's fires: ",
         paste(names(z)[is.na(z)], collapse = ", "))
  }
  z
}


#' Save a figure as both .png and .pdf into manuscript-spread/figures/
#'
#' The PDF goes through `cairo_pdf`, not the default `pdf()` device: the
#' parameter labels carry Unicode subscripts (`par_labels()`) and the base
#' device cannot draw them.
#'
#' @param name file stem, e.g. "fig2_spread_curves".
save_fig <- function(plot, name, width, height,
                     dir = file.path("manuscript-spread", "figures"),
                     dpi = 350) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  for (ext in c("png", "pdf")) {
    f <- file.path(dir, paste0(name, ".", ext))
    ggplot2::ggsave(f, plot = plot, width = width, height = height,
                    units = "cm", dpi = dpi, bg = "white",
                    device = if (ext == "pdf") grDevices::cairo_pdf else NULL)
    cat("wrote", f, "\n")
  }
}
