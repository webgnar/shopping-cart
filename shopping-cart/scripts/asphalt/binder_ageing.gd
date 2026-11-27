class_name BinderAgeing
extends RefCounted
## Binder ageing (T2): the NCHRP 973 Pavement Aging Model (Kim et al. 2021, ch. 2, 4, 5, Table 9). Hardens the
## binder year by year, fastest at the surface and in hot weather. Gives the binder stiffness log |G*| (kPa, at
## 64 C and 10 rad/s) at any depth and year, and the surface ageing p. docs/ASPHALT_SCIENCE.md, Model 1.
##
## Surface kinetics (eqs. 1-3), integrated hour by hour over a normal year of surface temperatures
## (PavementTemperature), carrying log |G*| from one hour to the next through the equivalent time (fig. 17):
##   rise(t) = M [ (1 - kc/kf)(1 - e^(-kf t)) + kc t ],  kf = Af e^(-Eaf/RT),  kc = Ac e^(-Eac/RT),  t in days.
## Depth (eq. 22), from the surface ageing AP = rise / M:
##   log|G*|(t, z) = log|G*|0 + M ((0.916 z + APmax) / (z + 1)) (1 - e^(-N AP(t))),  z in cm,
##   APmax = (4.5 - log|G*|0) / M,  N = 0.477 e^(-0.226 AP(10 years)).
## Reproduces docs/asphalt_checks/binder_ageing_chain.py.

## NCHRP 871 Table 16, per day. NCHRP 973 Tables 1 and 9 print Af = 1.25e3: a misprint (Model 1).
const AF := 1.25e13            ## /day, fast reaction
const EAF := 95.04             ## kJ/mol
const AC := 3.68e7             ## /day, constant reaction
const EAC := 62.21             ## kJ/mol
const R := 0.008314            ## kJ/(mol K), the gas constant
const KELVIN := 273.15
const MIN_AGEING_C := 20.0     ## hours below this add no measurable ageing (NCHRP 973); skipped
const HOUR_DAYS := 1.0 / 24.0
const SURFACE_LIMIT := 4.5     ## log |G*| the surface heads for (eq. 22, APmax)
const DEEP_FRACTION := 0.916   ## deep down the binder heads for log |G*|0 + 0.916 M (eq. 22)
const N_YEAR := 10             ## N is set by the surface ageing at 10 years (eq. 22)

var log_g0 := 0.0              ## log |G*| of the unaged binder, kPa (eq. 26 from the grade: T2 step 4)
var m := 0.0                   ## M, the binder's ageing susceptibility (eq. 27)
var ap := PackedFloat64Array() ## surface ageing AP at the end of each year; ap[0] = 0, the road as laid
var n := 0.0                   ## N of eq. 22


## Ages the binder (log |G*|0, M) through `years` normal years of `climate` (at least 10, for N).
func _init(climate: SiteClimate, binder_log_g0: float, binder_m: float, years: int) -> void:
	log_g0 = binder_log_g0
	m = binder_m
	ap = surface_ageing(climate, m, maxi(years, N_YEAR))
	n = 0.477 * exp(-0.226 * ap[N_YEAR])


## /day: the fast reaction's rate at `t_k` kelvin (eq. 2).
static func kf(t_k: float) -> float:
	return AF * exp(-EAF / (R * t_k))


## /day: the constant reaction's rate (eq. 3).
static func kc(t_k: float) -> float:
	return AC * exp(-EAC / (R * t_k))


## The rise in log |G*| after `days` at a steady `t_k` (eq. 1).
static func rise(days: float, t_k: float, binder_m: float) -> float:
	var f := kf(t_k)
	var c := kc(t_k)
	return binder_m * ((1.0 - c / f) * (1.0 - exp(-f * days)) + c * days)


## Days at `t_k` that give `rise_now`: the equivalent time that carries the state from one temperature to the
## next. Newton from below; rise is increasing and concave, so each step stays below the root.
static func equivalent_days(rise_now: float, t_k: float, binder_m: float) -> float:
	if rise_now <= 0.0:
		return 0.0
	var f := kf(t_k)
	var c := kc(t_k)
	var a := rise_now / binder_m
	# Both lines lie above the curve, so where they reach `a` is below the root: the tangent at 0, the asymptote.
	var t := maxf(a / f, (a - (1.0 - c / f)) / c)
	for i in 50:
		var g := (1.0 - c / f) * (1.0 - exp(-f * t)) + c * t - a
		var step := -g / ((1.0 - c / f) * f * exp(-f * t) + c)
		t += step
		if absf(step) <= 1e-12 * maxf(t, 1.0):
			break
	return t


## AP at the end of each of `years` normal years of `climate`'s surface temperatures; index 0 is 0.
static func surface_ageing(climate: SiteClimate, binder_m: float, years: int) -> PackedFloat64Array:
	var warm := PackedFloat64Array()   # the year's hours that age the binder, in kelvin, in order
	for t in PavementTemperature.year(climate, 0.0):
		if t >= MIN_AGEING_C:
			warm.append(t + KELVIN)
	var out := PackedFloat64Array()
	out.resize(years + 1)
	var x := 0.0
	for y in years:
		for t_k in warm:
			x = rise(equivalent_days(x, t_k, binder_m) + HOUR_DAYS, t_k, binder_m)
		out[y + 1] = x / binder_m
	return out


## Surface ageing AP after `year` years (straight line between year ends).
func ageing(year: float) -> float:
	var y := clampf(year, 0.0, ap.size() - 1.0)
	var i := mini(int(y), ap.size() - 2)
	return lerpf(ap[i], ap[i + 1], y - i)


## 0 to 1: the surface ageing p = 1 - e^(-N AP), how far the surface is along its way to log |G*| = 4.5.
func surface_progress(year: float) -> float:
	return 1.0 - exp(-n * ageing(year))


## log |G*| (kPa, 64 C, 10 rad/s) at `depth_m` below the surface after `year` years (eq. 22).
func log_g(depth_m: float, year: float) -> float:
	var z := depth_m * 100.0
	var ap_max := (SURFACE_LIMIT - log_g0) / m
	return log_g0 + m * ((DEEP_FRACTION * z + ap_max) / (z + 1.0)) * surface_progress(year)
