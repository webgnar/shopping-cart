class_name TelemetryGraph
extends Control
## Graphs of the cart over the last `history` seconds (scenes/ui/hud.tscn, the GRAPHS sign; G toggles it, hud.gd).
## Sampled every physics step while the sign is up, from what cart.gd exposes (read only):
##  - SPEED km/h along the nose (+ forward, - backward)
##  - ACCEL m/s² along the nose, from the change in that speed (a short running average, as one step is noisy)
##  - HANDS N: each hand's push (+) or pull (-) along the nose at the bar (handle_forces[side].arm)
##  - WHEELS N: what the ground pushes up on each wheel (wheel_load)
##  - CASTERS °: each front fork's swivel against the frame, 0 trailing straight back (rolling forward),
##    ±180 trailing forward (rolling backward)
## Each strip's range is its `*_range` export, widened while a value in the window goes past it; the latest value
## of each line is printed on the right.

@export var history := 5.0               ## s of history shown
@export var strip_size := Vector2(400, 54)
@export var strip_gap := 6.0
@export var accel_smoothing := 0.05      ## s the acceleration is averaged over
@export var speed_range := Vector2(-5, 25)      ## km/h shown at the bottom and top of the strip
@export var accel_range := Vector2(-4, 8)       ## m/s²
@export var hand_range := Vector2(-60, 120)     ## N
@export var wheel_range := Vector2(0, 150)      ## N
@export var caster_range := Vector2(-180, 180)  ## degrees
@export_group("Colours")
@export var line_color := Color(1, 1, 1)
@export var left_color := Color(0.35, 0.75, 1.0)
@export var right_color := Color(1.0, 0.69, 0.0)
@export var wheel_colors: PackedColorArray = [Color(0.35, 0.75, 1.0), Color(1.0, 0.69, 0.0), Color(0.6, 0.9, 0.4), Color(0.95, 0.4, 0.35)]
@export var grid_color := Color(1, 1, 1, 0.15)
@export var zero_color := Color(1, 1, 1, 0.4)
@export var label_color := Color(1.0, 0.69, 0.0)
@export var label_size := 10

const WHEELS := ["FL", "FR", "RL", "RR"]
const LEFT_PAD := 58.0    ## px for the strip's name
const RIGHT_PAD := 108.0   ## px for the latest values

var _cart: ShoppingCart
## One row per physics step: [speed, accel, hand L, hand R, FL, FR, RL, RR, caster FL, caster FR].
var _rows: Array[PackedFloat32Array] = []
var _head := 0          ## where the next row goes in the ring
var _count := 0
var _speed_hist := PackedFloat32Array()   ## the last few speeds, for the averaged acceleration


## Called every frame by the HUD while the sign is up.
func show_cart(cart: ShoppingCart) -> void:
	if cart != _cart:
		_cart = cart
		clear()
	custom_minimum_size = Vector2(strip_size.x, 5 * strip_size.y + 4 * strip_gap)
	queue_redraw()


func clear() -> void:
	_rows.clear()
	_head = 0
	_count = 0
	_speed_hist.clear()


func _physics_process(delta: float) -> void:
	if not is_visible_in_tree() or _cart == null or not is_instance_valid(_cart) or _cart.frame == null:
		return
	var n := maxi(2, roundi(history / delta))
	if _rows.size() != n:
		_rows.resize(n)
		_head = 0
		_count = 0
	var xf := _cart.frame.global_transform
	var fwd := Vector3(xf.basis.x.x, 0, xf.basis.x.z).normalized()
	var speed := _cart.frame_velocity().dot(fwd)
	# Acceleration: the speed's change across the averaging window.
	var window := maxi(1, roundi(accel_smoothing / delta))
	_speed_hist.append(speed)
	if _speed_hist.size() > window + 1:
		_speed_hist.remove_at(0)
	var accel := (_speed_hist[-1] - _speed_hist[0]) / (delta * maxf(1.0, _speed_hist.size() - 1))
	var row := PackedFloat32Array()
	row.resize(10)
	row[0] = speed * 3.6
	row[1] = accel
	for i in 2:
		var side: String = ["L", "R"][i]
		row[2 + i] = (_cart.handle_forces[side].arm as Vector3).dot(fwd) if _cart.handle_forces.has(side) else 0.0
	for i in 4:
		row[4 + i] = _cart.wheel_load[WHEELS[i]]
	for i in 2:
		var fork: RigidBody3D = _cart.forks[["FL", "FR"][i]]
		var local := xf.basis.inverse() * fork.global_transform.basis.x
		row[8 + i] = rad_to_deg(atan2(-local.z, local.x))
	_rows[_head] = row
	_head = (_head + 1) % n
	_count = mini(_count + 1, n)


func _draw() -> void:
	# [name, unit, range, columns, each line's name, colours, value format]
	var strips := [
		["SPEED", "KM/H", speed_range, [0], [""], [line_color], "%.1f"],
		["ACCEL", "M/S²", accel_range, [1], [""], [line_color], "%+.1f"],
		["HANDS", "N", hand_range, [2, 3], ["L", "R"], [left_color, right_color], "%+d"],
		["WHEELS", "N", wheel_range, [4, 5, 6, 7], WHEELS, wheel_colors, "%d"],
		["CASTERS", "DEG", caster_range, [8, 9], ["FL", "FR"], [left_color, right_color], "%+d"],
	]
	var y := 0.0
	for s in strips:
		_draw_strip(Rect2(0, y, strip_size.x, strip_size.y), s[0], s[1], s[2], s[3], s[4], s[5], s[6])
		y += strip_size.y + strip_gap


func _draw_strip(r: Rect2, title: String, unit: String, base: Vector2, cols: Array, names: Array, colors: Array,
		fmt: String) -> void:
	var plot := Rect2(r.position + Vector2(LEFT_PAD, 0), Vector2(r.size.x - LEFT_PAD - RIGHT_PAD, r.size.y))
	# The strip's range, widened to fit what's in the window.
	var lo := base.x
	var hi := base.y
	for k in _count:
		for c in cols:
			var v: float = _rows[k][c]
			lo = minf(lo, v)
			hi = maxf(hi, v)
	var to_y := func(v: float) -> float:
		return plot.end.y - (v - lo) / maxf(hi - lo, 0.001) * plot.size.y
	draw_rect(plot, grid_color, false, 1.0)
	for k in range(1, int(history)):
		var gx := plot.position.x + plot.size.x * k / history
		draw_line(Vector2(gx, plot.position.y), Vector2(gx, plot.end.y), grid_color, 1.0)
	if lo < 0.0 and hi > 0.0:
		var zy: float = to_y.call(0.0)
		draw_line(Vector2(plot.position.x, zy), Vector2(plot.end.x, zy), zero_color, 1.0)
	_text(r.position + Vector2(0, 12), title, label_color)
	_text(r.position + Vector2(0, 24), unit, Color(label_color, 0.7), label_size - 2)
	_text(plot.position + Vector2(3, 9), _num(hi), Color(1, 1, 1, 0.5), label_size - 2)
	_text(Vector2(plot.position.x + 3, plot.end.y - 2), _num(lo), Color(1, 1, 1, 0.5), label_size - 2)
	if _count < 2:
		return
	var n := _rows.size()
	var step := maxi(1, _count / int(plot.size.x))   # about one point per pixel
	for ci in cols.size():
		var c: int = cols[ci]
		var pts := PackedVector2Array()
		var k := 0
		while k < _count:
			var row: PackedFloat32Array = _rows[(_head - _count + k + n) % n]
			var age := float(_count - 1 - k) / n * history
			pts.append(Vector2(plot.end.x - age / history * plot.size.x, to_y.call(row[c])))
			k += step
		var last: PackedFloat32Array = _rows[(_head - 1 + n) % n]
		pts.append(Vector2(plot.end.x, to_y.call(last[c])))
		draw_polyline(pts, colors[ci], 1.5, true)
		var v := last[c]
		var txt := ("%s " % names[ci] if names[ci] else "") + fmt % (roundi(v) if fmt.contains("d") else v)
		_text(Vector2(plot.end.x + 6 + (ci % 2) * 52, r.position.y + 12 + (ci / 2) * 13), txt, colors[ci])


func _num(v: float) -> String:
	return "%d" % roundi(v) if absf(v) >= 10.0 or is_equal_approx(v, roundf(v)) else "%.1f" % v


func _text(at: Vector2, text: String, color: Color, size := -1) -> void:
	draw_string(get_theme_font("font", "Label"), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size if size > 0 else label_size, color)
