class_name PavementBuildup
extends Resource
## A pavement cross-section: its layers from the top down, on a subgrade of a given CBR. AsphaltSim works out its
## crack spacings, cell sizes and fatigue scaling from it. Presets are in assets/asphalt/buildups/ (c620 parking
## lot tables, References/Levels/c620content.pdf).

@export var title := ""
@export_multiline var source := ""
@export var layers: Array[PavementLayer] = []   ## top to bottom
@export var subgrade_cbr := 0.0                 ## California Bearing Ratio of the subgrade (c620: good 9, moderate 6)

const PSI := 6894.757                           ## Pa
const PCI := 271447.1                           ## Pa/m (psi per inch)


## The asphalt layers bonded together at the top (surface and asphalt base courses), as one layer.
func asphalt_thickness() -> float:
	var h := 0.0
	for l in layers:
		if l.kind != PavementLayer.Kind.ASPHALT:
			break
		h += l.thickness
	return h


## The top asphalt layer: its properties stand for the bound asphalt.
func surface() -> PavementLayer:
	return layers[0] if not layers.is_empty() else null


## The first layer under the asphalt (what it slides on), or null for full-depth asphalt on the subgrade.
func base() -> PavementLayer:
	for l in layers:
		if l.kind != PavementLayer.Kind.ASPHALT:
			return l
	return null


## Pa: the subgrade's resilient modulus from its CBR, Mr = 2555 CBR^0.64 psi (MEPDG, NCHRP 1-37A, one of several
## CBR correlations; a correlation, not a test).
func subgrade_mr() -> float:
	return 2555.0 * pow(subgrade_cbr, 0.64) * PSI


## Pa/m: the modulus of subgrade reaction, k = Mr / 19.4 with Mr in psi and k in pci (AASHTO 1993, an empirical
## plate-load relation). The aggregate base's extra support is left out.
func subgrade_k() -> float:
	return subgrade_mr() / PSI / 19.4 * PCI
