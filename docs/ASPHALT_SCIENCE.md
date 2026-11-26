# Asphalt simulator: science register

The goal: every number in `AsphaltSim` that shapes what is drawn comes from a source (a paper, a standard, a data
set) or from an equation fed by one. This file tracks where each one stands. Update it whenever a placeholder is
replaced. Papers are in `References/Asphalt/` (see its README).

Status words used below:
- **Sourced**: the value or equation comes from a reference, cited next to it.
- **Derived**: worked out in our own experiment (the CrackLattice runs), not yet checked against a reference.
- **Placeholder**: set by eye so the road looked right.

## The ladder of sources

1. **Definitions**: what each distress is and how it is measured. *LTPP Distress Identification Manual (done,
   below).* ASTM D6433 next for parking lots, slippage cracks and the PCI.
2. **Data**: how the distresses grow year by year on real roads. LTPP InfoPave survey maps and photos.
3. **Equations**: the models fitted to that data. MEPDG (fatigue, thermal cracking, rutting), field binder
   ageing (Glover group), crack-pattern physics (Li & Marasteanu, Chen, Bohn, Shorlin, Goehring).

## Size of the code (Nov 2026)

`asphalt_sim.gd` is 1,726 lines with about 377 non-trivial numeric literals. Roughly a dozen trace to a source. By
part: header and exports 227 lines, public API 204, `bake_height` 211, stats 49, the simulation step 404, crack
networks 186, repairs 446. Plan: as each model is replaced with a sourced one, move it into its own file (ageing,
thermal cracking, fatigue, water and potholes, repairs, height map, survey), so each file maps to one set of
references. No big-bang refactor.

## Register

### Layout and pavement

| What | Now | Status | Source / next |
|---|---|---|---|
| Wheel paths | 4 paths at x 1.95, 3.75, 6.25, 8.05 m; Gaussian load, e-fold 0.35 m | Placeholder | LTPP fig. 136: 0.76 m bands centred 0.76 m and 2.9 m from the edge stripe (highway, 3.66 m lane). That's a survey band, not a load spread: lateral wander comes from MEPDG. Parking lots need their own (car traffic in aisles). |
| Edge zone | fretting up to 0.6 m | Sourced | LTPP ACP 3: edge cracking within 0.6 m of the edge, unpaved shoulders only |
| Build-up | `PavementBuildup` resource, layers top to bottom plus subgrade CBR; baseline `assets/asphalt/buildups/c620_table3b_cbr9.tres` | Sourced | c620 Table 3B: 3.0 in asphalt on 4.0 in untreated aggregate base, good subgrade CBR 9 |
| Asphalt thickness | 0.0762 m (sum of the bound asphalt layers) | Sourced | c620 Table 3B |
| Asphalt E (warm), nu | 3 GPa, 0.35 | Typical values | No citation yet. Li & Marasteanu MnROAD: E 16-17.6 GPa at -18 C (cold, not warm) |
| Asphalt cold tensile strength, density | 2.27 MPa, 2289 kg/m3 | Sourced | Li & Marasteanu Table 4 (MnROAD cell 18, AC 20, -18 C) |
| Aggregate base cohesion, friction | 62.1 kPa, tan phi 1.299 | Sourced | Li & Marasteanu Table 4 (Mn/DOT Class 6, room temperature; frozen base likely 1.5-2x the cohesion) |
| Subgrade k | 146 MPa/m from CBR 9 (was 60 by hand) | Correlation | Mr = 2555 CBR^0.64 psi (MEPDG, one of several CBR correlations), k = Mr / 19.4 (AASHTO 1993, plate load). Primary texts not yet read. The aggregate base's support is left out |
| Slip length | 2.69 m (was 2.28) | Sourced | Li & Marasteanu eq. 4, the full form: sigma_t / (C/h + rho g tan phi). Full-depth asphalt (no base) uses a 0.1 MPa placeholder |
| Transverse spacing | 2.0 -> 0.6 slip lengths (5.4 -> 1.6 m) | Derived | Li & Marasteanu: 1.5 Xc (4.0 m). Their MnROAD cracks were closer than predicted. The aged 0.6 has no reference |
| Block size | 0.7 x 1.0 slip lengths (1.9 x 2.7 m, 5.1 m2) | Derived | LTPP ACP 2: blocks 0.1-10 m2, occurrence at least 15 m long. Consistent |
| Crocodile cell | 0.7 x 1.0 Westergaard radius (0.12 x 0.17 m; was 0.15 x 0.21) | Derived | LTPP ACP 1: pieces usually under 0.3 m on the longest side. Consistent. Westergaard is a slab-on-springs model, standing in for layered elastic analysis |
| `structure` slider, `weak` noise | still in use | Placeholder | To be replaced by the build-up (thickness, compaction) and a subgrade CBR field across the plan |

### Ageing, fatigue, water

| What | Now | Status | Source / next |
|---|---|---|---|
| Binder oxidation | 1 - exp(-t climate / 9 yr) | Placeholder | Field oxidation kinetics (Glover group, Texas A&M) |
| Crack opening drive | 0.4 + 0.9 x oxidation | Placeholder | Thermal stress E alpha dT from a climate record |
| Fatigue rate | 0.085 x traffic / structure x (h0/h)^2 x multipliers | Placeholder (1/h^2 sourced) | MEPDG allowable loads from tensile strain, Miner's sum, logistic damage -> % area cracked |
| Fatigue thresholds | crack at 1.0, cells at 1.2, broken at 1.4 | Placeholder | MEPDG damage -> area transfer function |
| Water damage, pothole birth | k_d 0.6, birth at damage 1.0 | Placeholder | LTPP data; pumping is ACP 15 |
| Pothole depth | starts 12 mm, +30 mm/yr, stops at 90 mm | Placeholder | LTPP ACP 8 severity classes: < 25, 25-50, > 50 mm |

### Cracks

| What | Now | Status | Source / next |
|---|---|---|---|
| Width | 1 mm + 1.6 mm x drive, capped at 30 mm | Placeholder | LTPP severity bands: <= 6, 6-19, > 19 mm. Rate from InfoPave data |
| Transverse onset | rate 0.8 climate ox per year, opens at 1.6 x spacing gap | Placeholder | Chen 2022: average spacing is 3/4 of the largest gap (halving) |
| Lane joint | 0.45 per year from 0.8 yr | Placeholder | |
| Growth speeds | 3.5, 1.2, 0.5 + 0.3 f m/yr | Placeholder | |
| Junctions | T 55 %, stop short 25 %, look-ahead 8 cm, turn 0.35 | Placeholder | Shorlin: mean 90 deg, SD 15 deg. **We get 69 deg** |
| Slippage | crescent sets in the wheel paths | Placeholder | Not an LTPP distress; ASTM D6433 / Austroads |
| Edge cracking, fretting | rates 0.5/yr, 0.025 m/yr | Placeholder | LTPP ACP 3 severity: breakup over <= 10 % / > 10 % of the length |
| Reflection | AC-over-AC through overlays, 1.5-5 yr delay | Placeholder | LTPP ACP 5 is only over concrete joints; AC-on-AC is recorded as ACP 4 / 6. Chen: rises about 2.5 cm/yr |

### Height map and surface

| What | Now | Status | Source / next |
|---|---|---|---|
| Crack depth | 4 x width, 4-50 mm | Placeholder | |
| Spalls | 2.2 x width + 8 mm wide, 6 mm deep | Placeholder | LTPP: "spalled" is part of the fatigue and patch severity words |
| Rutting | 1.1 mm/yr x traffic / structure, capped at 25 mm | Placeholder | MEPDG rutting; LTPP measures it with a 1.2 m straightedge, patch severity uses < 6, 6-12, > 12 mm |
| Shoulder drop, fret drop | -25 mm, -35 mm (fixed) | Placeholder | LTPP ACP 14 (not measured in LTPP) |
| Patch, fill, sealant, paint proud | 3, 4, 1.5, 0.8 mm | Placeholder | |
| Bleeding, shoving | none | Missing | LTPP ACP 10, 11 |

### Repairs and condition

| What | Now | Status | Source / next |
|---|---|---|---|
| Sealant life | 6 yr | Placeholder | LTPP counts sealant "in good condition" only over >= 1 m continuous (longitudinal) or >= 90 % of the crack (transverse) |
| Patch seams, fill ravel, overlay resets | 2-6 yr, ..., fatigue x 0.45 | Placeholder | |
| Sealcoat, paint life | 3 yr, 8 yr | Placeholder | |
| Patch severity | none | Missing | LTPP ACP 7: by the worst distress in it, rutting < 6 / 6-12 / > 12 mm, patch-in-patch = high |
| Condition index | rough deduct score | Placeholder | LTPP gives quantities, not an index. PCI is ASTM D6433 |

## LTPP Distress Identification Manual: what it gives us

Read in full: the asphalt chapter and appendix A (FHWA-HRT-13-092, 2014). The manual is a dictionary and a
measuring method. It holds **no rates**: how fast things happen comes from the LTPP data and from models
calibrated on it.

Definitions we adopt:
- **Crack severity, by mean width** (block, longitudinal, reflection, transverse): low <= 6 mm (or sealed in good
  condition), moderate 6-19 mm, high > 19 mm. A crack is also moderate (or high) when low (or moderate/high)
  severity random cracking lies within 0.3 m of it. A transverse crack is rated at the highest severity present
  over at least 10 % of its length. Cracks under 0.3 m long are not recorded.
- **Fatigue (ACP 1)**: in the wheel paths; interconnected cracks that become many-sided, sharp-angled pieces,
  usually under 0.3 m on the longest side; must have an area. Low: few connecting cracks, not spalled. Moderate:
  a complete pattern, maybe slightly spalled. High: moderately or severely spalled, pieces may rock, pumping may
  show. Short, closely spaced (< 0.3 m) transverse cracks in a wheel path count as fatigue. A wheel-path
  longitudinal crack with random cracking round it, or one that meanders and has an area, is fatigue.
- **Block (ACP 2)**: roughly rectangular pieces of 0.1-10 m2; fatigue area inside is taken out of it; at least
  15 m long.
- **Edge (ACP 3)**: unpaved shoulders only; crescent or continuous cracks within 0.6 m of the edge. Low: no
  breakup; moderate: breakup or loss over up to 10 % of the affected length; high: over 10 %.
- **Longitudinal (ACP 4)**: 4a in the wheel paths, 4b outside them.
- **Patch (ACP 7)**: at least 0.1 m2; severity from the worst distress in it and its rutting (< 6, 6-12,
  > 12 mm); a patch with another patch in it is high. Sealant without aggregate is not a patch.
- **Pothole (ACP 8)**: bowl-shaped, at least 150 mm across (a 150 mm circle fits inside), about 0.02 m2 at least;
  severity by maximum depth: < 25, 25-50, > 50 mm. Its area is taken out of any fatigue area round it.
- **Rutting (ACP 9)**: depth in mm; no severity levels.
- **Raveling, polished aggregate, bleeding (ACP 11-13)**: area only, no severity.
- **Wheel paths (fig. 136)**: 0.76 m wide, centred 0.76 m and 2.9 m from the edge stripe, unless wear shows
  otherwise.

The sim measured against it (seed 1, defaults, no repairs; probe script, Nov 26 2026):

| Year | Open crack m, low / mod / high | Potholes, low / mod / high (single 10 cm cell) | Alligator % | Rut mm |
|---|---|---|---|---|
| 5 | 11 / 0 / 0 | 0 | 0.0 | 5.5 |
| 10 | 49 / 10 / 0 | 0 | 0.4 | 11.0 |
| 15 | 110 / 149 / 11 | 1 / 4 / 1 (6) | 9.4 | 16.5 |
| 20 | 61 / 262 / 98 | 10 / 21 / 43 (32) | 20.4 | 22.0 |
| 25 | 37 / 142 / 325 | 1 / 0 / 14 (2) | 26.7 | 25.0 |
| 30 | 20 / 89 / 445 | 0 / 1 / 4 (1) | 31.5 | 25.0 |

What this shows:
- Width runs away: by year 25, 64 % of open crack length is high severity, and every crack heads for the 30 mm
  cap. Whether that's real is a question for the LTPP data.
- Many potholes are a single 10 cm cell, which is under LTPP's 150 mm minimum. A real survey wouldn't count them.
- Ruts grow linearly to a hard cap.
- The sim's crack polylines are not distresses: thousands of segments under 0.3 m are pieces of networks. A survey
  layer (fatigue areas, blocks, transverse cracks by severity, patches, potholes) is needed before the sim can be
  compared with LTPP surveys.

## Next steps

0. Done (Nov 26 2026): the build-up as data (`PavementBuildup`, Table 3B baseline). Next: the cross-section drawing
   as a slice of the build-up, then the build-up's variation across the plan (replacing `structure` and `weak`).
1. Add a survey layer: `AsphaltSim` reports LTPP quantities by severity (m2 of fatigue and block, m of
   longitudinal 4a/4b and transverse, number and m2 of patches and potholes, rut depth). Lab panel and tests use
   it. No visual change; it is the measuring stick for everything after.
2. LTPP InfoPave: pick sections like our lots (thin AC over granular base, several climates) and read their
   survey time series. These are the targets.
3. Replace the models one at a time against those targets: ageing, then thermal cracking, then fatigue, then
   width, potholes, rutting and repairs.
