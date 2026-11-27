# Asphalt cracking papers

Papers behind the crack lattice experiment (`shopping-cart/scenes/asphalt/crack_lattice_lab.tscn`). Put the PDFs
in this folder with the file names below.

## Distress definitions (what we draw and how it is measured)
- `fhwa_2014_ltpp_distress_identification_manual.pdf`: Miller & Bellinger, "Distress Identification Manual for the
  Long-Term Pavement Performance Program", 5th revised edition, FHWA-HRT-13-092 (2014). Public domain (US DOT).
  https://www.fhwa.dot.gov/publications/research/infrastructure/pavements/ltpp/13092/13092.pdf
  Asphalt chapter (distresses 1-15, pp. 1-30) and appendix A (wheel paths, fig. 136, p. 91). Crack severity by mean
  width (<= 6 mm, 6-19 mm, > 19 mm), pothole severity by depth (< 25, 25-50, > 50 mm, at least 150 mm across),
  fatigue pieces usually under 0.3 m, blocks 0.1-10 m2, edge cracking within 0.6 m of the edge. Our notes on it:
  `docs/ASPHALT_SCIENCE.md`.

## Binder ageing
- `Long-Term Aging of Asphalt Mixtures for Performance Testing and Prediction Phase I & II Results .pdf`: Kim et al.,
  NCHRP Research Report 871 (2018). The original NCHRP 09-54 work: lab ageing procedure, the first Pavement Aging Model.
- `Long-Term Aging of Asphalt Mixtures for Performance Testing and Prediction Phase III Results .pdf`: Kim et al.,
  NCHRP Research Report 973 (2021). The field-calibrated Pavement Aging Model (Table 9), inputs from the binder's PG
  (eqs. 26-28), and the AMAC model (chapter 6). Notes: docs/ASPHALT_SCIENCE.md, Model 1.
- `glover_2014_tti_0-6009-2_binder_aging.pdf`: Glover et al., "Evaluation of Binder Aging and Its Influence in Aging of
  Hot Mix Asphalt Concrete", TTI report FHWA/TX-14/0-6009-2 (2014), 526 pp. Pavement temperature model, oxidation
  kinetics, diffusion with depth. https://library.ctr.utexas.edu/hostedPDFs/tti/0-6009-2.pdf

## Pavement temperature and colour
- `fhwa_1998_rd-97-103_ltpp_pavement_temperature_models.pdf`: Mohseni, "LTPP Seasonal Asphalt Concrete (AC) Pavement
  Temperature Models", FHWA-RD-97-103 (1998). High and low pavement temperature from air temperature, latitude and
  depth (eqs. 7, 8), from 30 LTPP seasonal monitoring sites.
- `pomerantz_2000_lbnl-43442_pavement_albedo.pdf`: Pomerantz, Pon, Akbari, Chang, "The Effect of Pavements'
  Temperatures on Air Temperatures in Large Cities", LBNL-43442 (2000). Measured albedo of asphalt pavements against
  age (fig. 1): 0.04 fresh, 0.12 +- 0.03 after 5 years; chip seal about 2/3 of the aggregate's albedo.

## Mix design (aggregate gradation and volumetrics)
- `fhwa_1998_rd-98-087_superpave_summary.pdf`: FHWA Research and Development, "Superpave Mixture Design" summary
  chart, FHWA-RD-98-087 (1998), 2 pp. Public domain (US DOT). https://rosap.ntl.bts.gov/view/dot/89514
  Gradation control points by nominal maximum size; for 12.5 mm: 100 % passing 19.0, 90-100 at 12.5, 28-58 at
  2.36, 2-10 at 0.075 mm; restricted zone 39.1 (2.36), 25.6-31.6 (1.18), 19.1-23.1 (0.60), 15.5 (0.30). Minimum VMA
  14 % (12.5 mm); design air voids 4 % (Ndes at 96 % Gmm); VFA 65-78 % (0.3-3 million ESALs). Limits, not a mix:
  a job-mix formula (LTPP test AG04 for a section) gives the actual curve.

- `mndot_1997_97-06_mnroad_hma_mixtures.pdf`: Stroup-Gardiner & Newcomb, "Investigation of Hot Mix Asphalt Mixtures
  at Mn/ROAD", Mn/DOT report 97-06 (1997). https://rosap.ntl.bts.gov/view/dot/14717
  Table 2.1 (p. 10): the job mix formula used for every Mn/ROAD asphalt cell (Crow River partially crushed gravel,
  fines 66 % and coarse 24 %, plus 10 % crushed granite CA-50; bulk specific gravity 2.702 field); cells 15-19 used
  AC-20 (PG 64-22). Table 3.5 (p. 25 of the report): as-built tests per cell and lift; cell 18 wear course (4th
  lift, 38 mm): 100 / 99 / 93 / 84 / 67 / 55 / 43 / 25 / 9 / 4.6 % passing 19 / 16 / 12.5 / 9.0 / 4.75 / 2.0 /
  1.0 / 0.45 / 0.25 / 0.075 mm, 5.8 % asphalt, 3.2 % air voids, VMA 15.3 %, Gmb 2.360, Gmm 2.439; listed as a
  50-blow Marshall mix (as the 2001 MnROAD forensic report, 2001MRRDOC006, also lists it).
- `mndot_1996_mnroad_aggregate_profile.pdf`: "Mn/ROAD Aggregate Profile" (Mn/DOT, 1996), 3 pp.
  https://sll.dot.state.mn.us/research/pdf/1996MRRDOC002.pdf. Measured gradations of the Class 3sp-6sp base
  materials (Table 1); Class 6sp (the build-up's base, Li & Marasteanu): 100 / 97.7 / 69.7 / 46 / 27.8 / 15.1 /
  10.4 / 8.1 / 6.3 / 4.7 % passing 25 / 19 / 9.5 / 4.75 / 2 / 0.85 / 0.425 / 0.25 / 0.15 / 0.075 mm.

## Albedo and macrotexture (surface composition, T2 step 6b)
- `ncat_2019_19-09_quantifying_pavement_albedo.pdf`: NCAT Report 19-09 / National Concrete Pavement Technology
  Center, "Quantifying Pavement Albedo" (Dec 2019). https://rosap.ntl.bts.gov/view/dot/62003. Asphalt albedo against
  surface age and coarse aggregate grayscale (Table 23, figs. 90 and 97); grayscale procedure in the appendix.
- `fhwa_2025_hrt-25-100_macrotexture_model.pdf`: FHWA TechBrief FHWA-HRT-25-100, "Macrotexture Model Development for
  Asphalt Mixtures Aimed at Safety Analysis" (2025). https://rosap.ntl.bts.gov/view/dot/88867. Eq. 1: MPD from mix
  type, Cu, P8, P200 and VFA.
- `vtrc_2023_23-r15_dense_graded_surface_functional.pdf`: Boz, Flintsch et al., "Functional Characteristics of
  Dense-Graded Asphalt Surface Mixtures", VTRC 23-R15 (2023). https://rosap.ntl.bts.gov/view/dot/67231. Measured MPD of
  Virginia dense-graded surfaces (Table 3, 0.39-0.49 mm) and a regression (eq. 3).
- `herold_roberts_2005_spectral_asphalt_road_aging.pdf`: Herold & Roberts, "Spectral characteristics of asphalt road
  aging and deterioration: implications for remote-sensing applications", Applied Optics 44(20), 4327-4334 (2005).
  Field spectra (350-2500 nm) of Santa Barbara roads: ageing and erosion raise reflectance (loss of hydrocarbons,
  more than 10 % in the near IR and SWIR) and bring out the minerals (iron oxide features at 520, 670, 870 nm);
  cracks darken by shadow (up to 7-8 %); ravelling brightens; slurry crack seal stays at about 5 %; patches look
  like fresh pavement; chip seal is much brighter. Spectral change is largest in the first years.
- Not filed (paywalled): "Albedo change mechanism of asphalt concrete surfaces", Transportation Research Record
  2676 (2022) 763-772, doi 10.1177/03611981221082567: lab oxidation leaves albedo at about 0.05; abrasion of the
  surface binder reproduces the field rise.

## Aggregate shape and packing (surface composition, T2 step 6b)
- `xu_2010_3d_aggregate_generation_packing.pdf`: Xu, Yang, Yin, Yang, Ye, "A three-dimensional aggregate generation
  and packing algorithm for modeling asphalt mixture with graded aggregates", Journal of Mechanics 26(2), 165-171
  (2010), doi 10.1017/S1727719100003026. Convex polyhedral stones grown from a random acute triangle (eq. 1:
  convexity by the sign of the tetrahedron volume), at most 10 faces, sharpness Lmax / Lmin <= 5 (eq. 2); stone
  counts per size group n_i = 6 phi g_i G / (pi D_i^3 rho) (eq. 4); packing largest first, a smaller stone tried
  where one doesn't fit; fines under 2.36 mm treated as mastic.

## Crack patterns in shrinking layers
- `bohn_2005_hierarchical_crack_pattern_II.pdf`: Bohn, Platkiewicz, Andreotti, Adda-Bedia, Couder, "Hierarchical
  crack pattern as formed by successive domain divisions. II. From disordered to deterministic behavior", Phys. Rev. E
  71, 046215 (2005). https://www.phys.ens.fr/~foldingslidingstretchinglab/papers/A22_PhysRevE_71_046215.pdf
  Cracks form one at a time and meet older ones at 90 deg; cell size ~5.5 x layer thickness (starch).
- `shorlin_1999_shrinkage_crack_patterns.pdf`: Shorlin, de Bruyn, Graham, Morris, "Development and geometry of
  isotropic and directional shrinkage crack patterns", arXiv patt-sol/9911003. https://arxiv.org/pdf/patt-sol/9911003
  Mean junction angle 90 deg, mostly 4-sided cells, spacing proportional to depth, larger on a slippery base; how
  much disorder decides straight, wavy or scattered cracks.

## How asphalt breaks
- `wagoner_buttlar_paulino_2005_dct_test.pdf`: Wagoner, Buttlar, Paulino, "Disk-Shaped Compact Tension Test for
  Asphalt Concrete Fracture", Experimental Mechanics 45(3), 2005.
  https://paulino.princeton.edu/journal_papers/2005/EM_05_DiskShapedCompactTension..pdf
- `wagoner_2005_hma_fracture_resistance_dct.pdf`: Wagoner, Buttlar, Paulino, Blankenship, "Investigation of the
  Fracture Resistance of Hot-Mix Asphalt Concrete Using a Disk-Shaped Compact Tension Test", TRR 1929, 2005.
  https://paulino.princeton.edu/journal_papers/2005/TRR_05_InvestigationOfTheFracture.pdf
- Fracture of asphalt concrete, a cohesive zone approach with viscoelastic effects (Illinois thesis).
  https://ideals.illinois.edu/items/84588

## Crack spacing in pavements
- `chen_2022_transverse_crack_spacing_semi_rigid_base.pdf`: Chen, Li, Zhao et al., "Investigation of transverse
  crack spacing in an asphalt pavement with a semi-rigid base", Scientific Reports 12, 18079 (2022).
  https://www.nature.com/articles/s41598-022-23122-y
- `li_marasteanu_2005_low_temp_crack_spacing.pdf`: Li, Marasteanu, Dai, Lukanen, "Prediction of Low Temperature
  Crack Spacing in Asphalt Pavements", Bearing Capacity of Roads, Railways and Airfields (2005).
  https://www.ntnu.no/ojs/index.php/BCRRA/article/download/3192/3076

## Lattice models of asphalt (NC State theses)
- Microstructure Generation of Asphalt Concrete and Lattice Modeling of Its Cracking Behavior under Low Temperature.
  https://repository.lib.ncsu.edu/items/85ad3164-49d1-4b94-a93e-de07496230e1
- `feng_2003_multiscale_lattice_fatigue_cracking.txt` (text only, from zack): Feng, NC State PhD 2003, "Micromechanics-based Multiscale Lattice Modeling of Fatigue Cracking in Hot Mixed Asphalt".
  https://repository.lib.ncsu.edu/items/e9f2dfdc-9b39-44e7-a56b-5665b3741e9b
- Cracking of asphalt mixture by discrete element modelling with real aggregate shapes. https://trid.trb.org/View/2103190

Pavement thicknesses for lots: `References/Levels/c620content.pdf`, tables 3-6.
