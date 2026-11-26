class_name CurveView
extends Control
## One editable Curve on the CURVES sign (scenes/ui/hud.tscn, curve_panel.gd). It draws the curve over its domain
## and value range, a marker per hand where the cart is working on it right now (`operating`), and lets you edit
## the curve in place: drag a point, double-click to add one, right-click a point to remove it. The Curve resource
## is the one the cart uses, so an edit takes effect on the next physics step; CurvePanel saves it back to its .tres.

signal edited   ## the curve was changed with the mouse

@export var title := ""
@export var x_label := ""
@export var y_label := ""
## The cart export holding this curve (cart.get(cart_property)), e.g. "force_speed_curve".
@export var cart_property := ""
## The key of this curve's input in the cart's curve_inputs[side], e.g. "hand_speed".
@export var input_key := ""
@export var plot_margin := Vector2(34, 16)   ## px left of and below the plot for the axis numbers
@export var point_radius := 4.0
@export var pick_radius := 8.0               ## px: how near a point a click has to be to grab it
@export_group("Colours")
@export var curve_color := Color(1, 1, 1)
@export var point_color := Color(1.0, 0.69, 0.0)
@export var left_color := Color(0.35, 0.75, 1.0)
@export var right_color := Color(1.0, 0.69, 0.0)
@export var grid_color := Color(1, 1, 1, 0.15)
@export var label_color := Color(1.0, 0.69, 0.0)
@export var label_size := 10

var curve: Curve:
	set(c):
		if curve == c:
			return
		curve = c
		queue_redraw()
## Where each hand works on the curve: {"L": x, "R": x}. Missing sides aren't drawn.
var operating := {}
## Shown in place of the curve when there's none to edit.
var missing_text := ""
var _drag := -1   ## index of the point being dragged


func plot_rect() -> Rect2:
	return Rect2(Vector2(plot_margin.x, 14), size - Vector2(plot_margin.x + 6, plot_margin.y + 14))


func to_screen(p: Vector2) -> Vector2:
	var r := plot_rect()
	var t := Vector2(inverse_lerp(curve.min_domain, curve.max_domain, p.x), inverse_lerp(curve.min_value, curve.max_value, p.y))
	return Vector2(r.position.x + t.x * r.size.x, r.end.y - t.y * r.size.y)


func to_curve(s: Vector2) -> Vector2:
	var r := plot_rect()
	var t := Vector2((s.x - r.position.x) / r.size.x, (r.end.y - s.y) / r.size.y)
	return Vector2(lerpf(curve.min_domain, curve.max_domain, clampf(t.x, 0, 1)),
		lerpf(curve.min_value, curve.max_value, clampf(t.y, 0, 1)))


func _point_at(s: Vector2) -> int:
	for i in curve.point_count:
		if to_screen(curve.get_point_position(i)).distance_to(s) <= pick_radius:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if curve == null:
		return
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_LEFT and e.pressed and e.double_click:
			if _point_at(e.position) < 0 and plot_rect().has_point(e.position):
				_drag = curve.add_point(to_curve(e.position), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
				edited.emit()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_drag = _point_at(e.position) if e.pressed else -1
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			var i := _point_at(e.position)
			if i >= 0 and curve.point_count > 2:
				curve.remove_point(i)
				edited.emit()
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion and _drag >= 0:
		var p := to_curve(event.position)
		# The end points keep the domain covered: they only move up and down.
		if _drag > 0 and _drag < curve.point_count - 1:
			var lo := curve.get_point_position(_drag - 1).x + 0.001
			var hi := curve.get_point_position(_drag + 1).x - 0.001
			_drag = curve.set_point_offset(_drag, clampf(p.x, lo, hi))
		curve.set_point_value(_drag, p.y)
		edited.emit()
		accept_event()
		queue_redraw()


func _draw() -> void:
	var r := plot_rect()
	_text(Vector2(0, 10), title, label_color)
	draw_rect(r, grid_color, false, 1.0)
	if curve == null:
		_text(r.position + Vector2(6, r.size.y / 2.0), missing_text, Color(1, 1, 1, 0.6))
		var y := r.position.y + r.size.y / 2.0 + 14.0
		for side in operating:
			_text(Vector2(r.position.x + 6, y), "%s  %s %.2f" % [side, x_label, operating[side]], left_color if side == "L" else right_color)
			y += 13.0
		return
	for k in range(1, 4):
		var gx := r.position.x + r.size.x * k / 4.0
		var gy := r.position.y + r.size.y * k / 4.0
		draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), grid_color)
		draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), grid_color)
	_text(Vector2(2, r.position.y + 8), _num(curve.max_value), Color(1, 1, 1, 0.6), label_size - 2)
	_text(Vector2(2, r.end.y), _num(curve.min_value), Color(1, 1, 1, 0.6), label_size - 2)
	_text(Vector2(r.position.x, r.end.y + 12), _num(curve.min_domain), Color(1, 1, 1, 0.6), label_size - 2)
	_text(Vector2(r.end.x - 22, r.end.y + 12), _num(curve.max_domain), Color(1, 1, 1, 0.6), label_size - 2)
	_text(Vector2(r.position.x + r.size.x / 2.0 - 30, r.end.y + 12), x_label, Color(label_color, 0.8), label_size - 2)
	_text(Vector2(r.position.x + 4, r.position.y + 10), y_label, Color(label_color, 0.8), label_size - 2)
	var pts := PackedVector2Array()
	var steps := maxi(2, int(r.size.x / 2.0))
	for k in steps + 1:
		var x := lerpf(curve.min_domain, curve.max_domain, float(k) / steps)
		pts.append(to_screen(Vector2(x, curve.sample(x))))
	draw_polyline(pts, curve_color, 1.5, true)
	for i in curve.point_count:
		var s := to_screen(curve.get_point_position(i))
		draw_rect(Rect2(s - Vector2.ONE * point_radius, Vector2.ONE * point_radius * 2.0), point_color if i != _drag else Color(1, 1, 1))
	# Where each hand is on the curve now.
	var row := 0
	for side in operating:
		var x: float = operating[side]
		var y := curve.sample(clampf(x, curve.min_domain, curve.max_domain))
		var col := left_color if side == "L" else right_color
		var s := to_screen(Vector2(clampf(x, curve.min_domain, curve.max_domain), y))
		draw_dashed_line(Vector2(s.x, r.end.y), s, Color(col, 0.6), 1.0, 3.0)
		draw_circle(s, 4.0, col)
		_text(Vector2(r.end.x - 118, r.position.y + 10 + row * 12), "%s  %.2f → %.2f" % [side, x, y], col, label_size - 1)
		row += 1


func _num(v: float) -> String:
	return "%d" % roundi(v) if is_equal_approx(v, roundf(v)) else "%.2f" % v


func _text(at: Vector2, text: String, color: Color, size := -1) -> void:
	draw_string(get_theme_font("font", "Label"), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size if size > 0 else label_size, color)
