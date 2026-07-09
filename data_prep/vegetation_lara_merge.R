library(terra)
library(tidyverse)

veg_lara_dir <- file.path("data", "vegetation_lara")

norte <- vect(file.path(veg_lara_dir, "norte.shp"))
centro <- vect(file.path(veg_lara_dir, "centro.shp"))
sur <- vect(file.path(veg_lara_dir, "sur.shp"))

# plot(norte)
# plot(centro)
# plot(sur)

all <- rbind(norte, centro, sur)
# plot(all)

# write raw values, in shp and tiff, projected at latlong
all_ll <- project(all, "EPSG:4326")
writeVector(all_ll, file.path(veg_lara_dir, "vegetation_map_lara1999.shp"), overwrite = TRUE)


# vegetation types
ss <- as.data.frame(all[, c("GRID_CODE", "CLASE")])
ss <- ss[!duplicated(ss$GRID_CODE), ]
ss <- ss[order(ss$GRID_CODE), ]
ss$CLASE[is.na(ss$CLASE)] <- "00. Indefinido"
View(ss)

ss$Kitz22 <- plyr::revalue(
  ss$CLASE,
  replace = c(
    "00. Indefinido" = NA,
    "01. Bosque de Alerce" = "Wet forest",
    "05. Bosque de Coihue, Rauli y Roble Pellin" = "Wet forest",
    "06. Bosque de Coihue, Rauli y Tepa" = "Wet forest",
    "07. Bosque Siempreverde Valdiviano" = "Wet forest",
    "11. Bosque de Coihue de Magallanes" = "Wet forest",
    "03. Bosque de Cipres de las Guaitecas"  = NA,
    "10. Bosque de Roble Hualo"  = NA,
    "12. Bosque Esclerofilo Mixto"  = NA,

    "02. Bosque de Araucaria" = "Dry forest",
    "04. Bosque de Cipres de la Cordillera" = "Dry forest",

    "08. Bosque de Lenga" = "Subalpine forest",

    "09. Bosque y Matorral de Ñire" = "Shrubland",

    "13. Estepa Patagonica" = "Grassland",
    "14. Mallines y Humedales" = "Grassland",

    "17. Plantaciones" = "Plantation",

    "16. Praderas y Matorrales de Origen Antropico" = "Anthropogenic prairie and shrubland",
    "18. Areas Agricolas" = "Anthropogenic prairie and shrubland",

    "15. Rocas y Vegetacion Altoandina" = "Non burnable",
    "19. Areas Urbanas" = "Non burnable",
    "20. Nieves y Glaciares" = "Non burnable",
    "21. Lagos" = "Non burnable",
    "22. Areas Sin Relevar" = "Non burnable"
  )
)

ss$FireSpread <- plyr::revalue(
  ss$CLASE,
  replace = c(
    "00. Indefinido" = "Non burnable",

    # Wet forest
    "01. Bosque de Alerce" = "Wet forest",
    "05. Bosque de Coihue, Rauli y Roble Pellin" = "Wet forest",
    "06. Bosque de Coihue, Rauli y Tepa" = "Wet forest",
    "07. Bosque Siempreverde Valdiviano" = "Wet forest",
    "11. Bosque de Coihue de Magallanes" = "Wet forest",
    "03. Bosque de Cipres de las Guaitecas"  = "Wet forest",
    "10. Bosque de Roble Hualo"  = "Wet forest",
    "12. Bosque Esclerofilo Mixto"  = "Wet forest",

    # Dry forest
    "04. Bosque de Cipres de la Cordillera" = "Dry forest",

    # Subalpine forest
    "02. Bosque de Araucaria" = "Subalpine forest",
    "08. Bosque de Lenga" = "Subalpine forest",

    # Shrubland
    "09. Bosque y Matorral de Ñire" = "Shrubland",
    "17. Plantaciones" = "Shrubland",
    "16. Praderas y Matorrales de Origen Antropico" = "Shrubland",
    "18. Areas Agricolas" = "Shrubland",

    # Grassland
    "13. Estepa Patagonica" = "Grassland",
    "14. Mallines y Humedales" = "Grassland",

    # Non-burnable
    "15. Rocas y Vegetacion Altoandina" = "Non burnable",
    "19. Areas Urbanas" = "Non burnable",
    "20. Nieves y Glaciares" = "Non burnable",
    "21. Lagos" = "Non burnable",
    "22. Areas Sin Relevar" = "Non burnable"
  )
)

write.csv(ss, file.path(veg_lara_dir, "clases_de_vegetacion_y_equivalencias_kitz22-firespread.csv"))
