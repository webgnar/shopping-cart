extends Node3D
## Prototype sandbox: slippery store floor with shelves on +X, grippy parking lot with ramp, curb and
## speed bumps on -X. Q/A = left hand push/pull, E/D = right hand push/pull, W lift, S press, R reset.
## The mouse only moves the camera (click to capture, Esc to release, wheel to zoom).


const KEYS := {
	"push_left": KEY_Q, "pull_left": KEY_A,
	"push_right": KEY_E, "pull_right": KEY_D,
	"lift": KEY_W, "press": KEY_S, "reset": KEY_R,
	"gear_1": KEY_1, "gear_2": KEY_2, "gear_3": KEY_3, "gear_4": KEY_4, "gear_5": KEY_5,
	"fullscreen": KEY_F11,
}

var cart: ShoppingCart
var gear := 3   ## push gear, kept across resets
var camera: Camera3D
var cam_yaw := 0.0
var cam_pitch := 0.38
var cam_dist := 3.2
var cam_heading := 0.0
var cam_target := Vector3.ZERO

var tile_mat := PhysicsMaterial.new()
var asphalt_mat := PhysicsMaterial.new()
var solid_mat := PhysicsMaterial.new()

var _hud := {}


func _ready() -> void:
	_setup_input()
	tile_mat.friction = 0.18
	asphalt_mat.friction = 0.9
	solid_mat.friction = 0.5
	_build_environment()
	_build_level()
	spawn_cart(Vector3(2, 0, 0), 0.0)
	camera = Camera3D.new()
	camera.fov = 55
	camera.near = 0.05
	add_child(camera)
	camera.current = true
	_build_hud()


func _setup_input() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, ev)


## Removes the current cart (and its groceries) and builds a fresh one at `at`, facing `yaw`.
func spawn_cart(at: Vector3, yaw: float) -> void:
	if cart:
		remove_child(cart)
		cart.free()
	cart = ShoppingCart.new()
	cart.name = "Cart"
	cart.gear = gear
	cart.transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 0.005, 0))
	add_child(cart)
	cam_heading = yaw
	cam_target = at + Vector3(0, 0.67, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var up: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
			if event.ctrl_pressed:   # Ctrl + scroll zooms the camera
				cam_dist = maxf(1.4, cam_dist * 0.9) if up else minf(9.0, cam_dist * 1.1)
			else:                    # scroll shifts the push gear
				gear = cart.set_gear(gear + (1 if up else -1))
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * 0.004
		cam_pitch = clampf(cam_pitch + event.relative.y * 0.003, 0.05, 1.3)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("fullscreen"):
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
		gear = cart.set_gear(event.physical_keycode - KEY_0)
	elif event.is_action_pressed("reset"):
		var p := cart.cart_origin()
		spawn_cart(Vector3(p.x, 0.05, p.z), cart.heading())


func _process(delta: float) -> void:
	# Camera trails behind the handle; the mouse orbits on top of that.
	var dh := wrapf(cart.heading() - cam_heading, -PI, PI)
	cam_heading += dh * minf(1.0, 3.0 * delta)
	var com := cart.frame.global_transform * ShoppingCart.COM
	cam_target = cam_target.lerp(com + Vector3(0, 0.25, 0), minf(1.0, 9.0 * delta))
	var yaw := cam_heading + PI + cam_yaw
	camera.global_position = cam_target + Vector3(cos(yaw) * cos(cam_pitch), sin(cam_pitch), -sin(yaw) * cos(cam_pitch)) * cam_dist
	camera.look_at(cam_target)
	_update_hud()


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("1c2230")
	sky_mat.sky_horizon_color = Color("4a5568")
	sky_mat.ground_horizon_color = Color("4a5568")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30
	add_child(sun)


func _static_box(size: Vector3, pos: Vector3, mat: PhysicsMaterial, color: Color, rot_z := 0.0, roughness := 0.85) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = ShoppingCart.LAYER_WORLD
	b.physics_material_override = mat
	b.position = pos
	b.rotation.z = rot_z
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	mesh.material = m
	mi.mesh = mesh
	b.add_child(mi)
	add_child(b)


func _build_level() -> void:
	# Store floor (slippery polished tile) on +X, parking lot (asphalt) on -X; both top out at y = 0.
	_static_box(Vector3(30, 1, 40), Vector3(15, -0.5, 0), tile_mat, Color("aeb5bf"), 0.0, 0.2)
	_static_box(Vector3(30, 1, 40), Vector3(-15, -0.5, 0), asphalt_mat, Color("3b3f46"))
	for i in range(-3, 4):   # parking bay lines
		var line := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(5, 0.1)
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color("e8e2c8")
		pm.material = lm
		line.mesh = pm
		line.position = Vector3(-10, 0.002, i * 2.8)
		add_child(line)
	for z in [-6.0, -2.2, 1.6, 5.4]:   # store shelves
		_static_box(Vector3(10, 1.8, 0.6), Vector3(12, 0.9, z), solid_mat, Color("7d8796"))
	_static_box(Vector3(0.4, 2.4, 40), Vector3(29.8, 1.2, 0), solid_mat, Color("9aa3b0"))     # back wall
	_static_box(Vector3(3.2, 0.2, 2.4), Vector3(-6, 0.16, -7), asphalt_mat, Color("5b616b"), 0.12)  # ramp
	_static_box(Vector3(2, 0.36, 2.4), Vector3(-8.55, 0.18, -7), asphalt_mat, Color("5b616b"))      # ramp top
	_static_box(Vector3(0.3, 0.12, 12), Vector3(-3.2, 0.06, 6), asphalt_mat, Color("9ea3a8"))       # curb
	for x in [-12.0, -15.0]:   # speed bumps
		_static_box(Vector3(0.35, 0.05, 6), Vector3(x, 0.025, 4), asphalt_mat, Color("d8b23a"))
	# Boxes to knock over
	for i in 6:
		var s := 0.35
		var b := RigidBody3D.new()
		b.mass = 2.0
		b.collision_layer = ShoppingCart.LAYER_WORLD
		b.collision_mask = ShoppingCart.LAYER_WORLD | ShoppingCart.LAYER_CART | ShoppingCart.LAYER_CARGO
		b.position = Vector3(5.5, s / 2 + (i % 3) * s, -1.2 + floorf(i / 3.0) * 0.4)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE * s
		cs.shape = shape
		b.add_child(cs)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * s
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("b8875a")
		mesh.material = m
		mi.mesh = mesh
		b.add_child(mi)
		add_child(b)


# ---------------------------------------------------------------- HUD

const CAPS := [
	["Q", "push_left", "LEFT PUSH", "push"], ["W", "lift", "LIFT", "lift"], ["E", "push_right", "RIGHT PUSH", "push"],
	["A", "pull_left", "LEFT PULL", "pull"], ["S", "press", "PRESS", "lift"], ["D", "pull_right", "RIGHT PULL", "pull"],
]
const COLORS := {"push": Color("3ddc84"), "pull": Color("ff6b6b"), "lift": Color("5aa9ff")}


func _cap_style(bg: Color, border: Color, bottom: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_bottom = bottom
	sb.set_corner_radius_all(9)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := Label.new()
	title.text = "SHOPPING CART  ·  Godot prototype\nTwo hands on the handlebar. The physics does the steering."
	title.position = Vector2(16, 12)
	title.add_theme_font_size_override("font_size", 16)
	layer.add_child(title)

	var stats := Label.new()
	stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)   # stays pinned to the top-right corner at any window size
	stats.offset_left = -260
	stats.offset_right = -16
	stats.offset_top = 12
	stats.offset_bottom = 112
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(stats)
	_hud.stats = stats

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)  # stays pinned to the bottom-left corner
	panel.offset_left = 16
	panel.offset_bottom = -16
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	var psb := _cap_style(Color(0.07, 0.08, 0.11, 0.85), Color("2e3542"), 1)
	psb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", psb)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	# Push meter: five segments, the current gear and its force.
	var meter_box := VBoxContainer.new()
	meter_box.add_theme_constant_override("separation", 4)
	vb.add_child(meter_box)
	var meter_label := Label.new()
	meter_label.add_theme_font_size_override("font_size", 13)
	meter_box.add_child(meter_label)
	var segs := HBoxContainer.new()
	segs.add_theme_constant_override("separation", 4)
	meter_box.add_child(segs)
	_hud.meter_label = meter_label
	_hud.segs = []
	for i in 5:
		var seg := Panel.new()
		seg.custom_minimum_size = Vector2(48, 10 + i * 3)
		seg.size_flags_vertical = Control.SIZE_SHRINK_END
		segs.add_child(seg)
		_hud.segs.append(seg)
	_hud.seg_off = _cap_style(Color("262c38"), Color("4a5263"), 1)
	_hud.seg_on = []
	for i in 5:
		var c := Color("3ddc84").lerp(Color("ffb02e"), i / 4.0)
		_hud.seg_on.append(_cap_style(c, c, 1))
	var meter_hint := Label.new()
	meter_hint.text = "scroll or 1-5 to change push strength"
	meter_hint.add_theme_font_size_override("font_size", 11)
	meter_hint.modulate = Color(1, 1, 1, 0.6)
	meter_box.add_child(meter_hint)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	_hud.caps = []
	var idle := _cap_style(Color("262c38"), Color("4a5263"), 4)
	for c in CAPS:
		var cap := PanelContainer.new()
		cap.custom_minimum_size = Vector2(80, 64)
		cap.add_theme_stylebox_override("panel", idle)
		var cvb := VBoxContainer.new()
		cvb.alignment = BoxContainer.ALIGNMENT_CENTER
		cvb.add_theme_constant_override("separation", 0)
		var letter := Label.new()
		letter.text = c[0]
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", 24)
		var lab := Label.new()
		lab.text = c[2]
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 10)
		cvb.add_child(letter)
		cvb.add_child(lab)
		cap.add_child(cvb)
		grid.add_child(cap)
		var col: Color = COLORS[c[3]]
		_hud.caps.append({"action": c[1], "node": cap, "labels": [letter, lab], "idle": idle,
			"on": _cap_style(col, col, 1)})

	var hands := Label.new()
	hands.add_theme_font_size_override("font_size", 13)
	vb.add_child(hands)
	_hud.hands = hands
	var hint := Label.new()
	hint.text = "R reset  ·  F11 full screen  ·  click to look, Esc to release, Ctrl+scroll zoom"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(hint)


func _update_hud() -> void:
	for c in _hud.caps:
		var on := Input.is_action_pressed(c.action)
		c.node.add_theme_stylebox_override("panel", c.on if on else c.idle)
		for l in c.labels:
			l.add_theme_color_override("font_color", Color("12151b") if on else Color("eceef2"))
	var v := cart.frame.linear_velocity
	_hud.stats.text = "Speed  %.1f km/h\nTurn rate  %d°/s\nWheels down  %d / 4\nGroceries  %d / %d" % [
		Vector2(v.x, v.z).length() * 3.6, roundi(rad_to_deg(cart.frame.angular_velocity.y)),
		cart.wheels_down(), cart.groceries_in_basket(), cart.groceries.size()]
	_hud.meter_label.text = "PUSH  gear %d / %d   ·   %d N per hand   ·   up to %.0f km/h" % [
		cart.gear, cart.gears.size(), roundi(cart.push_force), cart.walk_max * 3.6]
	for i in _hud.segs.size():
		_hud.segs[i].add_theme_stylebox_override("panel", _hud.seg_on[i] if i < cart.gear else _hud.seg_off)
	var hs := cart.hand_state
	_hud.hands.text = "Left hand: %s\nRight hand: %s" % [hs.L if hs.L else "—", hs.R if hs.R else "—"]
