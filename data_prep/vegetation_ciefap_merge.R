library(tidyverse)
library(terra)

source(file.path("R", "config.R"))

veg_ciefap_dir <- file.path("data", "vegetation_ciefap")

vne <- vect(file.path(veg_ciefap_dir, "NQN_2013", "cob_2013_N3_aok_NQN.shp"))
vrn <- vect(file.path(veg_ciefap_dir, "RN_2013", "cob_2013_N3_aok_RN.shp"))
vchu <- vect(file.path(veg_ciefap_dir, "CH_2013", "cob_2013_N3_aok_CH.shp"))

v <- rbind(vne, vrn, vchu)

v$Ley_N1 %>% unique
v$Ley_N2 %>% unique
v$Ley_N3 %>% unique

vdf <- as.data.frame(v)
tmp1 <- aggregate(Area_Ha ~ Ley_N1 + Ley_N2 + Ley_N3, vdf, sum)
names(tmp1)[4] <- "area_ha"
tmp1$area_rel <- tmp1$area_ha / sum(tmp1$area_ha) * 100
tmp1$Ley_N1 <- factor(tmp1$Ley_N1, levels = c("TF", "OFL", "OT"))

classes <- tmp1[order(tmp1$Ley_N1, tmp1$Ley_N2, tmp1$Ley_N3), ]

write.csv(classes, file.path(veg_ciefap_dir, "clases_de_vegetacion_y_equivalencias_ciefap.csv"), row.names = T)
View(vdf)


# Ahora subo el excel con las clases reclasificadas, para agregar esa columna.
tab <- readxl::read_xlsx(config$veg_equiv_xlsx_ciefap, sheet = 1)
head(tab)

data_merge <- as.data.frame(v)
data_merge <- left_join(data_merge,
                        tab[, c("Ley_N3", "class1", "cnum1", "class2", "cnum2")],
                        by = "Ley_N3")

v$class1 <- data_merge$class1
v$cnum1 <- data_merge$cnum1
v$class2 <- data_merge$class2
v$cnum2 <- data_merge$cnum2
# esto se sube a GEE.

writeVector(v, file.path(veg_ciefap_dir, "ciefap_2016_NQN-RN-CH_reclass.shp"), overwrite = TRUE)

