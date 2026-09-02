# Figure 1 — the study area.
#
# A remake, in R, of the QGIS figure the Fire Ecology paper used ("mapa area de
# estudio 6.qgz" -> "01) study area 6.jpeg", Feb 2025). Three panels over the
# same extent, plus a locator inset:
#
#   (A) the fire record — every mapped fire 1999-2022, with the 57 that have a
#       MAPPED IGNITION POINT in their own colour. That split is the only thing
#       this version adds to the published figure, and it is what the spread
#       paper needs: those 57 are the fires the model was fitted to (stage 1 and
#       the burned-area calibration of Fig. 6), the other 178 enter only through
#       the record-wide validation of Fig. 7.
#   (B) elevation.
#   (C) vegetation type, in the classes the spread model uses.
#
# Everything about the design is taken from the QGIS project rather than
# reinvented: EPSG:5343 (POSGAR 2007 / Argentina 1) and the layout's own map
# extent, the colours below, Chile grey against Argentina white, the lakes over
# the elevation panel in a paler blue than over the other two, and the
# international border as a thick dashed grey line (it is simply the Chile
# polygon's own outline).
#
# TWO KNOWN DEPARTURES from the QGIS original, both noted for Iván in
# docs/roadmap.md:
#   * the QGIS map items carry `mapRotation = -1.5` degrees. That 1.5-degree
#     tilt is not reproduced here; the panels are north-up.
#   * the fire layer is `data/patagonian_fires_spread.shp` (241 features), not
#     the 238-feature base record the QGIS figure drew, because only the
#     `_spread` file carries the split ids the 57 focal fires are keyed on.
#
# Inputs: the fire and study-area shapefiles in the repo's store, plus the
# elevation, lake, country/province and vegetation base layers of the old QGIS
# project, which were copied into the store on 2026-09-01 and now live together
# in `data/study_area_figure_layers/` (`R/config.R` -> `study_area_map_dir`;
# provenance in that folder's README.txt). Runs in a couple of minutes, nearly
# all of it reading the 240 MB elevation mosaic and the vegetation raster.

library(terra)
library(ggplot2)
library(tidyterra)
library(viridis)
library(patchwork)
library(sf)
theme_set(theme_bw())

source(file.path("R", "config.R"))
source(file.path("R", "spread_figure_functions.R"))
# for veg_crosswalk(); sources cleanly with terra alone, no FireSpread needed
source(file.path("R", "landscape_functions.R"))

# Settings ----------------------------------------------------------------

map_crs <- "EPSG:5343"

# The layout's own map extent, in EPSG:5343, straight out of the .qgs.
map_ext <- ext(1476449.12, 1622527.39, 5071498.51, 5690988.16)

# The inset covers South America between these lon/lat bounds, drawn in the
# SAME CRS as the panels. EPSG:5343 is a transverse Mercator centred on 72
# degrees W, so a continent-wide view in it is badly stretched towards Brazil —
# that is what the published figure shows, and it is kept. The bounds also
# throw away Easter Island and South Georgia, which would otherwise set the
# extent and shrink the continent to nothing.
inset_bbox <- ext(-82, -33, -57, 14)

# Colours, from the QGIS project's symbology.
col_chile <- "grey83"          # land outside Argentina
col_border <- "grey45"         # the provincial boundaries, dashed
col_lake <- "#1DCCE3"          # lakes over panels A and C
col_lake_pale <- "#CAEEFC"     # lakes over the elevation panel

# The fires and the study-area outline are three points of ONE magma ramp, so
# panel A reads as a single family and sits beside panel C's inferno
# vegetation. Positions, not names: 0.12 is the near-black end for the outline,
# 0.38 the deep purple-magenta that marks the 57 fires with a mapped ignition
# point, 0.60 the rose the rest of the record takes. Far enough apart on the
# ramp to differ in hue AND in lightness, which is what makes them tell apart
# at the size these polygons are drawn — and the darker of the two is the
# highlighted subset, since it is the one the eye should stop on. The lakes
# stay cyan, as published: a lake has to read as water, not as a fourth level
# of the fire scale.
col_study <- viridis::magma(1, begin = 0.12)     # "#1B1043"
col_fire <- viridis::magma(1, begin = 0.60)      # "#DE4968"
col_fire_ig <- viridis::magma(1, begin = 0.38)   # "#842681"

# WHICH VEGETATION MAP PANEL C DRAWS.
#
#   "merged"  the CIEFAP + Lara99 merge the spread model actually runs on,
#             coarsened to 120 m by the GEE script <Vegetation merged export
#             for study area map> in ~/dev/fire_spread-gee. Classes are the
#             model's own: the five burnable ones plus non-burnable.
#   "lara"    the WWF / Lara et al. (1999) raster the published QGIS figure
#             drew, in its own 8 display classes. Keeps continuity with the
#             Fire Ecology paper, but is not the landscape the model sees.
#
# Both rasters live in `data/study_area_figure_layers/` with the other base
# layers.
#
# The two differ in more than resolution: the merge patches every pixel burned
# before 2014 with Lara cover and takes the rest from CIEFAP 2016, and its
# classes come through `veg_crosswalk()` — the same table the landscape builder
# reads — so under "merged" the figure cannot drift away from the model.
veg_source <- "merged"

# Where the GEE export lands once it has been run and moved into the store.
veg_merged_file <- file.path(config$study_area_map_dir,
                             "vegetation_merged_120m.tif")

# The vegetation ramp: inferno sampled at 8 levels, as set in the QGIS project
# (and in the old `study area map/study_area_map_colors.R`). Under "lara" the
# last two classes share a colour and one legend entry, exactly as the
# published figure does; "merged" has no anthropogenic classes of its own
# (plantation folds into shrubland, urban into non-burnable) and so uses the
# first six colours only.
veg_colors_lara <- c("#000000", "#6b186e", "#a82e5f", "#dd513a",
                     "#f98c0a", "#f6d645", "#fcffa4", "#fcffa4")
# The seventh label is wrapped by hand: on one line it runs past the edge of
# the page, and `guide_legend` does not wrap.
veg_labels_lara <- c("Non-burnable", "Subalpine forest", "Wet forest",
                     "Dry forest", "Shrubland", "Grassland",
                     "Anthropogenic prairie\nand plantation", NA)

veg_colors_merged <- veg_colors_lara[1:6]
veg_labels_merged <- veg_labels_lara[1:6]

# The QGIS project ran the ramp to the study area's true maximum, 3200 m, which
# spends most of viridis on ground that barely exists: almost every peak here
# tops out near 2200 m, and only Tronador and Lanín go well above it, over a
# tiny area. Clamping at 2400 (`oob = squish`, so those two summits sit at the
# top colour rather than dropping out) puts the contrast where the landscape
# actually is.
elev_limits <- c(200, 2400)

# Raster cells actually rendered. The elevation mosaic is 121 million cells at
# 30 m and the panel is 3 cm wide; drawing it at full resolution is minutes of
# nothing.
maxcell_plot <- 3e6

fig_dir <- file.path("manuscript-spread", "figures")

sam_dir <- config$study_area_map_dir
if (!dir.exists(sam_dir)) {
  stop("missing base-layer folder: ", sam_dir,
       "\n  it is part of the store — run ./setup.sh, or edit R/config.R",
       " (study_area_map_dir)")
}

# Data --------------------------------------------------------------------

to_map <- function(x) project(x, map_crs)

study_area <- to_map(vect(file.path("data", "patagonian_fires",
                                    "study_area.shp")))

# Every mapped fire, split by whether the spread model has an ignition point
# for it. The 57 are exactly the focal landscapes.
fires <- vect(file.path("data", "patagonian_fires_spread.shp"))
focal_ids <- sub("\\.rds$", "",
                 list.files(file.path("data", "focal_fires", "landscapes"),
                            pattern = "\\.rds$"))
stopifnot(all(focal_ids %in% fires$fire_id))
fires$has_ignition <- fires$fire_id %in% focal_ids
fires <- to_map(fires)
cat(nrow(fires), "mapped fires,", sum(fires$has_ignition),
    "with a mapped ignition point\n")

lakes <- to_map(vect(file.path(sam_dir, "lakes.shp")))

# Chile: the grey half of every panel. The international border needs no line
# of its own — it is where the grey meets the white.
countries <- vect(file.path(sam_dir, "countries_ign.shp"))
chile <- to_map(countries[countries$nom_abrev == "Chile", ])
stopifnot(nrow(chile) > 0)

# The thick dashed grey lines crossing the panels are the boundaries between
# the three Argentine provinces the study area spans — the ones panel C names.
# Drawn as the provinces' own outlines: within this extent that gives the
# Neuquén / Río Negro line and the Río Negro / Chubut line, and nothing else
# (their eastern edges are hundreds of km off-panel, and their western one runs
# along the international border, under the grey/white edge).
# From the bicontinental project's IGN layer, not the FAO GAUL one in the same
# folder: GAUL's Argentina is missing six provinces, Río Negro and Chubut among
# them.
prov_names <- c("Neuquén", "Río Negro", "Chubut")
provinces_all <- vect(file.path(sam_dir, "provinces_ign.shp"))
provinces <- provinces_all[provinces_all$NAM %in% prov_names, ]
stopifnot(nrow(provinces) == length(prov_names))
provinces <- to_map(provinces)

# Both rasters are drawn only inside the study area, as in the published
# figure, and each is clipped in ITS OWN CRS — the elevation and Lara layers
# are lon/lat, the merged export is already EPSG:5343, and reprojecting before
# masking would resample 121 million cells for nothing.
study_area_ll <- vect(file.path("data", "patagonian_fires", "study_area.shp"))
clip_to_study <- function(r) {
  sa <- project(study_area_ll, crs(r))
  mask(crop(r, sa), sa)
}

elev <- rast(file.path(sam_dir, "elevation_study_area.tif"))
names(elev) <- "elevation"
elev <- clip_to_study(elev)

#' Panel C's vegetation layer, as a factor raster, plus its legend
#'
#' Returns the raster with one level per legend entry, in the order the legend
#' prints them, and the labels and colours to go with it.
veg_layer <- function(source) {
  if (source == "lara") {
    r <- rast(file.path(sam_dir, "vegetation_lara.tif"))
    names(r) <- "class"
    r <- clip_to_study(r)
    labels <- veg_labels_lara
    colors <- veg_colors_lara
    # The file is already coded 1-8 in the published figure's own display
    # classes, so the levels are the values.
    r <- as.factor(r)
    lev <- levels(r)[[1]]
    lev$label <- labels[as.integer(lev[[1]])]
    levels(r) <- lev[, c(1, ncol(lev))]
    return(list(raster = r, labels = labels[!is.na(labels)], colors = colors))
  }

  if (!file.exists(veg_merged_file)) {
    stop("panel C is set to the merged vegetation map, but\n  ",
         veg_merged_file, "\nis not there yet. Run the GEE task ",
         "<Vegetation merged export for study area map> in\n",
         "  ~/dev/fire_spread-gee, then move the .tif from Drive into that ",
         "folder.\nOr set `veg_source <- \"lara\"` to draw the published ",
         "raster instead.")
  }

  r <- rast(veg_merged_file)[[1]]
  names(r) <- "class"
  r <- clip_to_study(r)

  # The export carries the merge's own `cnum1` codes, 1-11. Reclass through
  # the SAME crosswalk the landscape builder uses, keyed on `cnum_spread`
  # rather than on `class2`: that is the column that says what the model
  # actually does with a class, and it is where Urban parts company with
  # Grassland. `urban_as = "nonburnable"` matches the simulation landscapes —
  # over a 600 km region holding Bariloche, Esquel and El Bolsón, drawing the
  # towns as burnable grassland would be wrong on the map for the same reason
  # it is wrong in the simulator.
  dveg <- veg_crosswalk(urban_as = "nonburnable")
  level_of <- c("0" = 3, "1" = 2, "2" = 4, "3" = 5, "4" = 6, "99" = 1)
  stopifnot(all(as.character(dveg$cnum_spread) %in% names(level_of)))

  # `others = NA` sends the export's 0 no-data value, and any code the
  # crosswalk does not cover, to transparent.
  r <- classify(r, cbind(dveg$cnum1,
                         unname(level_of[as.character(dveg$cnum_spread)])),
                others = NA)
  r <- as.factor(r)
  lev <- levels(r)[[1]]
  lev$label <- veg_labels_merged[as.integer(lev[[1]])]
  levels(r) <- lev[, c(1, ncol(lev))]

  list(raster = r, labels = veg_labels_merged, colors = veg_colors_merged)
}

vl <- veg_layer(veg_source)
veg <- vl$raster
veg_labels <- vl$labels
veg_colors <- vl$colors
cat("panel C: ", veg_source, " vegetation, ", length(veg_labels),
    " classes, ", ncell(veg), " cells\n", sep = "")

# Panels ------------------------------------------------------------------

# Where the graticule falls. Fixed by hand, as in the QGIS layout: the panel is
# 5.4 degrees tall and 1.6 wide, so one meridian every degree and one parallel
# every two is all that fits.
lon_breaks <- c(-72, -71)
lat_breaks <- c(-40, -42, -44)

#' The frame every panel shares
#'
#' @param labels which axes carry graticule labels; "-" for none. Panel A takes
#'   them, B and C only the lines, so the three read as one map.
map_frame <- function(labels = FALSE) {
  list(
    coord_sf(xlim = c(map_ext[1], map_ext[2]),
             ylim = c(map_ext[3], map_ext[4]),
             expand = FALSE, datum = st_crs(4326)),
    scale_x_continuous(breaks = lon_breaks),
    scale_y_continuous(breaks = lat_breaks),
    theme(
      panel.background = element_rect(fill = "white", colour = NA),
      panel.border = element_rect(colour = "black", fill = NA,
                                  linewidth = 0.4),
      panel.grid = element_line(colour = "grey45", linetype = "dashed",
                                linewidth = 0.25),
      panel.ontop = FALSE,
      axis.title = element_blank(),
      axis.text = if (labels) element_text(size = 7, colour = "grey20")
                  else element_blank(),
      axis.ticks = if (labels) element_line(colour = "grey20",
                                            linewidth = 0.25)
                   else element_blank(),
      plot.margin = margin(1, 1, 1, 1, unit = "mm")
    )
  )
}

# Chile grey, then the provincial boundaries, under everything else.
base_layers <- list(
  geom_spatvector(data = chile, fill = col_chile, colour = NA),
  geom_spatvector(data = provinces, fill = NA, colour = col_border,
                  linetype = "dashed", linewidth = 0.45)
)

outline_layer <- geom_spatvector(data = study_area, fill = NA,
                                 colour = col_study, linewidth = 0.45)

#' A label placed by its relative position inside the panel
at <- function(fx, fy) {
  c(map_ext[1] + fx * (map_ext[2] - map_ext[1]),
    map_ext[3] + fy * (map_ext[4] - map_ext[3]))
}

panel_letter <- function(letter) {
  p <- at(0.10, 0.965)
  annotate("text", x = p[1], y = p[2], label = letter, size = 13 / .pt,
           hjust = 0, vjust = 1)
}

# Panel A — the fire record -----------------------------------------------

# Panel A's four things go through ONE legend, so it comes out of the plot
# rather than being drawn by hand. The trick is that every layer maps BOTH
# `fill` and `colour` to the same four-level factor, and the two manual scales
# are given the same name, breaks and labels — ggplot then merges them into a
# single guide, and the study area gets a key with no fill and a violet border
# while the other three get a filled key with no border.
a_levels <- c("Study area", "Fires", "Fires with known\nignition point",
              "Lakes")
a_fill <- setNames(c(NA, col_fire, col_fire_ig, col_lake), a_levels)
a_colour <- setNames(c(col_study, NA, NA, NA), a_levels)

fires$class <- ifelse(fires$has_ignition, a_levels[3], a_levels[2])
lakes$class <- a_levels[4]
study_area$class <- a_levels[1]

a_scales <- function(...) {
  args <- list(name = NULL, breaks = a_levels, limits = a_levels,
               guide = guide_legend(keywidth = unit(4, "mm"),
                                    keyheight = unit(4, "mm")))
  list(do.call(scale_fill_manual, c(list(values = a_fill), args)),
       do.call(scale_colour_manual, c(list(values = a_colour), args)))
}

p_a <- ggplot() +
  base_layers +
  geom_spatvector(data = study_area, aes(fill = class, colour = class),
                  linewidth = 0.45) +
  geom_spatvector(data = lakes, aes(fill = class, colour = class),
                  linewidth = 0) +
  geom_spatvector(data = fires[!fires$has_ignition, ],
                  aes(fill = class, colour = class), linewidth = 0) +
  geom_spatvector(data = fires[fires$has_ignition, ],
                  aes(fill = class, colour = class), linewidth = 0) +
  a_scales() +
  annotate("text", x = at(0.06, 0.10)[1], y = at(0.06, 0.10)[2],
           label = "Chile", angle = 90, size = 8 / .pt, hjust = 0) +
  annotate("text", x = at(0.93, 0.10)[1], y = at(0.93, 0.10)[2],
           label = "Argentina", angle = 90, size = 8 / .pt, hjust = 0) +
  panel_letter("A") +
  map_frame(labels = TRUE)

# Panel B — elevation -----------------------------------------------------

p_b <- ggplot() +
  base_layers +
  geom_spatraster(data = elev, maxcell = maxcell_plot) +
  scale_fill_viridis_c(option = "D", limits = elev_limits, oob = scales::squish,
                       na.value = "transparent", name = "Elevation (m a.s.l.)",
                       breaks = elev_limits,
                       guide = guide_colourbar(
                         title.position = "top", direction = "vertical",
                         barwidth = unit(4, "mm"),
                         barheight = unit(18, "mm"))) +
  geom_spatvector(data = lakes, fill = col_lake_pale, colour = NA) +
  outline_layer +
  panel_letter("B") +
  map_frame()

# Panel C — vegetation ----------------------------------------------------

p_c <- ggplot() +
  base_layers +
  # The vegetation layer is never downsampled: `maxcell` would resample a
  # categorical raster, and a class that is the average of two others does not
  # exist. It is small enough to draw whole either way.
  geom_spatraster(data = veg, maxcell = max(maxcell_plot, ncell(veg))) +
  scale_fill_manual(values = setNames(veg_colors, veg_labels),
                    breaks = veg_labels[!is.na(veg_labels)],
                    na.value = "transparent", na.translate = FALSE,
                    name = "Vegetation type",
                    guide = guide_legend(keywidth = unit(4, "mm"),
                                         keyheight = unit(4, "mm"))) +
  geom_spatvector(data = lakes, fill = col_lake, colour = NA) +
  outline_layer +
  # The three provinces, centred on their own share of the panel, in the white
  # strip east of the study area. Positions by hand, as in the QGIS layout.
  annotate("text", x = at(0.93, 0.84)[1], y = at(0.93, 0.84)[2],
           label = "Neuquén", angle = 90, size = 8 / .pt) +
  annotate("text", x = at(0.93, 0.58)[1], y = at(0.93, 0.58)[2],
           label = "Río Negro", angle = 90, size = 8 / .pt) +
  annotate("text", x = at(0.93, 0.26)[1], y = at(0.93, 0.26)[2],
           label = "Chubut", angle = 90, size = 8 / .pt) +
  ggspatial::annotation_scale(
    location = "br", height = unit(1.4, "mm"), width_hint = 0.5,
    bar_cols = c("grey15", "white"), text_col = "grey15", text_cex = 0.55,
    line_width = 0.4, pad_x = unit(1, "mm"), pad_y = unit(1, "mm")) +
  ggspatial::annotation_north_arrow(
    location = "br", height = unit(7, "mm"), width = unit(5, "mm"),
    pad_x = unit(1, "mm"), pad_y = unit(5, "mm"),
    style = ggspatial::north_arrow_orienteering(
      text_size = 5, line_width = 0.5, fill = c("white", "grey30"))) +
  panel_letter("C") +
  map_frame()

# The inset ---------------------------------------------------------------

# South America with all of Argentina's provinces, and the study area as a
# coloured sliver. Drawn in the same CRS as the panels, which is what stretches
# it.
#
# The provinces come from the SAME IGN layer the panels use. The FAO GAUL file
# that sat next to it in the original QGIS folder is the trap here, and is the
# reason only the IGN one was copied into the store: GAUL's Argentina has 17 of
# the 24 provinces, so drawing the inset from it leaves the whole east and
# south of the country grey, as if it were another country.
sa <- to_map(crop(vect(file.path(sam_dir, "south_america.shp")), inset_bbox))
# Cropping also drops the Antarctic claim carried by Tierra del Fuego, which
# would otherwise stretch the inset to the pole.
ar <- to_map(crop(provinces_all, inset_bbox))
stopifnot(nrow(ar) == 24)
inset_ext <- ext(sa)

p_inset <- ggplot() +
  geom_spatvector(data = sa, fill = "grey80", colour = "grey45",
                  linewidth = 0.2) +
  geom_spatvector(data = ar, fill = "white", colour = "grey55",
                  linewidth = 0.15) +
  geom_spatvector(data = aggregate(ar), fill = NA, colour = "black",
                  linewidth = 0.3) +
  geom_spatvector(data = study_area, fill = col_fire, colour = col_fire,
                  linewidth = 0.3) +
  coord_sf(xlim = c(inset_ext[1], inset_ext[2]),
           ylim = c(inset_ext[3], inset_ext[4]), expand = FALSE) +
  theme(panel.background = element_rect(fill = "white", colour = NA),
        panel.border = element_rect(colour = "black", fill = NA,
                                    linewidth = 0.4),
        panel.grid = element_blank(),
        axis.title = element_blank(),
        axis.text = element_blank(),
        axis.ticks = element_blank(),
        plot.margin = margin(1, 1, 1, 1, unit = "mm"))

# Assembly ----------------------------------------------------------------

# Panel A's key sits under panel A and panel B's colourbar under panel B, as the
# published QGIS figure has them; only the vegetation legend is pulled out into
# the fourth column, under the inset.

strip_legend <- function(p) p + theme(legend.position = "none")
grab <- function(p) ggpubr::as_ggplot(ggpubr::get_legend(p))

# A key placed under a 3.5 cm panel has to be one column wide, and its title
# and text have to shrink or the panel is set by the legend rather than by the
# map.
below_theme <- function(p, ...) {
  p + guides(...) +
    theme(legend.position = "bottom",
          legend.direction = "vertical",
          legend.justification = "left",
          legend.title = element_text(size = 8),
          legend.text = element_text(size = 7),
          legend.margin = margin(1, 0, 0, 0, unit = "mm"),
          legend.box.margin = margin(0, 0, 0, 0, unit = "mm"))
}

# The panel is 146 km wide and 619 km tall and `coord_sf` holds that ratio, so
# the figure's height decides how wide the three maps come out, and a height
# that is too generous just puts a white band above and below them. At 17 cm
# wide the three panels plus the legend column leave each map about 3.5 cm, so
# ~15 cm of drawn map; 18.5 cm of figure leaves that much map plus the height
# the two keys under panels A and B take.
assemble <- function() {
  left <- list(
    below_theme(p_a, fill = guide_legend(ncol = 1),
                colour = guide_legend(ncol = 1)),
    below_theme(p_b, fill = guide_colourbar(
      title.position = "top", barwidth = unit(4, "mm"),
      barheight = unit(14, "mm"))))
  right <- p_inset / grab(p_c) + plot_layout(heights = c(1, 2.2))
  (left[[1]] | left[[2]] | strip_legend(p_c) | right) +
    plot_layout(widths = c(1, 1, 1, 1.3))
}

dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)
fig <- assemble()
for (ext_ in c("png", "pdf")) {
  f <- file.path(fig_dir, paste0("fig1_study_area.", ext_))
  ggsave(f, plot = fig, width = 17, height = 18.5, units = "cm",
         dpi = 400, bg = "white",
         device = if (ext_ == "pdf") grDevices::cairo_pdf else NULL)
  cat("wrote", f, "\n")
}
