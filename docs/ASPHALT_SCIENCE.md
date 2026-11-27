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
  normals): about 0.13 and 0.15, giving 0.08 at 1 year, 0.11 at 3, 0.12 at 5 and 10. A two-number calibration
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
