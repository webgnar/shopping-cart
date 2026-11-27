class_name SiteClimate
extends Resource
## The climate of a road's site, as a small table: the 12 monthly normals of the mean daily high and low air
## temperature, and the latitude. Kept in degrees F exactly as NOAA publishes them (1991-2020 normals,
## www.ncei.noaa.gov, normals-monthly, MLY-TMAX-NORMAL and MLY-TMIN-NORMAL); the functions give degrees C.
## Feeds PavementTemperature (T2 binder ageing; later T3). Presets: assets/asphalt/climates/.

@export var title := ""
@export_multiline var source := ""
@export var latitude := 0.0                     ## degrees north
@export var air_high_f := PackedFloat64Array()  ## 12 monthly normals of the daily high, January first, deg F
@export var air_low_f := PackedFloat64Array()   ## 12 monthly normals of the daily low, January first, deg F

const MONTH_DAYS := 30.4                        ## the year as 12 equal months (365 / 12, rounded)
const FIRST_MID := 15.2                         ## day of the year at the middle of January (day 0 = Jan 1)


static func f_to_c(f: float) -> float:
	return (f - 32.0) / 1.8


## deg C: the normal daily high air temperature on day `day` (0-364), straight-line between month middles.
func air_high(day: float) -> float:
	return f_to_c(_between(air_high_f, day))


## deg C: the normal daily low air temperature on day `day` (0-364).
func air_low(day: float) -> float:
	return f_to_c(_between(air_low_f, day))


## Each monthly normal stands at the middle of its month; days between are a straight line, December to January
## across the new year. (Matches docs/asphalt_checks/binder_ageing_chain.py.)
func _between(months: PackedFloat64Array, day: float) -> float:
	var d := day if day >= FIRST_MID else day + 365.0
	var m := clampi(int(floor((d - FIRST_MID) / MONTH_DAYS)), 0, 11)
	var f := clampf((d - (FIRST_MID + MONTH_DAYS * m)) / MONTH_DAYS, 0.0, 1.0)
	return lerpf(months[m], months[(m + 1) % 12], f)
