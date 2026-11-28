# Asphalt simulator: science register

The goal: every number in `AsphaltSim` that shapes what is drawn comes from a source (a paper, a standard, a data
set) or from an equation fed by one. This file tracks where each one stands. Update it whenever a placeholder is
replaced. Papers are in `References/Asphalt/` (see its README).

Status words used below:
- **Sourced**: the value or equation comes from a reference, cited next to it.
- **Derived**: worked out in our own experiment (the CrackLattice runs), not yet checked against a reference.
- **Placeholder**: set by eye so the road looked right.

The topics, their order, what passes between them and where each stands: `docs/ASPHALT_ROADMAP.md`.

## Goal

**An accurate visual representation of an asphalt pavement as it ages, in plan and in section.**

- **Plan:** the road surface seen from above: the colour map, the height map and the LTPP distress map.
- **Section:** the pavement cut across: the build-up (asphalt, base, subgrade) and what happens through it
  (cracks, ruts, potholes, patches).
- Plan and section are two slices of one state. The build-up, the climate and the traffic make that state through
  sourced equations; the plan view comes out of the section, not the other way round.
- Every visible feature must come from a sourced model. What has no source yet is taken out, not hidden or
  guessed (the lab runs with `AsphaltSim.placeholders` off). The drawings follow the LTPP manual.
- It is checked against a real LTPP section: its build-up, climate and traffic in, its yearly distress surveys
  as the target.
- The picture is the purpose; the science is how we earn it. Keep to what the picture needs.

## Scope: what the simulation studies, and what it doesn't

One pavement: an asphalt surface on an untreated aggregate base over a soil subgrade, on a two-lane road (LTPP
GPS-1 type). The causes are studied in order, the most generic first; each is added only when its model is
sourced, and what is not yet sourced is taken out rather than left in as a guess.

**Inputs (given, not simulated):** the build-up (layer thicknesses, materials, subgrade CBR; editable in the
lab), the road layout (lanes, wheel paths, markings), and later the climate (temperatures) and traffic (ESALs) of
the site, from the LTPP section being modelled.

**Studied, in this order:**

1. **The structure (layer thicknesses and stiffness).** How thick and how stiff the layers are sets how the
   pavement carries load and how far stress spreads (crack spacing, crocodile cell size, fatigue strain). Sources
   in hand: c620 build-ups, Li & Marasteanu (slip length), Westergaard; layered elastic analysis (MEPDG) next.
2. **The binder ageing (oxidation).** The asphalt binder hardens and turns brittle with time, fastest at the
   surface and in heat. Every distress below depends on it. Source: TTI 0-6009-2 (Glover et al. 2014); NCHRP 871
   and 973 once they are in References.
3. **Thermal cracking (transverse, then block).** Cold shrinks the hardened layer; friction on the base holds it;
   it cracks across the road at a spacing set by the structure. Sources: Li & Marasteanu, Chen; MEPDG thermal
   cracking model later.
4. **Load fatigue cracking and rutting (wheel paths, crocodile cells).** Repeated axle loads bend the layer; damage
   builds (Miner's rule) until it cracks, and the layers deform permanently. Source: MEPDG bottom-up fatigue and
   rutting (the same layered analysis drives both).
5. **Consequences of cracking:** crack widening (LTPP severity), water getting in, potholes.
6. **Repairs:** crack sealing, patching, overlays, judged against LTPP's maintenance experiments (SPS-3, SPS-5).

Throughout: crack geometry (how cracks run and meet: Bohn, Shorlin) and the LTPP manual's definitions, survey and
drawings.

**Not studied (out of scope unless decided otherwise):** binder chemistry beyond its ageing rate; the mix's
microstructure and stones (the lattice is a research tool, not part of the simulation); mix design and
construction quality; drainage and frost heave; other base types (cement- or lime-treated bases, full-depth
asphalt, concrete); slippage cracking (not an LTPP distress); bleeding, shoving, polished aggregate and raveling
(until a source is found); individual vehicles (traffic is counted in ESALs).

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
| Road layout | Two-lane road: 3.65 m (12 ft) lanes, centreline joint at 5 m, 1.35 m gravel shoulders; markings: white edge lines, broken yellow centreline (10 ft dash, 30 ft gap), 4 in wide | Sourced | MUTCD (line widths, broken-line pattern); 12 ft lane as LTPP fig. 136 assumes |
| Wheel paths | 2.11, 4.25, 5.75, 7.89 m: 0.76 m and 2.9 m in from each edge stripe; load still a Gaussian, e-fold 0.35 m | Sourced (positions) / placeholder (load spread) | LTPP fig. 136. Lateral wander of the load comes from MEPDG |
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
| `structure`, `traffic`, `climate`, `drainage`, `bond`, `ponding` | inside the sim at 1.0 (`bond` 0.7); no longer in the lab UI | Placeholder | Each goes when its model arrives: thickness and compaction (build-up), ESALs (traffic; c620 Table 5 uses them), temperature drop and freeze-thaw cycles (Li, Chen), water |

### Ageing, fatigue, water

| What | Now | Status | Source / next |
|---|---|---|---|
| Binder oxidation | 1 - exp(-t climate / 9 yr) | Placeholder | Field oxidation kinetics (Glover group, Texas A&M) |
| Crack opening drive | 0.4 + 0.9 x oxidation | Placeholder | Thermal stress E alpha dT from a climate record |
| Fatigue rate | 0.085 x traffic / structure x (h0/h)^2 x multipliers | Placeholder (1/h^2 sourced) | MEPDG allowable loads from tensile strain, Miner's sum, logistic damage -> % area cracked |
| Fatigue thresholds | crack at 1.0, cells at 1.2, broken at 1.4 | Placeholder | MEPDG damage -> area transfer function |
| Water damage, pothole birth | k_d 0.6, birth at damage 1.0 | Placeholder | LTPP data; pumping is ACP 15 |
| Pothole depth | starts 12 mm, +30 mm/yr, stops at 90 mm | Placeholder | LTPP ACP 8 severity classes: < 25, 25-50, > 50 mm. The cross-section shows 90 mm cuts 14 mm into the base under 76 mm of asphalt, though the code says holes stop at the base course |

### Cracks

| What | Now | Status | Source / next |
|---|---|---|---|
| Width | 1 mm + 1.6 mm x drive, capped at 30 mm | Placeholder | LTPP severity bands: <= 6, 6-19, > 19 mm. Rate from InfoPave data |
| Transverse onset | rate 0.8 climate ox per year, opens at 1.6 x spacing gap | Placeholder | Chen 2022: average spacing is 3/4 of the largest gap (halving) |
| Lane joint | 0.45 per year from 0.8 yr | Placeholder | |
| Growth speeds | 3.5, 1.2, 0.5 + 0.3 f m/yr | Placeholder | |
| Junctions | Look-ahead = asphalt thickness, turning harder as the tip nears; shrinkage branches leave at 90 +- 15 deg; 25 % stop short | Sourced (look-ahead: Bohn, influence ~ layer thickness; turn: local symmetry; branches: Shorlin) / stop short placeholder | Shorlin: 90 deg, SD 15 deg. **Shrinkage cracks now 79.5 +- 9.5 deg** (10 seeds, 48 junctions; was 71 +- 20). Fatigue cracks 69 deg: LTPP says "sharp-angled", no measured target. Fatigue branch angles still placeholders |
| Slippage | crescent sets in the wheel paths | Placeholder | Not an LTPP distress; ASTM D6433 / Austroads |
| Edge cracking, fretting | rates 0.5/yr, 0.025 m/yr | Placeholder | LTPP ACP 3 severity: breakup over <= 10 % / > 10 % of the length |
| Reflection | AC-over-AC through overlays, 1.5-5 yr delay | Placeholder | LTPP ACP 5 is only over concrete joints; AC-on-AC is recorded as ACP 4 / 6. Chen: rises about 2.5 cm/yr |

### Height map and surface

| What | Now | Status | Source / next |
|---|---|---|---|
| Crack depth | 4 x width, 4-50 mm (`AsphaltSim.crack_depth`) | Placeholder | Drawn dashed in the cross-section. Next: top-down / bottom-up cracks and how far through the layers they have gone |
| Spalls | 2.2 x width + 8 mm wide, 6 mm deep | Placeholder | LTPP: "spalled" is part of the fatigue and patch severity words |
| Rutting | 1.1 mm/yr x traffic / structure, capped at 25 mm; only the surface sinks (the cross-section shows the layer interfaces flat) | Placeholder | MEPDG rutting splits it between asphalt, base and subgrade; LTPP measures it with a 1.2 m straightedge, patch severity uses < 6, 6-12, > 12 mm |
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

## LTPP appendix A: the distress map and its symbols

Appendix A ("Manual for Distress Surveys") says how a survey is drawn and totalled. Read in full: figs. 134
(section limits), 136 (wheel paths), 137 (map symbols for asphalt), 138 (an example map) and data sheets 1-3.

- **The section** (fig. 134): one lane, from the edge stripe to the centreline stripe, extended to a joint, crack or
  pavement edge within 0.3 m outside them. A 152.5 m LTPP section is mapped on five sheets of two 15.25 m strips.
- **The map** (fig. 138): distance along the lane left to right (direction of travel), offset from the edge bottom
  to top (0-5 m, feet on the right), a fine grid, both wheel paths marked (fig. 136: drawn where the traffic runs,
  0.76 m wide by default). Each distress is drawn to scale and labelled with a circled code: its number, a/b for
  longitudinal, L/M/H, and "s" beside well-sealed cracks (e.g. "4aH", "6Ms").
- **The symbols** (fig. 137): 1 fatigue an outlined area of X's; 2 block the cracks forming blocks; 3 edge a hatched
  strip at the edge; 4 longitudinal and 6 transverse the crack lines (S sealed); 5 reflection at joints (concrete
  joints only, not recorded); 7 patch solid black; 8 pothole an ellipse with a cross; 9 rutting and 14 dropoff
  not drawn; 10 shoving a box of wavy lines; 11 bleeding curved hatch; 12 polished aggregate short slashes; 13
  raveling circles in a dotted outline; 15 water bleeding/pumping chevrons along the crack; 16 other, described.
  Sealant applied without aggregate is 16, not a patch.
- **Data sheets 1-2** total the map by severity: m2 (1, 2), m (3, 4a, 4b and their sealed lengths), number and m
  (6), number and m2 (7, 8), m2 (10-13), number and m (15). Sheet 3 is straightedge rutting every 15.25 m (SPS-3).

In the sim: `AsphaltSurvey` (scripts/asphalt/asphalt_survey.gd) classifies the road by these rules, each lane an
LTPP section (lane 1 left of the paving joint). The lab's "Distress map (LTPP)" view (`DistressMapCanvas`) draws
both lanes as one sheet with the fig. 137 symbols and the sheet 1-2 totals; the cross-section uses the same survey
rules (severity, straightedge, codes). Judgment calls, each a placeholder until checked against LTPP maps:

| What | Choice | Why |
|---|---|---|
| Fatigue severity | M once crack density reaches 0.08 m per 10 cm cell (a complete crocodile network at the 3B cell size), H once cracks pass 5 mm (spalling) or a pothole touches it | The manual's words are "few connecting cracks", "complete pattern", "spalled" |
| Fatigue occurrence | patches closer than 0.3 m are one area, rated at its worst severity, drawn as a rounded outline round it | "an area"; fig. 138 draws one outline per occurrence |
| Block area | the box the block cracks span, less fatigue, patches and potholes | Approximation of "the area divided into blocks" |
| Twins | a crack grown both ways from one start is one crack | The sim grows each crack as two |
| Labels | cracks under 0.6 m drawn and counted, not labelled | Legibility; the manual labels every distress |
| Not done | "adjacent random cracking within 0.3 m raises severity" | Needs a random-cracking test per crack |
| Not simulated | 10 shoving, 11 bleeding, 12 polished aggregate, 13 raveling, 15 pumping | The base shader draws polish and ravel, but the sim has no state for them |

Findings from the map: a 10 m section can never meet block cracking's 15 m occurrence rule (noted on the sheet);
straightedge rut depths include the broken surface of failed wheel paths (37 mm against the rut model's 25 mm cap)
and potholes under the straightedge (up to 89 mm), as a real straightedge would.

## Model 1: binder ageing, the NCHRP 973 Pavement Aging Model (proposal for review)

**Source:** Kim et al., NCHRP Research Report 973 (2021), "Long-Term Aging of Asphalt Mixtures for Performance
Testing and Prediction: Phase III Results", chapters 2, 4 and 5, Table 9 (`References/Asphalt/Long-Term Aging ...
Phase III Results .pdf`). It builds on NCHRP Report 871 (Phases I and II, same folder). Field-calibrated on cores
from 8 US states and Manitoba (LTPP SPS-8 sections, WesTrack, FHWA ALF, NCAT, MnROAD), with the oxidation
kinetics of Glaser et al. (2013). The report finds it predicts field ageing better than the MEPDG's Global Aging
System (R2 0.71 against 0.38 over all depths, fig. 34).

**What it predicts:** the binder's stiffness, log |G\*| at 64 C and 10 rad/s (kPa), at any age t and depth z.
Higher |G\*| is harder, more brittle binder.

**Equations (report numbering):**

1. Surface kinetics, integrated hour by hour over the surface temperature T (K), log |G\*| carried as the state
   from one hour to the next (fig. 17):
   log|G\*|kin = log|G\*|0 + M [ (1 - kc/kf)(1 - e^(-kf t)) + kc t ]   (1), t in days
   kf = Af exp(-Eaf / RT), kc = Ac exp(-Eac / RT)   (2), (3)
   Af = 1.25e13 /day, Eaf = 95.04 kJ/mol, Ac = 3.68e7 /day, Eac = 62.21 kJ/mol, R = 0.008314 kJ/mol K (universal).
   **Misprint found:** NCHRP 973 Tables 1 and 9 print Af = 1.25 x 10^3; NCHRP 871 Table 16 (where the constants were
   fitted) gives 1.25 x 10^13 for every mixture. With 10^3 the fast reaction would be ~10^9 times slower than the
   constant one and nothing ages; with 10^13, at 95 C kf = 0.41 /day and kc = 0.055 /day, and 8 to 32 lab days raise
   log |G\*| by 1 to 2 x M, as the reports' ageing plots show. 871 labels A in s^-1, but its kinetics equation (and
   973's) take t in days; per day is the reading that matches the data.
   Two reactions: a fast one that runs out, and a slow constant one. Hours below 20 C add almost nothing.
2. Depth (z in cm), from the surface ageing:
   APt = (log|G\*|kin,t - log|G\*|0) / M,  APmax = (4.5 - log|G\*|0) / M,  N = 0.477 exp(-0.226 AP(t=10 yr))
   log|G\*|t,z = log|G\*|0 + M ((0.916 z + APmax) / (z + 1)) (1 - exp(-N APt))   (22)
   At the surface it heads for log |G\*| = 4.5; deep down for 0.916 M above the start. The gradient with depth
   (oxygen reaching less far, UV at the top) comes out of this equation.
3. Asphalt content off the Superpave optimum: x (1 - 0.149 %ACdev)   (23). We take the optimum (factor 1).

**Inputs:**

- log |G\*|0 and M, the binder's: from its high performance grade (HPG), the report's least accurate route but the
  one that needs no lab tests: log|G\*|0 = 6.552 / (1 + (HPG / 107.167)^-4.068)   (26),
  M = 0.94 / (1 + (HPG / 82.68)^7.96)   (27). PG 64-22: log |G\*|0 = 0.72 (5.2 kPa), M = 0.83 (eq. 28 agrees: 0.82).
  The binder grade becomes a build-up input (on the asphalt layer).
- The surface temperature through the year, built from a small climate table instead of hourly records (the
  report used hourly EICM temperatures from MERRA-2 weather):
  - Climate: 12 monthly normals of the mean daily high and low air temperature, and the latitude. NOAA 1991-2020
    normals (www.ncei.noaa.gov, normals-monthly); later the LTPP section's own weather.
  - Pavement temperature from air temperature: the LTPP models of FHWA-RD-97-103 (Mohseni 1998, from 30 LTPP
    seasonal monitoring sites; `fhwa_1998_rd-97-103_ltpp_pavement_temperature_models.pdf`), H = depth in mm:
    high Tpav = 54.32 + 0.78 Tair - 0.0025 Lat^2 - 15.14 log10(H + 25)  (eq. 8, R2 76 %, RMSE 3.0 C)
    low  Tpav = -1.56 + 0.72 Tair - 0.004 Lat^2 + 6.26 log10(H + 25)    (eq. 7, R2 96 %, RMSE 2.1 C)
    They were fitted to monthly high (May-Sep) and low (Nov-Mar) temperatures at 25-275 mm; we apply them to each
    day's normal high and low at the surface (H = 0): a stated extrapolation.
  - The hours between: a daily cycle, coldest at 06:00, hottest at 15:00 (Pomerantz 2000: the pavement peaks at
    least an hour after the sun), half-cosines between. An assumption, labelled as one. Hours below 20 C are
    skipped (NCHRP 973: they add no measurable ageing).

**What it drives, in plan and section:**

- Section: binder stiffness through the asphalt layer, drawn as a gradient (hardest at the top), each year.
- Plan: the surface colour as a parameter, its albedo (solar reflectance, ASTM E1918). Pomerantz et al. 2000
  (LBNL-43442, `pomerantz_2000_lbnl-43442_pavement_albedo.pdf`, fig. 1): fresh asphalt 0.04-0.05; over 5 years
  0.12 +- 0.03, never over ~0.16; rising fast for ~4 years then flat. Causes named: binder wearing off the stones,
  the binder lightening as it oxidises, dirt. Bounded by the aggregate's albedo (0.10-0.28 for their stones).
  Proposal: albedo = a_fresh + (a_limit - a_fresh)(1 - exp(-p / p0)), p = the model's surface ageing
  (1 - exp(-N APt)); a_fresh = 0.04 (measured); a_limit and p0 fitted to fig. 1 in the Bay Area climate (Concord
  normals): about 0.13 and 0.15, giving 0.08 at 1 year, 0.11 at 3, 0.12 at 5 and 0.13 at 10 (0.127; a least-squares fit to 0.08 / 0.11 / 0.12 / 0.12 would give 0.123 and 0.125 instead). A two-number calibration
  against measured data, labelled as such. The grey drawn is the albedo as a linear reflectance.
- Later models: thermal cracking (a stiffer, more brittle layer) and fatigue, through NCHRP 973 chapter 6
  (the AMAC model: binder |G\*| to mixture properties), read when those models start.

**Chain run (docs/asphalt_checks/binder_ageing_chain.py, PG 64-22, NOAA normals), log |G\*| kPa, start 0.72:**

| Year | Burlington VT surface | at 2 cm | Concord CA surface | at 2 cm |
|---|---|---|---|---|
| 1 | 0.96 | 0.83 | 1.05 | 0.87 |
| 5 | 1.75 | 1.20 | 1.97 | 1.30 |
| 10 | 2.47 | 1.54 | 2.74 | 1.66 |
| 20 | 3.38 | 1.96 | 3.65 | 2.09 |

Burlington's surface spends 4,400 h a year above 20 C, Concord's 5,600; the hotter site ages faster, the surface
heads for 4.5, and 2 cm at 10 years (1.5-1.7) sits in the 1-3 range of the report's field cores (figs. 35-39).

**Checks before it is trusted:** the equations reproduce the report's numbers (Table 1 constants, eq. 26-28 for a
known HPG, the surface saturating at 4.5 and the deep value at 0.916 M); its depth profiles have the shape of
figs. 35-39 for a site of similar climate; ageing stalls in cold years and runs in hot ones.

**Not in it:** RAP, warm mix and polymer-modified binders (the report's outliers); air voids (found
insignificant); UV beyond what the depth calibration absorbs.

## Model 1b: the surface made of what the mix is made of (proposal for review; T2 step 6b)

**Why:** Model 1 gives one number, the albedo. Drawing the plan from it needs a texture, and a texture set by eye
(procedural noise, or a picture) is not data. Here the surface is composed from the mix itself: binder and
aggregate in the volumes the mix design measured, stones sized by the measured gradation, each with its measured
albedo. The mean albedo then comes out of the composition, and the plan and the section are two slices of one
3D mix. Like Substance Designer, the texture is computed; unlike it, every distribution is a measured one, and
the random seed only says where each stone lands.

**Sources (References/Asphalt):**
- The mix: MnROAD cell 18, wear course (4th lift, 38 mm), as built (Mn/DOT 97-06, Table 3.5): 100 / 99 / 93 / 84
  / 67 / 55 / 43 / 25 / 9 / 4.6 % passing 19 / 16 / 12.5 / 9.0 / 4.75 / 2.0 / 1.0 / 0.45 / 0.25 / 0.075 mm, 5.8 %
  asphalt, 3.2 % air voids, VMA 15.3 %. AC-20 (PG 64-22, the build-up's binder); the same cell as the build-up's
  cold strength (Li & Marasteanu Table 4). Aggregate: 90 % partially crushed Crow River gravel, 10 % crushed
  granite (97-06 Table 2.1). A 12.5 mm mix in FHWA-RD-98-087's terms (first sieve retaining over 10 %: 9.0 mm);
  its 2.0 mm value (55 %) sits at the top of the Superpave 2.36 mm band (28-58 %): a Marshall-era fine mix.
- Albedos: Pomerantz et al. 2000, Table 1: binder 0.05; aggregates 0.10-0.28; a chip seal (stones as exposed as
  a surface gets) reflects 0.67 +- 0.11 of its aggregate's albedo. Fig. 1: pavement albedo against age.
- Surface ageing p: Model 1.

**The model:**
1. Volumes: aggregate 1 - VMA = 84.7 %, effective binder VMA - air = 12.1 %, air 3.2 % (Pomerantz p. 3: about
   85 / 15).
2. Stones: the aggregate retained on each sieve from 2.0 mm up, one class per sieve pair (diameter the geometric
   mean of its sieves), its share of the aggregate volume from the gradation: 1 / 6 / 9 / 17 / 12 % for 16-19 /
   12.5-16 / 9-12.5 / 4.75-9 / 2-4.75 mm, so stones are 38.1 % of the mix volume. Finer aggregate is part of the
   mastic (binder + fines + air) and is drawn as the mastic's area average.
3. The 3D field: stones as spheres at random positions (a Boolean model: overlaps allowed), with intensities set
   so their union is exactly 38.1 % of the volume (sum lambda_i v_i = -ln(1 - 0.381)). Any plane through it shows
   stones over the volume fraction of its area (Delesse's principle) and cuts of mean diameter pi/4 d. The plan is
   the plane z = 0; the section A-B is the vertical plane at the cut. Scrubbing the cut moves through the same
   stones, and a stone cut at the surface line appears in both.
4. Albedo of each part: binder 0.05; aggregate a_agg, the rock's measured albedo; exposed aggregate shows a_agg,
   covered aggregate shows the binder. As the surface ages the binder wears off the aggregate (Pomerantz names
   this as the main cause), up to a chip seal's 0.67 a_agg:
   albedo = 0.05 + (0.67 a_agg - 0.05)(1 - e^(-p / p0)),
   and the share of the aggregate area that shows is (albedo - 0.05) / ((a_agg - 0.05) x 0.847). Each stone gets a
   random threshold and shows once that share passes it, so the exposed area is the model's at every year.
5. a_agg for cell 18 (option A, zack): no measured albedo for Crow River gravel; Pomerantz's rows of the same rock
   types stand in: river pebbles 0.21, granite 0.26-0.28, blended 90 / 10: 0.216. Ceiling 0.145 +- 0.024.
   **One calibrated number left:** p0, how fast the binder wears off against the surface ageing.

**Check run (docs/asphalt_checks/surface_composition.py):** volumes 84.7 / 12.1 / 3.2 %; a 0.5 m random plane
covers 37.4 % with stones (38.1 % expected) and its cuts average 0.79 d per class, as theory says (pi / 4); a 10 m
section through 76 mm of asphalt cuts about 27,000 stones (cheap to draw each time the cut moves). p0 = 0.26 fits
Pomerantz fig. 1 in Concord with an rms of 0.007: 0.077 / 0.105 / 0.118 / 0.133 at 1 / 3 / 5 / 10 years (his
0.08 / 0.11 / 0.12 / 0.12); Burlington 0.071 / 0.097 / 0.112 / 0.129. Model 1's two fitted numbers (limit 0.13,
p0 0.15) become one (p0), the limit now coming from the chip-seal measurement.

**Assumptions, stated:** spheres (aggregate shape: Gap); overlaps allowed (a hard-core packing would be the next
refinement; the volume and the Delesse fraction are exact either way); the surface is a flat plane through the
field (macrotexture, the stone tops standing proud: Wanted, for the height map); air voids drawn as binder (pore
albedo: Gap); exposure tied to the surface ageing (traffic wear is T4's); one albedo per rock type borrowed from
Pomerantz's California rocks.

**Gaps (left out until sourced):** binder lightening as it oxidises (Pomerantz names it, no number); aggregate
weathering (rock oxidises too: iron staining, feldspar to clay); stone colour (albedo is broadband; the plan stays
neutral grey); dirt and oil.

**Later, same method:** the base from its gradation (Class 6sp, Mn/ROAD aggregate profile 1996, Table 1), the
subgrade from its soil class; the LTPP section's own gradation (AG04) and aggregate when InfoPave is back.

**Scope change this needs:** "the mix's microstructure and stones" moves from *not studied* to studied, for the
drawing (the crack models still don't use it).

### Model 1b, second pass (Nov 27): packing, shape, macrotexture, what drives the albedo

**What drives the greying: wear, not oxidation.** "Albedo change mechanism of asphalt concrete surfaces",
Transportation Research Record 2676 (2022), pp. 763-772, doi 10.1177/03611981221082567 (abstract read; full text
paywalled, not filed): asphalt mixes aged in the lab by several methods kept an albedo of about 0.05 however much
they aged; an abrasion procedure that removes the surface binder reproduced the field rise on four field cores.
So **binder lightening is measured to be negligible** (the gap closes: binder 0.05, constant), and the exposed
aggregate grows with **wear** (traffic and weather), not with oxidation. Model 1's albedo and Model 1b as written
drive exposure by the surface ageing p (oxidation): **proposed change: drive it by age now and by traffic once
T4 exists.** The stiffness gradient (Model 1) is unaffected.

**Field data by aggregate colour.** NCAT Report 19-09, "Quantifying Pavement Albedo" (2019; filed): asphalt
sites in seven central and eastern US states, under 1 to over 30 years old; albedo rises and approaches a steady
value; fitted (fig. 97, recalibrated): albedo = (0.0001 CLR + 0.0033) ln(age) + (0.0001 CLR + 0.0812), CLR the
coarse aggregate's grayscale on 0-255 (measured on a core photo against a printed grey card, appendix); model
against field: mean difference 0.008, sd 0.029. Pomerantz's California curve (0.08 / 0.11 / 0.12 / 0.12) lies
inside NCAT's band for mid-grey aggregates (CLR 110-160: 0.092-0.097 / 0.108-0.118 / 0.115-0.128 /
0.125-0.142): two independent field sets agree. A log in age has no fresh value (age 0) and no ceiling, so it is a
calibration target for the exposure, not the model. Cell 18's Crow River gravel has no measured CLR: a Gap
(a photo of a MnROAD core against a grey card would close it).

**Packing: settle the stones with a physics engine.** Random placement can't reach the mix's stone volume
without overlaps: random sequential addition of equal spheres jams at about 38 %, exactly cell 18's coarse
fraction. Asphalt microstructure studies pack with discrete elements or a physics engine (e.g. Wan, García,
Hernández, "manufacture asphalt concrete virtually with a physics engine"; Xu, J. Mechanics, polyhedral
generation and packing; not yet read). Proposal: an offline bake (a tool, like the section bakes): drop the
stones of the measured gradation, largest first, as low-poly convex rigid bodies into a periodic box in Jolt
(already the game's physics), let them settle, compact (press and shake) until the coarse volume fraction is the
mix's 38 %, then place the 2-4.75 mm class in the remaining space; store the stones (centre, rotation, shape,
size) as a resource. A 0.2 x 0.2 m tile, 40 mm deep, holds about 16,000 stones (minutes, once per mix and seed),
repeated across the section (at the plan's 4.9 mm pixels the repeat is not visible; the section at 1:1 shows a
0.2 m period). Plan and section read the same resource, so they agree stone for stone.

**Shape: low-poly convex polyhedra, as data allows.** In hand: the share of crushed particles (Mn/DOT 97-06,
Table 2.1: Crow River coarse 61.2 % crushed, granite CA-50 100 %): crushed stones as angular hulls with few faces,
uncrushed river gravel as rounded hulls with more; Superpave's flat-and-elongated limit (FHWA-RD-98-087: at most
10 % beyond 5:1). Wanted: measured shape distributions (FHWA AIMS2, HIF-11-030, ch. 3: sphericity, angularity and
form for crushed gravel, limestone and granite; the FHWA page returned a server error on Nov 27).

**Macrotexture is the stones.** Yes: the surface is the top of the settled stones, with the mastic (binder,
fines, air) filled between them to the level its volume sets, not a flat cut. The height map comes from it, and
its mean profile depth becomes a **check**, not an input: FHWA-HRT-25-100 (2025, filed) eq. 1, MPD = 1.03 +
0.224 Type + 0.0034 Cu - 0.0050 P8 - 0.0105 P200 - 0.0049 VFA (field data, seven States), gives 0.35 mm for cell
18 (Cu 11.1, P8 57.3 %, P200 4.6 %, VFA 79.1 %); VTRC 23-R15 (2023, filed) measured 0.39-0.49 mm on Virginia
dense-graded surfaces. Exposure then has a place to happen: the binder film wears off the stone tops first.

### Model 1b, third pass (Nov 27): what each topic does to the albedo; the packing prototype

**Which sources do what.** Every number is sourced, but sources play three roles:
- *Inputs* (what the surface is made of): the mix (MnROAD cell 18, Mn/DOT 97-06), the component albedos
  (Pomerantz Table 1: binder 0.05, aggregates 0.10-0.28), the stone shapes and packing rules (Xu 2010).
- *Mechanism* (why it changes): binder wears off the stones by abrasion, oxidation alone does not lighten it
  (TRR 2022); ageing exposes minerals, cracks darken by shadow, seals stay dark, patches look fresh (Herold &
  Roberts 2005).
- *Targets* (what the result must reproduce): pavement albedo against age measured in the field (Pomerantz fig.
  1, California; NCAT 19-09, seven central and eastern states, by aggregate colour); mean profile depth
  (FHWA-HRT-25-100, VTRC 23-R15). NCAT's equation is a regression through its field data, not a mechanism: it
  calibrates and checks the model, it isn't the model.

**Every topic that changes the surface changes the albedo** (zack): the plan is an area-weighted sum of what lies
on it, each with its reflectance.

| Topic | What it does to the surface | Source so far |
|---|---|---|
| T2 binder ageing | Oxidation: no measurable albedo change (0.05) | TRR 2022 |
| T4 traffic | Abrasion strips binder off the stone tops, wheel paths first | TRR 2022 (mechanism), Pomerantz, NCAT (totals); rate per pass wanted |
| Climate | Weathering wears binder; wet surfaces darker; winter sand and salt | NCAT names it; numbers wanted |
| T3, T4 cracks | Dark by shadow (up to 7-8 % at high severity), expose fresher binder | Herold & Roberts |
| T5 potholes | Exposed base, standing water | Wanted |
| T6 repairs | Overlay and patch: fresh (0.05); crack seal about 5 %; chip seal brighter | Pomerantz, Herold & Roberts |
| The mix | Stone sizes, rock albedo, share exposed | Cell 18; Pomerantz; Xu |

Until T4 exists, age stands in for wear (one rate, calibrated on the field targets).

**Packing prototype** (`docs/asphalt_checks/stone_packing.py`): Xu stones (convex, 4-10 faces, Lmax/Lmin <= 5;
none beyond Superpave's 5:1 flat-and-elongated limit, 7 % beyond 3:1), packed largest first with Xu's
smaller-stone fallback into a 100 x 100 mm tile of cell 18's 38 mm wear course, periodic across. Learned from the
volumetrics: the stones fill only 38 % of the mix, below any settled packing (~55-60 %), so they float in the
mastic and **no physics settling is needed** in the bulk. Learned from the sim's grids: random tries jam at 24 %;
a voxel map of free space (0.5 mm), shrunk by each stone's half size, proposes only positions with room, and the
exact separating-axis test still decides (speed only, not the result). The roller turns stones near the surface
onto their most upward face and pushes them against it (a convex body pressed by a plate rests on a face).
Results: 7,333 stones, **38.5 % stone volume (mix 38.1 %)**, every size class at its share; Delesse: averaged
vertical cuts 38.7 % (sd 1.0 per cut); stone share by depth 27 % in the top 4 mm (the roller's wall effect), about
40 % below; stone tops reach the surface over 14 % of the plan. 900 s in Python, once per mix and seed (a compiled
bake would be far faster). **Not yet a check:** the mean profile depth depends on how far the mastic sits below
the stone tops, which nothing here predicts: 0.45-0.6 mm gives 0.35-0.49 mm (FHWA-HRT-25-100 and VTRC 23-R15).
Until a source sets that level (binder film and mastic at the surface), MPD calibrates it and the albedo targets
check it. Also wanted: a source for how compaction orients stones near the surface (CT studies).

### Model 1b, fourth pass (Nov 27): from a tile to the road; exposure from the packed stones

**Scale: a tile stands for the mix if it holds enough of every stone size.** Studies of asphalt's representative
volume put it at about 50-60 mm for dense-graded Superpave mixes (60 mm for a 12.5 mm mix), roughly 4-5 times the
nominal size (search summaries; Romero & Masad 2001 and Kim et al. 2009 to read). Our check: a 50 mm tile (seed 7)
against the 100 mm tile (seed 1). The exposure curve agrees within about a point of stone share up to 1.5 mm of
wear; the 50 mm tile overshoots on the largest stones (one 17 mm stone is 341 % of that class's share in so small a
tile: 40.3 % stone instead of 38.1 %), the 100 mm tile holds three (114 %). So 50 mm is the smallest that works,
100 mm is comfortable. Per-cut scatter falls with size as expected (Delesse sd 2.3 % at 50 mm, 1.0 % at 100 mm).

**From the tile to a road, without repeats:** periodic copies of one tile repeat every 100 mm, invisible in the
plan at 4.9 mm pixels but visible in the section at full scale. The graphics answer is Wang tiles (Cohen et al.,
SIGGRAPH 2003: a small set of tiles with coloured edges, laid at random with matching edges, tiles the plane
non-periodically; they fill tiles with Poisson distributions and 3D geometry) or corner tiles (Lagae & Dutré, better
for Poisson-disk distributions, which is what stone centres are). Proposal: pack a set of tiles (for Wang tiles
with two edge colours each way, 16) so that the stones crossing each edge colour are shared, then tile the road at
random from them. Packing cost: 16 tiles, once per mix. Variation at the road scale (wheel paths, wear, repairs)
does not come from the tiles: it comes from the topics, as a field the sim already carries over the road (traffic
wears the wheel paths deeper, so more stone shows there). Two scales: the mix in the tile (mm), the state in the
sim (cm to m).

**Exposure from the packed stones** (`docs/asphalt_checks/surface_exposure.py`): the surface wears to a depth w;
a stone shows where its top is above the worn level and it still reaches below it (one entirely above has
ravelled). Share of stone showing A(w), 100 mm tile: 14 % once the binder film is off (0.1 mm), 23 % at 0.5 mm,
32 % at 1 mm, 42 % at 2 mm; albedo = 0.05 + (a_agg - 0.05) A. Two independent data sets meet here: the MPD
calibration puts the mastic about 0.5 mm below the stone tops as built, where 23 % of the plan is stone under its
binder film (microns thick: 6-10 um by the mix-design rule, 0.5-2.4 um measured in one study); once the film wears,
the albedo is 0.088, against Pomerantz's 0.08 and NCAT's 0.09-0.10 at one year, with nothing fitted to albedo.
After that, matching Pomerantz needs about 0.75 mm more mastic wear by year 3 and 1.3 mm by year 5, then little;
NCAT's continued rise (0.12-0.14 at 10 years) needs about 3 mm by year 10. Whether those wear depths are right needs
measured surface wear rates (Wanted; T4's traffic). A stand-in mechanism for the flattening, not sourced: once the
stone tops carry the tyres they shield the mastic between them.

**Stone orientation near the surface:** CT studies find compaction orients stones perpendicular to its direction
(gyratory), slab rolling mimics field orientation better than gyratory compaction (Airey and Collop), and the
voids are higher at mid-depth than near the surface (search summaries; papers not yet read). Consistent with the
face-down roller and with fewer stones in the top 4 mm (27 %); quantitative orientation data still Wanted.

**Corner-tile road** (`docs/asphalt_checks/corner_tiles.py`; Lagae 2007): two corner colours at random on the road's
100 mm lattice; 16 tiles; 2 corner patches, 8 edge strips and 16 interiors, each packed once and checked against
every part it can meet, so any colouring assembles without overlaps. Seams are 22 mm half-wide: a stone reaching
further is redrawn (4.5 % of the 16-19 mm class, 0.5 % of the 12.5-16 mm, the most elongated). Two lessons on the
way: (1) a part must count the stone volume actually inside its region, neighbours' spill included, not its own
stones by centre (else 39.9 % overall); (2) size classes must go largest first across the whole set, not part by
part (else 36-37 % within 25 mm of a seam and 40-43 % mid-tile). Result, random 4 x 4 road (400 x 400 mm, 55,200
stones in the set, 17 min on 4 cores): **no point in two stones (of 400,000); 38.5 % stone (mix 38.1 %), 37.5-39.2 %
per tile; mid-tile 38.1 %**. Left: about 40 % within 15 mm of a seam line and a narrow dip to 34-35 % where strips
meet interiors (22 mm off the seam), every 100 mm; about 0.002 of albedo, below what the plan can show. A long
section crosses the seams without a visible join. Next refinement if needed: interleave strips and interiors in
two rounds within each class.

**Stone shape against measurement** (FHWA AIMS2, HIF-11-030, filed): AIMS sphericity cbrt(d_s d_i / d_l^2) of 3,000
Xu stones: mean 0.70 (10-90 %: 0.60-0.80); 6.8 % beyond 3:1. Measured: crushed gravel 0.68-0.70 and 0.6-3.8 %;
granite 0.60-0.68 and 5.2-9.7 %. Cell 18 is 90 % gravel (61 % of its coarse part crushed): the sphericity matches,
the share beyond 3:1 is a little high; a check to tighten (e.g. a lower S_max for the gravel), not a calibration.

**Where the bake runs (decided with zack, Nov 28):** offline, in Python (numpy), writing the packed tiles as a
resource the game loads; not in GDScript, which would be far slower for 16 tiles of thousands of stones each. It
only runs when the mix changes, like the section bakes. What could haunt us later, and the answer: (1) a Python
dependency to rebake (the repo already has Python tools; numpy only); (2) a second implementation if the game ever
needs to pack at run time (then port the core to a GDExtension; the format stays); (3) the file format, kept simple
and documented (per stone: tile, class, vertex list), so either side can change.

**Rock weathering and dirt: still Gaps.** No measurement for asphalt aggregate found. The nearest are concrete
studies (Levinson and Akbari, LBNL: simulated weathering, soiling and abrasion changed concrete albedo by about
-0.06, -0.05 and -0.19), which are not our material and are not used. NCAT names winter maintenance (sand, salt)
as a possible factor, without numbers.

## Model 2: thermal cracking (proposal for review; T3)

**Status: written up from the sources below; not yet checked in Python; no code.** Every number quoted is from
the report named next to it; "derived" marks our own algebra on a sourced equation; gaps are listed at the end.

### Sources, and what each gives

| Source (References/Asphalt) | Read for | What T3 takes |
|---|---|---|
| Li, Marasteanu, Dai, Lukanen 2005 (`li_marasteanu_2005_...`) | all | Frictional constraint model, eqs. 2 and 4; Jones's alpha, eq. 3; MnROAD cells 18, 21, 22 (Tables 1, 2, 4, 5); TCMODEL predicted no cracking there (Table 3) |
| Marasteanu et al. 2007, Mn/DOT 2007-43, "Investigation of Low Temperature Cracking in Asphalt Pavements", pooled fund study (`mndot_2007-43_...`, filed this thread) | ch. 2 (TC model, alpha), ch. 3-6 (mixes, IDT, TSRST, dilatometry), ch. 9 (TCMODEL against field) | TCMODEL as implemented (eqs. 22-40); a measured low-temperature data set for a PG 64-22 mix; MnROAD field cores; TCMODEL's field record |
| Von Quintus et al. 2024, MassDOT 24-067, Pavement ME calibration phase III (`massdot_2024_...`, filed) | ch. 5.1 | The current transverse cracking equations and the 2018 global calibration (eqs. 12-17) |
| Kim et al. 2021, NCHRP 973, ch. 6 (`Long-Term Aging ... Phase III ...`) | ch. 6 in full | AMAC: binder log abs(G\*) change to a shift of the mix's modulus master curve (eqs. 37, 51) |
| Chen et al. 2022 (`chen_...`) | all | Halving of spacing, eqs. 14-15 (mean = 3/4 of the largest uncracked spacing); shear-lag stress, eq. 7; measured asphalt alpha 15-22 x 10^-6/C (Table 2) |
| Bohn et al. 2005; Shorlin et al. 1999 | all | Cracks one at a time, each dividing a domain near its middle, meeting older cracks at 90 deg; spacing proportional to thickness, larger on a slipperier base |
| FHWA-HRT-16-084 (2019), LTPP environmental factors (`fhwa_2019_...`, filed) | ch. 1 | Mechanisms named (cold events, repeated cycles with oxidation, long-term shrinkage); widths grow over time; no rates |

### What it predicts

When and where transverse cracks open in a winter, how far down they go, their spacing as the road ages, and the
seasonal opening of each crack. Not the LTPP severity growth over the years (Gap, below).

### How the sources disagree, and the choice proposed

**The MEPDG thermal cracking model (TCMODEL)** (Hiltunen and Roque 1994, as restated in Mn/DOT 2007-43 ch. 2 and
MassDOT 24-067 ch. 5.1; the primary text, NCHRP 1-37A Appendix HH, is Wanted):
1. Thermal stress: the mix's coefficient of contraction (Jones et al. 1968, Mn/DOT eq. 22:
   alpha_mix = (VMA B_AC + V_agg B_agg) / (3 x 100), B_AC = 3.45 x 10^-4 /C volumetric for every binder),
   creep compliance from IDT tests at -20, -10 and 0 C fitted to a master curve (eqs. 24-27), converted to a
   relaxation modulus (eqs. 28-29), and the 1D hereditary integral solved by the Soules recursion (eqs. 30-32).
2. Crack growth: K_I = sigma (0.45 + 1.99 C0^0.56) (eq. 33), Paris law Delta C = A Delta K^n per daily cycle
   (eqs. 34-35), n = 0.8 (1 + 1/m) (eq. 38), A = 10^(kt beta_t (4.389 - 2.52 log(E sigma_m n))) (MassDOT eq. 15).
   The layer is split in four sublayers and a crack crosses at most one per day, so four severe days make one
   full-depth crack (Li and Marasteanu p. 4).
3. Amount: TC = beta_t1 N(log(C_d / h_ac) / sigma_d) (MassDOT eq. 17), sigma_d = 0.769, beta_t1 = 400.
   **The units, checked by arithmetic:** a crack is counted only at full depth, where N(0) = 0.5, so the model
   gives at most 200 of beta_t1's 400. Mn/DOT 2007-43 says the output is ft per 500 ft and that the model "does not
   predict more than 50 % of the total possible amount" with a minimum spacing of 15 ft: 400 ft per 500 ft is a
   full 12 ft lane crack every 15 ft, so beta_t1 is in ft per 500 ft. MassDOT and the Missouri report label TC ft/mi
   with the same 400; the software converts somewhere, which only Appendix HH or the Manual of Practice can settle.
4. Calibration has moved: k = 10,000 and beta = 353.5 (Mn/DOT 2007-43 ch. 2, restating the 2004 guide); a level
   factor 1.0 / 6.0 (version 0.964, Mn/DOT ch. 9); kt per input level, beta_t1 = 400 (2015 manual, Missouri report);
   **2018 global: kt = 3 x 10^-7 MAAT^4.0317 for MAAT < 57 F** (MassDOT eq. 16), added because the event-based
   model never predicted cracks in mild climates, where they occur (MassDOT p. 31). Burlington, MAAT 47.6 F from
   the NOAA normals: kt = 1.74.

Its record: at level 3 it predicted **no** cracking in MnROAD cells 18, 21 and 22, which cracked at 4.8-8.2 m
(Li and Marasteanu Tables 3, 5); in Mn/DOT 2007-43 (Table 9.1, version 0.964, ft per 500 ft) it was close on MnROAD 03 (192 against 182) and
34 (0-7 against 6), off by 2-4x on 33, capped below cell 19's observed 547, missed 35 and overpredicted three
other sections. The Mn/DOT authors call the Paris law step "the weakest link". **It gives an amount
(length per section), not positions, spacing or widths,** and it saturates at a 9 m spacing (15 ft at the 400
ceiling).

**The frictional constraint model** (Timm 2001 via Li and Marasteanu): a crack forms at once where the thermal stress
reaches the mix's strength; friction and cohesion on the base rebuild the stress over the slip length
Xc = sigma_t / (C/h + rho g tan phi) (eq. 4) from each free end; spacing 1.5 Xc. Against MnROAD it predicts
spacing about 2x too wide; the authors trace that to base properties measured warm (frozen cohesion is larger;
1.5-2x would match), and it doesn't tell the driving lane from the passing one.

**Proposed for the picture: TCMODEL's stress calculation (part 1, mechanics) with the frictional constraint
model's strength criterion and spacing. TCMODEL's Paris law, crack amount and calibration (parts 2-3) are left
out.** Reasons: the picture needs positions and spacing, which only the frictional model gives; MnROAD's cracks
formed mostly in one winter at -39 C (Li and Marasteanu p. 4), which a strength criterion describes and the
four-sublayer rule cannot; parts 2-3 depend on an empirical kt that changed four times. The TCMODEL amount stays
as a cross-check in the Python run (ft per 500 ft against our crack count), not as a driver. **zack's call.**

### Equations of the proposal

1. **Contraction coefficient, measured.** Mn/DOT 2007-43 dilatometry (eq. in ch. 6, from Bahia et al.):
   v = c_v + alpha_g (T - Tg) + R (alpha_l - alpha_g) ln(1 + exp((T - Tg)/R)),
   a two-slope strain-temperature curve: alpha_l above the glass transition Tg, alpha_g below. (The report's
   definitions after the equation in ch. 5 swap the two; its ch. 2 and ch. 7 text and every table put the larger
   coefficient, alpha_l, above Tg, as physics requires. We read it that way.) Jones's volumetric estimate
   (Li and Marasteanu eq. 3) is kept as a cross-check only: it is one number with no Tg.
2. **Creep compliance and relaxation of the unaged mix** (TCMODEL part 1, Mn/DOT eqs. 24-29): D(xi), xi = t / aT,
   from IDT creep at three temperatures; Prony series to E(xi).
3. **Ageing: AMAC** (NCHRP 973 eq. 51, Level 2): log aA = c (log abs(G\*)_aged - log abs(G\*)_STA), both at 64 C
   and 10 rad/s, **c = 1.71** (the universal value; per-mix c ran 1.00-2.43, Table 21). The aged mix at depth z and
   age t relaxes like the unaged mix at reduced time xi = t / (aT aA). Delta log abs(G\*) is exactly what T2 gives:
   `BinderAgeing.log_g(z, t) - log_g0` (PAM's log abs(G\*)_0 is the short-term-aged value, which AMAC's reference
   is). The temperature shift aT stays the unaged one (AMAC's stated assumption, p. 105).
4. **Thermal stress, fully restrained, through the depth** (Mn/DOT eqs. 30-32, Soules recursion):
   sigma_i(t) = e^(-Delta xi / lambda_i) sigma_i(t - Delta t) + Delta epsilon E_i (lambda_i / Delta xi)(1 - e^(-Delta xi / lambda_i)),
   sigma = sum sigma_i, Delta epsilon = alpha(T) Delta T, with T(z, hour) from T2's `PavementTemperature`.
5. **Initiation, by strength.** A crack forms in a segment when the stress at its middle reaches the strength:
   sigma(z, t) >= sigma_t at the surface. It goes down to the depth where sigma(z, t) falls below sigma_t (the
   colder, stiffer, more aged top cracks first; later events can deepen it). A crack at full depth is a transverse
   crack in the LTPP sense.
6. **Where: spacing by halving (derived, linking Li and Chen).** From a free end, friction builds the stress at
   C/h + rho g tan phi per metre (Li eq. 4), so in a segment of length L between two cracks the stress at its
   middle is at most (L/2)(C/h + rho g tan phi). A new crack forms at the middle (Bohn: nucleation near the
   domain's centre; Shorlin: in the middle of segments where the stress is highest) only if the restrained
   stress reaches sigma_t **and** L >= 2 Xc. Segments therefore end between Xc and 2 Xc long; halving from 2 Xc gives
   Chen's mean of 3/4 x 2 Xc = **1.5 Xc, the same factor Li and Marasteanu use**: the two papers agree.
   Order of cracking: cracks don't all appear in the first cold snap. Each segment gets its own strength, drawn
   from the measured scatter (IDT strength CV mostly 2-19 % on MnROAD cores, Mn/DOT Table 6.14: an assumption that
   specimen scatter stands for scatter along the road), so the weakest crack first and more follow as the binder
   ages and colder winters come. When C/h dominates (here 815 against 29 kPa/m), Xc ~ sigma_t h / C: spacing in
   proportion to thickness, as Bohn and Shorlin found in their layers.
7. **Seasonal opening (derived, a mechanics consequence of eq. 6; no field source yet).** A segment of length L
   between two cracks, cooled by Delta T below its stress-free state, closes its gap by the free shrinkage less
   what friction holds back: w = alpha Delta T L - (C/h + rho g tan phi) L^2 / (4E) for L/2 below the slip
   distance. For L = 4 m, alpha 2 x 10^-5, Delta T 40 C: w ~ 3.2 mm, the friction term about 0.2 micrometre. That is
   low severity at the coldest, and it closes in summer. It is not the permanent widening LTPP grades (Gap).

### Inputs, and where they come from

| Input | Value proposed (source) | Arrives from |
|---|---|---|
| Pavement temperature T(z, hour) | `PavementTemperature` (FHWA-RD-97-103 eqs. 7, 8) | T2, built |
| Binder log abs(G\*)(z, year) | `BinderAgeing.log_g()` | T2, built |
| **Daily air minimum, year by year** | NOAA GHCN-Daily for the site (or the LTPP section's weather) | **New input (climate).** The normals T2 uses make Burlington's coldest surface -8.4 C: never cold enough to crack anything (TSRST fracture of the reference mix: -25.9 C). Thermal cracking is set by the extremes (MnROAD: one -39 C winter). Needs a row in the shared quantities table, agreed in the hub |
| Contraction coefficient: Tg, alpha_g, alpha_l | PG 64-22 granite lab mix "64-22:U1:4:GR": Tg -27.9 C, alpha_g 10.95, alpha_l 33.20 x 10^-6 /C (Mn/DOT Table 6.19, cooling). For the AC-20 binder of the build-up: MnROAD cell 19 core: -15.3 C, 13.26, 38.60 (Table 6.22, one specimen) | New input on the asphalt layer |
| Unaged creep compliance (creep stiffness 1/D) | 64-22:U1:4:GR, Table 6.5, simple averages: 0 C 3.17 / 1.18 GPa, -12 C 10.24 / 5.55 GPa, -24 C 23.87 / 18.32 GPa at 60 / 500 s | New input on the asphalt layer (a master curve fitted to these six points: the Python check) |
| Strength sigma_t | Proposed: the TSRST fracture stress of the same mix, 2.82 and 3.02 MPa at -26.8 and -25.0 C, 10 C/h (Table 6.17): measured under restrained cooling, the load the model describes. IDT at 12.5 mm/min for comparison: 4.16 / 5.98 / 6.28 MPa at 0 / -12 / -24 C (Table 6.6) | Replaces the build-up's 2.27 MPa (cell 18 IDT at a slow rate, Li Table 4), which T1's slip length uses: **one owner for sigma_t, agreed in the hub** |
| Strength scatter | CV mostly 2-19 %, one 38 % (Mn/DOT Table 6.14, field cores) | Assumption, stated |
| h, rho, C, tan phi; Xc | build-up; `AsphaltSimState.slip_length()` (2.69 m now; 3.46 m with sigma_t 2.92 MPa) | T1, built |
| AMAC c | 1.71 (NCHRP 973, Level 2) | constant |

The reference mix (12.5 mm Superpave, PG 64-22, granite, 6.0 % binder, 4 % air) is not cell 18's Marshall mix;
it is the closest complete data set in hand to the build-up's binder grade. Cell 19's cores (AC-20, the
build-up's binder, aged about 12 years) give alpha and aged creep and strength for comparison, not an unaged curve.

### What it drives

- **Plan:** transverse cracks across each lane at the segment middles, appearing in the winters where they form;
  their opening drawn at the season shown (eq. 7). Paths still follow the crack-geometry rules already in the
  code (Bohn, Shorlin: 90 deg junctions).
- **Section:** at a cut crossing a crack, the crack from the surface down to its depth (eq. 5); full depth once
  through.
- **Distress map:** transverse cracks (ACP 6) counted and measured; severity stays low until widening has a source.

### Checks (the Python run, next step)

1. **TSRST:** cool the reference mix at 10 C/h, fully restrained (eqs. 1, 2, 4): the stress reaches the measured
   2.92 MPa near the measured -25.9 C (Table 6.17). This tests alpha, the master curve and the stress recursion
   together, against data not used to fit them.
2. Jones's eq. 3 with cell 18's volumetrics against Li and Marasteanu's 1.862 x 10^-5 /C, and against the measured
   two-slope curve.
3. Li and Marasteanu Table 4 reproduced: Xc 6.7 / 5.9 / 7.0 m for cells 18 / 21 / 22.
4. The halving rule with strength scatter gives a mean spacing near 1.5 Xc and a spread to compare with
   MnROAD's (cell 18 driving lane 15.8 +- 7.35 ft, Li Table 2; their table says ft and Table 5 confirms it).
5. Ageing: the restrained-cooling fracture temperature warms with T2's log abs(G\*) at 1, 5, 10, 20 years
   (Burlington, surface and 2 cm): an aged layer cracks at a milder cold (roadmap check "a more aged binder
   cracks sooner").
6. Climate: with the normals nothing cracks; with a daily record the first cracks come in the coldest winters,
   more in a colder site (roadmap check "a colder climate gives more thermal cracks").
7. TCMODEL's amount for the same run (eqs. 33-40 with kt 1.74) beside our count, to show the difference.

### Not in it, and gaps

- **Crack widening over the years (LTPP L/M/H): Gap.** No source with rates found. FHWA-HRT-16-084 (p. 9) says widths
  of shrinkage cracks "continually increase over time" and reach 1 in in Arizona and Utah; Alaskan instrumented
  cracks stayed constant or closed slowly (AK-RD-86-26, not reachable from this session). Needed: LTPP yearly
  transverse crack counts by severity (InfoPave, blocked) or a field width study.
- **Block cracking: not predicted.** The same criterion across a lane: a longitudinal crack needs half the lane
  width to reach Xc; 3.65 m / 2 = 1.83 m < 2.69 m, so no longitudinal thermal crack forms inside a lane of the
  default build-up. LTPP ties block cracking to shrinkage and daily cycling of an aged mix; no model in hand. Gap.
- **Strength ageing: Gap.** AMAC gives the modulus and fatigue (S-VECD) properties, **not strength** (the roadmap
  said strength: corrected). Held at the unaged value. Cell 19's aged cores (4.67 / 4.22 / 3.86 MPa at -12 / -24 /
  -36 C, IDT 12.5 mm/min) only bound it.
- **AMAC at low temperature: an extrapolation.** It was fitted at 4-40 C, with the Hirsch-limited sigmoid
  underestimating the modulus at the cold end (NCHRP 973 p. 82, 105); here it shifts creep compliance at 0 to -30 C.
- **Frozen base:** C and tan phi are room-temperature values (Li and Marasteanu: frozen cohesion larger). Gap.
- **The paving joint** (the centreline) as a weak plane, its own strength: Gap.
- **Driving against passing lane** (traffic shortens the spacing, Li and Marasteanu Fig. 2): not modelled (T4).
- **Long-term shrinkage in mild climates** (the reason for the 2018 kt): out of scope until sourced.
- **Semi-rigid bases** (Chen's subject: cement- or lime-treated base cracking and reflecting): out of scope.

**Wanted (blocked from this session; zack to file in References/Asphalt if he can get them):**
`nchrp_1-37a_2004_appendix_hh_thermal_cracking.pdf` (onlinepubs.trb.org/onlinepubs/archive/mepdg/2appendices_HH.pdf:
TCMODEL's calibration and the level 3 creep and strength correlations), NCHRP 1-37A Part 3 ch. 3 (same site);
the AASHTO MEPDG Manual of Practice (2020, paywalled); Hiltunen and Roque 1994 and Jones et al. 1968 (AAPT,
paywalled); Alaska DOT AK-RD-86-26 (crack widths; host refused).

## Next steps

The roadmap (`docs/ASPHALT_ROADMAP.md`) is the tracker; this list is kept short.

Done (Nov 2026): the build-up as data and editable; LTPP survey, distress map and cross-section; the sim split by
concern; the placeholders taken out of the lab (`placeholders` off: it shows the structure only, and the road
does not age yet).

1. **Binder ageing** (scope step 2): read TTI 0-6009-2 (pavement temperature, oxidation kinetics, oxygen
   diffusion with depth, hardening); write the model and its equations here for review; then code it as its own
   file with its own checks. It drives the surface's greying in plan and the hardening with depth in section.
2. **The LTPP section:** verify a candidate on InfoPave (down for maintenance on Nov 27) and take its build-up,
   climate and traffic as the lab's inputs and its distress surveys as the target. Shortlist (unverified): 50-1002
   Vermont, 56-1007 Wyoming, 83-1801 Manitoba.
3. **Thermal cracking** (scope step 3), then **load fatigue** (step 4), each replacing its part of
   asphalt_sim_rules.gd.
