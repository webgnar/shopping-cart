class_name RingingPart
extends Resource
## One part of the cart that rings when struck (the basket's wires, the frame's tubes, a wheel), described by what it
## physically is. Its ringing frequencies and how fast each dies away are worked out from that (ImpactSynth uses
## them), so nothing here is a recording:
##  - ROD / TUBE: a steel bar free at both ends (Euler-Bernoulli beam). Mode n rings at
##    f = (b_n)^2 / (2 pi L^2) * sqrt(E I / (rho A)), b_n = 4.730, 7.853, 10.996, ... ; for a solid rod of diameter d,
##    sqrt(I / A) = d / 4; for a tube of outside D and inside d, sqrt(I / A) = sqrt(D^2 + d^2) / 4.
##    A part made of many bars (a wire grid) gives several spans between length_min and length_max.
##  - LUMPED: one thing bouncing on its own stiffness (a polyurethane wheel on its tyre): one mode at `frequency`.
## Each mode decays at sigma = pi f eta (eta = the loss factor, rising with frequency by loss_per_khz).
## Where it is hit matters, as on the real thing. The part sits in `region` (a box in the frame's space; the cart's
## nose is +X): a hit outside it reaches it weakened over `falloff` m. Along the bars (`along` axis) the hit point
## picks the modes by their shape (a hit at a node of a mode doesn't ring it). Across the bars (`across` axis) it
## picks which spans ring: the bars near the hit.

enum Shape { ROD, TUBE, LUMPED }

const BEAM_ROOTS := [4.7300, 7.8532, 10.9956, 14.1372, 17.2788, 20.4204]

@export var shape := Shape.ROD
@export var length_min := 0.1         ## m: shortest free span
@export var length_max := 0.1         ## m: longest free span
@export var spans := 1                ## how many different span lengths between those two
@export var diameter := 0.005         ## m: rod diameter, or a tube's outside diameter
@export var wall := 0.0015            ## m: a tube's wall
@export var youngs_modulus := 2.0e11  ## Pa (steel)
@export var density := 7850.0         ## kg/m^3 (steel)
@export var modes_per_span := 4
@export var frequency := 200.0        ## Hz: LUMPED only
@export var loss := 0.006             ## loss factor eta at low frequency: steel ~0.001, welded or bolted ~0.005-0.01
@export var loss_per_khz := 0.001     ## eta added per kHz (air and joints damp high modes faster)
@export var level := 1.0              ## how loud this part is next to the others
@export var frame_coupling := 1.0     ## how much a hit on the frame shakes this part
@export var wheel_coupling := 0.0     ## how much a wheel hitting the ground shakes this part
@export_group("Where")
@export var region := AABB(Vector3(-0.1, 0.0, -0.35), Vector3(1.2, 1.1, 0.7))   ## m, in the frame's space
@export_enum("X", "Y", "Z") var along := 0     ## the axis the bars run along
@export_enum("X", "Y", "Z") var across := 2    ## the axis the bars are spread over (span order)
@export var falloff := 0.3            ## m: a hit this far outside the region shakes it 1/e as much


## How much a hit at `p` (frame space) rings mode `n` of span `span`, 0..1.
func weight_at(p: Vector3, n: int, span: int) -> float:
	var outside := (p.clamp(region.position, region.end) - p).length()
	var w := exp(-outside / falloff)
	if shape == Shape.LUMPED:
		return w
	var q := ((p - region.position) / region.size).clamp(Vector3.ZERO, Vector3.ONE)
	# Free-free beam mode shape at the hit point, scaled so the ends are 1.
	var b: float = BEAM_ROOTS[n]
	var x: float = b * q[along]
	var sg := (cosh(b) - cos(b)) / (sinh(b) - sin(b))
	w *= absf(cosh(x) + cos(x) - sg * (sinh(x) + sin(x))) / 2.0
	if spans > 1:
		var d: float = (q[across] - float(span) / (spans - 1)) * (spans - 1)
		w *= exp(-d * d)
	return w


## [[frequency Hz, decay rate 1/s, gain, mode n, span], ...] for every mode below max_hz.
func modes(max_hz: float) -> Array:
	var out := []
	if shape == Shape.LUMPED:
		out.append([frequency, PI * frequency * (loss + loss_per_khz * frequency / 1000.0), level, 0, 0])
		return out
	var r_g := diameter / 4.0
	if shape == Shape.TUBE:
		var inner := maxf(0.0, diameter - 2.0 * wall)
		r_g = sqrt(diameter * diameter + inner * inner) / 4.0
	var c := r_g * sqrt(youngs_modulus / density)
	for s in spans:
		var l := length_min if spans == 1 else lerpf(length_min, length_max, float(s) / (spans - 1))
		for n in mini(modes_per_span, BEAM_ROOTS.size()):
			var b: float = BEAM_ROOTS[n]
			var f := b * b / (TAU * l * l) * c
			if f > max_hz:
				break
			var eta := loss + loss_per_khz * f / 1000.0
			out.append([f, PI * f * eta, level / sqrt(float(n + 1)), n, s])
	return out
