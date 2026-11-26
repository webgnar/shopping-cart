class_name CurvePanel
extends PanelContainer
## The CURVES sign (scenes/ui/hud.tscn; C opens it, hud.gd): the cart's relationship curves, each a CurveView,
## drawn live with where each hand is working on it and editable in game. Save writes every edited curve back to
## its .tres; Revert reloads them from disk (in place, so the cart picks the old curve back up at once).
##
## Each CurveView names the cart export that holds its Curve (cart_property) and the key of its input in the cart's
## curve_inputs[side] (input_key). The cart reads the same Curve resource every step, so an edit takes effect on
## the next physics step without restarting.
##
## Until cart.gd has those exports and curve_inputs, each view says so and shows its input worked out from what
## the cart already exposes (`_fallback_input`).

@export var save_button: Button
@export var revert_button: Button
@export var status_label: Label

var _views: Array[CurveView] = []
var _dirty := {}   ## Curve -> true for curves edited since the last save or revert


func _ready() -> void:
	for v in find_children("*", "CurveView", true, false):
		_views.append(v)
		v.edited.connect(_on_edited.bind(v))
	if save_button:
		save_button.pressed.connect(save)
	if revert_button:
		revert_button.pressed.connect(revert)
	_update_status()


func views() -> Array[CurveView]:
	return _views


## Called every frame by the HUD while the sign is open.
func show_cart(cart: ShoppingCart) -> void:
	var has_inputs := "curve_inputs" in cart
	for v in _views:
		if v.cart_property in cart:
			v.curve = cart.get(v.cart_property)
			v.missing_text = "" if v.curve else "cart.%s is empty" % v.cart_property
		elif v.curve == null:
			v.missing_text = "cart.gd has no %s yet" % v.cart_property
		var op := {}
		for side in ["L", "R"]:
			if has_inputs and cart.curve_inputs.has(side) and cart.curve_inputs[side].has(v.input_key):
				op[side] = cart.curve_inputs[side][v.input_key]
			else:
				op[side] = _fallback_input(cart, side, v.input_key)
		v.operating = op
		v.queue_redraw()


## Interim inputs from what the cart exposes today, until it publishes curve_inputs.
func _fallback_input(cart: ShoppingCart, side: String, key: String) -> float:
	match key:
		"hand_speed":   # m/s the hand moves along the nose (forward +)
			if not cart.handle_forces.has(side):
				return 0.0
			var f := cart.frame
			var fwd := Vector3(f.global_transform.basis.x.x, 0, f.global_transform.basis.x.z).normalized()
			var r: Vector3 = cart.handle_forces[side].point - f.global_transform * f.center_of_mass
			return (f.linear_velocity + f.angular_velocity.cross(r)).dot(fwd)
		"handle_height":   # m from the floor to where the hand holds the bar
			var floor_y := cart.floor_height()
			if not cart.handle_forces.has(side) or floor_y == -INF:
				return 0.0
			return cart.handle_forces[side].point.y - floor_y
		"fatigue":   # 0 fresh to 1 spent
			return cart.hand_fatigue[side]
	return 0.0


## Writes every edited curve back to its .tres. Returns how many were saved.
func save() -> int:
	var n := 0
	for c in _dirty.keys():
		var path: String = (c as Curve).resource_path
		if path.ends_with(".tres") and ResourceSaver.save(c, path) == OK:
			_dirty.erase(c)
			n += 1
	_update_status("SAVED %d" % n if n else "")
	return n


## Reloads every edited curve from its .tres, in place.
func revert() -> void:
	for c in _dirty.keys():
		var path: String = (c as Curve).resource_path
		if path != "" and ResourceLoader.exists(path):
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	_dirty.clear()
	for v in _views:
		v.queue_redraw()
	_update_status("REVERTED")


func _on_edited(v: CurveView) -> void:
	_dirty[v.curve] = true
	_update_status()


func _update_status(note := "") -> void:
	if status_label == null:
		return
	if note != "":
		status_label.text = note
	elif _dirty.is_empty():
		status_label.text = "DRAG A POINT · DOUBLE-CLICK ADDS · RIGHT-CLICK REMOVES"
	else:
		status_label.text = "%d UNSAVED" % _dirty.size()
