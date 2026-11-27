class_name PavementTemperature
extends RefCounted
## Pavement temperature from the site's air temperature (T2 binder ageing; later T3 thermal cracking).
##
## Daily high and low: the LTPP seasonal models of FHWA-RD-97-103 (Mohseni 1998), fitted to 30 LTPP seasonal
## monitoring sites at depths of 25-275 mm. We apply them to each day's normal high and low at the surface
## (depth 0): a stated extrapolation (docs/ASPHALT_SCIENCE.md, Model 1).
## The hours between: coldest at 06:00, hottest at 15:00, half-cosines between. An assumption, labelled as one
## (Pomerantz et al. 2000: the pavement peaks at least an hour after the sun).

const COLDEST_HOUR := 6.0
const HOTTEST_HOUR := 15.0


## deg C: the high pavement temperature, eq. 8: 54.32 + 0.78 Tair - 0.0025 Lat^2 - 15.14 log10(H + 25)
## (R2 76 %, RMSE 3.0 C). Tair: the high air temperature (C); lat: degrees; depth_mm: H, depth below the surface.
static func high(t_air: float, lat: float, depth_mm: float) -> float:
	return 54.32 + 0.78 * t_air - 0.0025 * lat * lat - 15.14 * log(depth_mm + 25.0) / log(10.0)


## deg C: the low pavement temperature, eq. 7: -1.56 + 0.72 Tair - 0.004 Lat^2 + 6.26 log10(H + 25)
## (R2 96 %, RMSE 2.1 C). Tair: the low air temperature (C).
static func low(t_air: float, lat: float, depth_mm: float) -> float:
	return -1.56 + 0.72 * t_air - 0.004 * lat * lat + 6.26 * log(depth_mm + 25.0) / log(10.0)


## 0 at the coldest hour, 1 at the hottest: rising over 06:00-15:00, falling over the 15 hours after.
static func day_shape(hour: float) -> float:
	if hour >= COLDEST_HOUR and hour <= HOTTEST_HOUR:
		return (1.0 - cos(PI * (hour - COLDEST_HOUR) / (HOTTEST_HOUR - COLDEST_HOUR))) * 0.5
	var since := fposmod(hour - HOTTEST_HOUR, 24.0)
	return (1.0 + cos(PI * since / (24.0 - HOTTEST_HOUR + COLDEST_HOUR))) * 0.5


## deg C: the pavement temperature at `depth_mm` on day `day` (0-364) at `hour` (0-23), on a normal year.
static func at(climate: SiteClimate, day: float, hour: float, depth_mm: float) -> float:
	var hi := high(climate.air_high(day), climate.latitude, depth_mm)
	var lo := low(climate.air_low(day), climate.latitude, depth_mm)
	return lo + (hi - lo) * day_shape(hour)


## The 8760 hourly temperatures of a normal year (365 days x 24 h, from Jan 1 00:00), deg C.
static func year(climate: SiteClimate, depth_mm: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(365 * 24)
	for d in 365:
		var hi := high(climate.air_high(d), climate.latitude, depth_mm)
		var lo := low(climate.air_low(d), climate.latitude, depth_mm)
		for h in 24:
			out[d * 24 + h] = lo + (hi - lo) * day_shape(h)
	return out
