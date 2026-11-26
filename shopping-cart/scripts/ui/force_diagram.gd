class_name ForceDiagram
extends Control
## Live diagram of the forces on the cart (scenes/ui/hud.tscn, the HANDLE FORCES sign). F cycles the view (hud.gd).
## It draws the cart's force ledger (cart.gd `ledger`: every force the script put on the cart in the last physics
## step, where it acted), plus the weight and the wheel loads that balance it.
## Side view: the cart model's own side silhouette (tools/cart_diagram_render.py), tipped as the cart is, on the
## ground; its weight at the centre of mass; the load each pair of wheels carries; the player's shoulders (lowered
## as the trunk leans) and the arm to the handle; and every ledger force on the frame, summed by name, where it acts.
## Rolling resistance (a torque about each axle) is shown as the drag it makes at the ground.
## Top view: the model from above, nose up; each hand where it holds the bar, the line from its shoulder, the forces
## that hand put on the bar seen from above, and the twist all the ledger forces give the cart about its centre of mass.

enum View { SIDE, TOP, BOTH }

@export var view := View.BOTH
@export var panel_size := Vector2(250, 210)   ## px of each view
@export var side_pixels_per_metre := 120.0
@export var top_pixels_per_metre := 110.0
@export var pixels_per_newton := 0.35      ## arrow length per N of hand force
@export var load_pixels_per_newton := 0.12 ## arrow length per N of wheel load and weight
@export var max_arrow := 80.0              ## px: longer arrows are clipped (the label still gives the force)
@export_group("Model images")
@export var side_texture: Texture2D        ## the model from its right side, nose to the right
@export var side_origin := Vector2(72, 500)   ## px in side_texture of the cart's origin (on the ground under the handle)
@export var top_texture: Texture2D         ## the model from above, nose up
@export var top_origin := Vector2(260, 448)   ## px in top_texture of the cart's origin
@export var texture_pixels_per_metre := 400.0
@export_group("Colours")
@export var push_color := Color(0.0, 0.75, 0.5)
@export var pull_color := Color(0.95, 0.3, 0.15)
@export var lean_color := Color(0.99, 0.8, 0.27)
@export var damp_color := Color(0.65, 0.65, 0.65)
@export var other_color := Color(0.8, 0.55, 1.0)   ## air drag, rest friction, rolling, hauling
@export var weight_color := Color(1, 1, 1)
@export var load_color := Color(0.45, 0.7, 1.0)
@export var cart_color := Color(1, 1, 1, 0.35)
@export var body_color := Color(1, 1, 1, 0.3)
@export var ground_color := Color(1, 1, 1, 0.3)
@export var label_color := Color(1.0, 0.69, 0.0)
@export var label_size := 11

const G := 9.81

var _cart: ShoppingCart


func show_cart(cart: ShoppingCart) -> void:
	_cart = cart
	var views := 2 if view == View.BOTH else 1
	custom_minimum_size = Vector2(panel_size.x * views + 12.0 * (views - 1), panel_size.y)
	queue_redraw()


func _draw() -> void:
	if _cart == null or not is_instance_valid(_cart) or _cart.ledger.is_empty():
		return
	var x := 0.0
	if view != View.TOP:
		_draw_side(Rect2(Vector2(x, 0), panel_size))
		x += panel_size.x + 12.0
	if view != View.SIDE:
		_draw_top(Rect2(Vector2(x, 0), panel_size))


func _draw_side(r: Rect2) -> void:
	var frame := _cart.frame
	var xf := frame.global_transform
	var nose := xf.basis.x
	var fwd := Vector3(nose.x, 0, nose.z).normalized()
	# The real floor under the handle, so a cart in the air shows off the ground (its lowest wheel if no floor is near).
	var ground_y := _cart.floor_height()
	if ground_y == -INF:
		ground_y = INF
		for k in _cart.wheels:
			ground_y = minf(ground_y, _cart.wheels[k].global_position.y - _cart.wheel_radius)
	var base := xf.origin
	var ppm := side_pixels_per_metre
	var ground_px := r.size.y - 26.0
	# World point -> panel: forward to the right, up is up, the ground along the lower edge.
	var to_px := func(p: Vector3) -> Vector2:
		return r.position + Vector2(40.0 + (p - base).dot(fwd) * ppm, ground_px - (p.y - ground_y) * ppm)
	var to_vec := func(f: Vector3, scale: float) -> Vector2:
		return Vector2(f.dot(fwd), -f.y) * scale
	_text(r.position + Vector2(4, 12), "SIDE", label_color)
	draw_line(r.position + Vector2(0, ground_px), r.position + Vector2(r.size.x, ground_px), ground_color, 1.0)
	# The model, tipped by the cart's pitch about its origin.
	if side_texture:
		var pitch := atan2(nose.y, nose.dot(fwd))
		var k := ppm / texture_pixels_per_metre
		draw_set_transform(to_px.call(base), -pitch, Vector2(k, k))
		draw_texture(side_texture, -side_origin, cart_color)
		draw_set_transform(Vector2.ZERO)
	# Weight at the centre of mass, and what each pair of wheels carries back up.
	var mass := _cart.rig_mass()
	for g in _cart.groceries:
		if g.visible and _cart.in_basket(g.global_position):
			mass += g.mass   # only what's in the basket weighs on the cart
	var com: Vector2 = to_px.call(xf * frame.center_of_mass)
	draw_circle(com, 3.0, weight_color)
	_arrow(com, Vector2(0, mass * G * load_pixels_per_newton), weight_color, "%d N" % roundi(mass * G))
	for pair in [["RL", "RR"], ["FL", "FR"]]:
		var at: Vector3 = (_cart.wheels[pair[0]].global_position + _cart.wheels[pair[1]].global_position) / 2.0
		var n: float = _cart.wheel_load[pair[0]] + _cart.wheel_load[pair[1]]
		var foot: Vector2 = to_px.call(at - Vector3(0, _cart.wheel_radius, 0))
		if n > 1.0:
			_arrow(foot + Vector2(0, 14), Vector2(0, -n * load_pixels_per_newton), load_color, "")
		_text(foot + Vector2(-14, 24), "%d" % roundi(n), load_color)
	# The ledger's forces on the frame, summed by name and drawn where they act (their average point).
	var sums := {}
	var roll := 0.0
	for e in _cart.ledger:
		if e.body != frame and not str(e.name).begins_with("rolling"):
			continue
		if e.torque != Vector3.ZERO:
			if str(e.name).begins_with("rolling"):
				roll += e.torque.length() / _cart.wheel_radius
			continue
		var s: Dictionary = sums.get(e.name, {"force": Vector3.ZERO, "point": Vector3.ZERO, "n": 0})
		s.force += e.force
		s.point += e.point
		s.n += 1
		sums[e.name] = s
	# The body, which the arms push from: shoulders behind the bar, lower the more the trunk leans.
	var at := Vector3.ZERO
	for side in ["L", "R"]:
		at += frame.global_transform * Vector3(_cart.hand_position.x, _cart.hand_position.y, (-1.0 if side == "L" else 1.0) * _cart.hand_reach(side))
	var handle: Vector2 = to_px.call(at / 2.0)
	var shoulder: Vector2 = to_px.call((_cart.body_point("L") + _cart.body_point("R")) / 2.0)
	draw_line(shoulder, handle, body_color, 1.5, true)
	draw_circle(shoulder, 4.0, body_color)
	draw_circle(handle, 3.5, weight_color)
	var nudge := 0.0
	for name in sums:
		var s: Dictionary = sums[name]
		var f: Vector3 = s.force
		if f.length() < 1.0:
			continue
		var p: Vector2 = to_px.call(s.point / s.n) + Vector2(nudge, 0)
		_arrow(p, to_vec.call(f, pixels_per_newton), _colour(name), "%s %d N" % [str(name).to_upper(), roundi(f.length())])
		nudge = -nudge + (4.0 if nudge <= 0.0 else -4.0)
	if roll > 0.5:
		_text(r.position + Vector2(r.size.x - 92, 12), "ROLLING %.1f N" % roll, other_color)


func _draw_top(r: Rect2) -> void:
	var ppm := top_pixels_per_metre
	var frame := _cart.frame
	var xf := frame.global_transform
	var nose := xf.basis.x
	var fwd := Vector3(nose.x, 0, nose.z).normalized()
	var right := Vector3(xf.basis.z.x, 0, xf.basis.z.z).normalized()
	# The handle's middle sits low in the panel, nose up; the body is behind it (below).
	var handle := r.position + Vector2(r.size.x / 2.0, r.size.y - 80.0)
	_text(r.position + Vector2(4, 12), "TOP", label_color)
	if top_texture:
		var k := ppm / texture_pixels_per_metre
		draw_set_transform(handle, 0.0, Vector2(k, k))
		draw_texture(top_texture, -top_origin, cart_color)
		draw_set_transform(Vector2.ZERO)
	var com := xf * frame.center_of_mass
	var twist := 0.0
	for e in _cart.ledger:
		if e.body == frame:
			twist += (e.point - com).cross(e.force).y
	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		var hand := handle + Vector2(s * _cart.hand_reach(side) * ppm, 0)
		var shoulder := handle + Vector2(s * _cart.shoulder_half * ppm, _cart.body_gap * ppm)
		draw_line(shoulder, hand, body_color, 1.5, true)
		draw_circle(shoulder, 4.0, body_color)
		draw_circle(hand, 4.0, weight_color)
		for e in _cart.ledger:
			if e.side != side or e.body != frame:
				continue
			var f: Vector3 = e.force
			var v := Vector2(f.dot(right), -f.dot(fwd)) * pixels_per_newton
			if v.length() > 2.0:
				_arrow(hand, v, _colour(e.name), "%d" % roundi(Vector2(f.dot(right), f.dot(fwd)).length()))
		_text(hand + Vector2(-14, 18), "%d CM" % roundi(_cart.hand_reach(side) * 100.0), label_color)
	_text(r.position + Vector2(4, r.size.y - 6), "TWIST %+d N·M %s" % [roundi(twist), "LEFT" if twist > 0.5 else ("RIGHT" if twist < -0.5 else "")], label_color)


func _colour(name: String) -> Color:
	match name:
		"push": return push_color
		"pull": return pull_color
		"lift", "press": return lean_color
		"hold height", "hold line": return damp_color
	return other_color


func _arrow(from: Vector2, v: Vector2, color: Color, label: String) -> void:
	if v.length() > max_arrow:
		v = v.normalized() * max_arrow
	var to := from + v
	draw_line(from, to, color, 2.5, true)
	if v.length() > 6.0:
		var d := v.normalized()
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([to + d * 2.0, to - d * 8.0 + n * 4.5, to - d * 8.0 - n * 4.5]), color)
	if label != "":
		_text(to + Vector2(4, -4 if v.y <= 0.0 else 12), label, color)


func _text(at: Vector2, text: String, color: Color) -> void:
	draw_string(get_theme_font("font", "Label"), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, color)
