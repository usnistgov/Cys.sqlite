# Title: p(phi,psi,dse) using AKDE
#
# Description: This script was implemented following the approach described through page 12 of the 
#              supporting information of Shapovalov and Dunbrack. 
#              
#              Citation: Structure. 2011 Jun 8;19(6):844-58. doi: 10.1016/j.str.2011.03.019
#              url:      https://www.ncbi.nlm.nih.gov/pubmed/21645855
#              si-url:   https://ars.els-cdn.com/content/image/1-s2.0-S0969212611001444-mmc1.pdf
#
#              last checked (2019-01-30)
#
#   This script can be used as an example for how to use cys.sqlite from R. Suggestions, contributions 
#   to improve the script are welcome!
#
#   basic setup to run the script (assumes basic understanding of linux shell): 
#     0. install R and libraries below
#     1. change directory to that of the Cys.Sqlite repo
#     2. > curl https://trc.nist.gov/cys.sqlite.gz > cys.sqlite.gz
#     3. > gunzip cys.sqlite.gz
#     4. > Rscript script/R/akde_phi_psi.r
#
#     output Rplots.pdf
#
#  Authors: Lenny Fobe and Demian Riccardi

library(data.table)
library(RSQLite)
library(plot3D)                           
library(pracma)
library(latex2exp)

rm(list = ls())

#Setup grid 
ngrid <- 73
phi_space <- linspace(-180, 180, ngrid)
psi_space <- linspace(-180, 180, ngrid)
phi_psi_grid <- meshgrid(phi_space,psi_space)
print (phi_space)

#connect to Cys.sqlite (here, the path to cys.sqlite file is local to where it is run)
cysqlite <- dbConnect(RSQLite::SQLite(), "cys.sqlite")


query_CysConf_PhiPsi <- function(dse_condition, exp_method) {
  ##########################################################################
  #  select phi and psi from cys_conf via queries
  #       on joined tables: 
  #       dse_condition: sql name cys_cys ss, e.g. "ss.dse >= 10.6 AND ss.dse < 15.9" 
  #       exp_method: 'X-RAY DIFFRACTION', 'SOLUTION NMR'
  #
  #  adjust the selections below for your own purpose, eg.: 
  #     - number of models from NMR
  #     - resolution for X-Ray structures
  ##########################################################################
  select <-
    paste(
      "SELECT cys_conf.phi, cys_conf.psi, ss.dse",
      "FROM  Cys_conf cys_conf",
      "     JOIN PDB pdb",
      "         ON pdb.id = cys_conf.pdb_id",
      "     JOIN CYS_CYS ss",
      "         ON ss.cys_conf_idi = cys_conf.id  OR ss.cys_conf_idj = cys_conf.id",
      paste("WHERE   pdb.exp_method ='", exp_method, "'", sep = ""),
      "  AND  ", dse_condition,
      "  AND   pdb.status = 'CURRENT'",
      "  AND   pdb.exp_method_identity_cutoff = '50'",
      #"  AND   pdb.exp_method_identity_cutoff is not NULL", # %100 
      "  AND   cys_conf.phi is not NULL",
      "  AND   cys_conf.psi is not NULL",
      #"  AND   cys_conf.model_num <= 2", # to speed up NMR cases for dev
      sep = " " 
    )
  
  if (exp_method == "X-RAY DIFFRACTION") {
    select <-
      paste(select,
            "  AND   pdb.resolution <= 1.5",
            "  AND   ss.alt_occ_flag IS NULL", # only full occupancy disulfides
            #"  AND   cys_conf.CA_bfact < 10", # can filter on additional columns
            sep = " ")
  } 

  data <- dbGetQuery(cysqlite, select)
  phi_psi <- data

  # may not be necessary with respect to results from query, which should not contain NULL phi,psi 
  phi_psi <-
    data[!is.na(phi_psi[[1]]) & !is.na(phi_psi[[2]]) & !is.na(phi_psi[[3]]), ] 
  return(phi_psi)
}

kde_builder_2d <- function(phi_psi, kappa) {
  phi <- phi_psi[, 1]
  psi <- phi_psi[, 2]
  vectorized_kde_builder <- function(vx, vy) {
    f_kde <- function(x, y) {
      f_kde <-
        1 / (4 * 180 ^ 2) * mean((1 / (besselI(kappa, 0) ^ 2)) * exp(kappa * (cos((x - phi) * pi / 180
        ) + cos((y - psi) * pi / 180
        ))))
      return(f_kde)
    }
    f <- mapply(f_kde, x = vx, y = vy)
    return(f)
  }
  return(vectorized_kde_builder)
}

akde_builder_2d <- function(dist, pilot_func, kappa) {
  phi <- dist[, 1]
  psi <- dist[, 2]
  
  lambda <-
    (geomean(pilot_func(dist[[1]], dist[[2]])) / (pilot_func(dist[[1]], dist[[2]]))) ^
    (1 / 2)
  myfunc <- function(vx, vy) {
    f_akde = function(x, y) {
      f_akde <-
        1 / (4 * 180 ^ 2) * mean((1 / (besselI(kappa / lambda, 0) ^ 2)) * exp(kappa / lambda * (cos((x - phi) * pi / 180
        ) + cos((y - psi) * pi / 180
        ))))
      return(f_akde)
    }
    f <- mapply(f_akde, x = vx, y = vy)
    return(f)
  }
  return(myfunc)
}

akde_2d <- function(dist, akde_func, kappa) {
  # whether or not this is akde depends on function
  # ...  you can pass nonaddaptive kde function here as well 
  z_vec <- akde_func(as.vector(phi_psi_grid$X), as.vector(phi_psi_grid$Y))
  z <- matrix(data = z_vec,
              ncol = ncol(phi_psi_grid$X))
  output <- list(phi_psi_grid, z)
  names(output) <- c('phi_psi_grid', 'z')
  return(output)
}

## MAIN
#exp_methods <- c("SOLUTION NMR")
exp_methods <- c("X-RAY DIFFRACTION")

# 1.5 \AA mean 10.6 STDEV 5.3 
DSEs <- c(
  "ss.dse <= 5.3",  # assumes ss defined within SQL query 
  "ss.dse >5.3    AND ss.dse < 10.6",
  "ss.dse >= 10.6 AND ss.dse < 15.9",
  "ss.dse >= 15.9",
  "ss.dse >0"
) 

kappa <- 100
# plotting parameters
par(ps = 12, cex = 1.45, cex.main = 1)

for (exp in exp_methods) {
  # need all phi psi for Shapovalov and Dunbrack type 2 pilot function (S10)
  all_phi_psi <- query_CysConf_PhiPsi("ss.dse > 0", exp)
  print(paste("Total phi psi for ", exp, "; selected count: ", nrow(all_phi_psi),sep = ""))
  print("Calculating pilot function for phi psi overall dse")
  all_pilot_func <- kde_builder_2d(all_phi_psi, kappa)
  print("Finished calculating pilot function for phi psi overall dse")

  for (dse in DSEs) {
    phi_psi_dse    <- query_CysConf_PhiPsi(dse, exp)
    # use this for type 1 pilot function (S9 from Shapovalov and Dunbrack):
    # dse_pilot_func <- kde_builder_2d(phi_psi_dse, kappa)
    print(paste("Working on AKDE: ", exp, " ", dse, " selected count: ", nrow(phi_psi_dse),sep = ""))
    akde_func <- akde_builder_2d(phi_psi_dse, all_pilot_func, kappa)
    akde_plot <- akde_2d(phi_psi_dse, akde_func, kappa)

    image2D(
      z = akde_plot[[2]],
      x = akde_plot[[1]]$X,
      y = akde_plot[[1]]$Y,
      xlab = TeX("$\\Phi"),
      ylab = TeX("$\\Psi"),
      #main = paste('Adaptive Kernel plot for all Conformations'),
      xaxs = 'i',
      yaxs = 'i',
      xlim = c(-180, 180),
      ylim = c(-180, 180),
      zlim = c(0, 4e-4),
      resfac = 5,
      xaxs = 'i', yaxs ='i',
      colkey = list(length = 0.5, width = 0.5, cex.clab = 0.75),
    )
    
    a_b_ratio <- integral2(akde_func, -180, -30, -120, 30)$Q / integral2(akde_func, -180, -30, 30, 180)$Q
    print(paste(exp, dse, ":", a_b_ratio))
    print(paste("overall integral:",integral2(akde_func, -180, 180, -180, 180)$Q ))

  }
}

dbDisconnect(cysqlite)
