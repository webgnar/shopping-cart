class_name MobileLevelExport
extends RefCounted
## Copies the Godot levels and cart rig to the mobile web game (mobile/), so the phone version plays the same
## levels with the same cart. The Godot scenes stay the source of truth; nothing in the Godot game reads the output.
##
## For each fast-travel destination of the console (scenes/ui/console.tscn, `destinations`) it loads the level as
## the game would (props run their _ready, so painted cars and labelled cases look right), then writes:
##  - mobile/levels/<key>.glb: what you see (meshes and materials). Loose props are named dyn_<n> so the phone
##    can move them with their physics body.
##  - mobile/levels/<key>.json: what you touch and how it's lit: every collision shape with its friction, the
##    loose props (mass, shapes), CartSpawn, the spare carts, sky/fog/ambient, the sun, lamps and 3D labels.
## And once for the cart (scenes/cart/cart.tscn): mobile/levels/cart.json with the rig (bodies, masses, shapes,
## hinges and their limits) and the cart's shared materials (assets/materials/cart/*.tres).
##
## Run headless from shopping-cart/:  godot --headless -s res://tools/export_mobile_levels_cli.gd
## tests/mobile_levels_sync_test.gd fails when a level or the cart changed since the last export.

const CONSOLE_SCENE := "res://scenes/ui/console.tscn"
const CART_SCENE := "res://scenes/cart/cart.tscn"
const SPARE_CART_SCENE := "res://scenes/cart/spare_cart.tscn"
const CART_MATERIALS_DIR := "res://assets/materials/cart/"
const OUT_DIR := "../mobile/levels"
const NAMES := {"sandbox": "Sandbox", "plot": "Parking lot", "garage": "Parking garage", "market": "Supermarket"}
const ORDER := ["sandbox", "plot", "garage", "market"]


static func out_path(file: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(OUT_DIR).path_join(file).simplify_path()


## The fast-travel destinations, in menu order: [{key, name, scene}].
static func destinations() -> Array:
	var console: Node = (load(CONSOLE_SCENE) as PackedScene).instantiate()
	var dest: Dictionary = console.get("destinations")
	console.free()
	var keys: Array = ORDER.filter(func(k): return dest.has(k))
	for k in dest:
		if not keys.has(k):
			keys.append(k)
	return keys.map(func(k): return {"key": k, "name": NAMES.get(k, String(k).capitalize()), "scene": dest[k]})


## A fingerprint of everything an export depends on: the scene files the level pulls in (recursively), their
## resources and the cart. If it matches the one written last time, the export is current.
static func source_hash(scene_path: String) -> String:
	var seen := {}
	_collect_deps(scene_path, seen)
	_collect_deps(CART_SCENE, seen)
	_collect_deps("res://tools/mobile_level_export.gd", seen)
	var paths := seen.keys()
	paths.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for p in paths:
		ctx.update(p.to_utf8_buffer())
		var bytes := FileAccess.get_file_as_bytes(p)
		ctx.update(bytes)
	return ctx.finish().hex_encode().substr(0, 16)


static func _collect_deps(path: String, seen: Dictionary) -> void:
	if seen.has(path) or not FileAccess.file_exists(path):
		return
	if path.get_extension() in ["jpg", "png", "glb", "gltf", "import"]:
		seen[path] = true
		return
	seen[path] = true
	for dep in ResourceLoader.get_dependencies(path):
		var p: String = dep.get_slice("::", 2) if dep.contains("::") else dep
		if p.begins_with("uid://"):
			p = ResourceUID.get_id_path(ResourceUID.text_to_id(p))
		_collect_deps(p, seen)


# ------------------------------------------------------------------ levels

## Exports one level. `tree` must be a running SceneTree (the level's scripts need _ready and a frame).
static func export_level(tree: SceneTree, key: String, scene_path: String) -> Dictionary:
	var level: Node3D = (load(scene_path) as PackedScene).instantiate()
	tree.root.add_child(level)
	await tree.process_frame
	await tree.process_frame
	level.process_mode = Node.PROCESS_MODE_DISABLED   # the level script must not drive the cart we take out
	var out := {
		"key": key, "name": NAMES.get(key, key), "scene": scene_path, "source": source_hash(scene_path),
		"spawn": null, "spare_carts": [], "environment": {}, "sun": null, "lights": [], "labels": [],
		"statics": [], "bodies": [],
	}
	var spawn := level.get_node_or_null("CartSpawn") as Node3D
	out.spawn = {"pos": _v(spawn.global_position if spawn else Vector3(2, 0, 0)), "yaw": spawn.global_rotation.y if spawn else 0.0}

	# Things the phone builds itself: the player's cart, spare carts, camera, HUD, UI.
	var drop: Array[Node] = []
	for n in level.find_children("*", "", true, false):
		if n is ShoppingCart:
			if n.scene_file_path == SPARE_CART_SCENE or not n.player_controlled:
				out.spare_carts.append({"pos": _v(n.global_position), "yaw": n.global_rotation.y})
			drop.append(n)
		elif n is Camera3D or n is CanvasLayer:
			drop.append(n)
	for n in drop:
		if is_instance_valid(n) and n.get_parent():
			n.get_parent().remove_child(n)
			n.free()

	for n in level.find_children("*", "", true, false):
		if n is WorldEnvironment:
			out.environment = _environment(n.environment)
		elif n is DirectionalLight3D and n.visible:
			out.sun = {"dir": _v(-n.global_basis.z), "color": _c(n.light_color), "energy": n.light_energy,
				"shadows": n.shadow_enabled}
		elif n is OmniLight3D and n.visible:
			out.lights.append({"type": "omni", "pos": _v(n.global_position), "color": _c(n.light_color),
				"energy": n.light_energy, "range": n.omni_range, "attenuation": n.omni_attenuation})
		elif n is SpotLight3D and n.visible:
			out.lights.append({"type": "spot", "pos": _v(n.global_position), "dir": _v(-n.global_basis.z),
				"color": _c(n.light_color), "energy": n.light_energy, "range": n.spot_range,
				"angle": deg_to_rad(n.spot_angle), "attenuation": n.spot_attenuation})
		elif n is Label3D and n.is_visible_in_tree():
			out.labels.append(_label(n))

	# Collision: static shapes go in one list, loose props keep their shapes per body.
	var dyn_count := 0
	for n in level.find_children("*", "CollisionObject3D", true, false):
		var body := n as CollisionObject3D
		if body is Area3D:
			continue
		var shapes := []
		for s in body.find_children("*", "CollisionShape3D", true, false):
			if s.disabled or s.shape == null or _owner_body(s) != body:
				continue
			var sh := _shape(s.shape, s.global_transform)
			if not sh.is_empty():
				shapes.append(sh)
		if shapes.is_empty():
			continue
		var friction := _friction(body)
		if body is RigidBody3D and not body.freeze:
			var rb := body as RigidBody3D
			var id := "dyn_%d" % dyn_count
			dyn_count += 1
			rb.name = id
			var entry := {"node": id, "xf": _xf(rb.global_transform), "mass": rb.mass, "friction": friction,
				"layer": rb.collision_layer, "mask": rb.collision_mask, "can_sleep": rb.can_sleep,
				"shapes": shapes.map(func(sh): return _local_shape(sh, rb.global_transform))}
			if rb.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
				entry["com"] = _v(rb.center_of_mass)
			out.bodies.append(entry)
		else:
			var surface := _surface(body)
			for sh in shapes:
				sh["friction"] = friction
				if surface:
					sh["surface"] = surface
				out.statics.append(sh)

	# What's left that the phone draws: meshes only (lights, labels and physics are in the JSON).
	for n in level.find_children("*", "", true, false):
		if is_instance_valid(n) and (n is Light3D or n is Label3D or n is WorldEnvironment or n is CollisionShape3D):
			n.get_parent().remove_child(n)
			n.free()
	_shrink_textures(level)
	var doc := GLTFDocument.new()
	doc.image_format = "JPEG"
	doc.lossy_quality = 0.8
	var state := GLTFState.new()
	var err := doc.append_from_scene(level, state)
	if err == OK:
		err = doc.write_to_filesystem(state, out_path(key + ".glb"))
	if err != OK:
		push_error("Mobile export: couldn't write %s.glb (error %d)" % [key, err])
	var f := FileAccess.open(out_path(key + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_tidy(out), "", false) + "\n")
	f.close()
	level.queue_free()
	await tree.process_frame
	print("MOBILE LEVEL %s: %d static shapes, %d loose props, %d spare carts, %d lamps, %d labels" % [
		key, out.statics.size(), out.bodies.size(), out.spare_carts.size(), out.lights.size(), out.labels.size()])
	return out


## Phones get each texture once, at most MAX_TEXTURE px: every material that uses the same texture shares one
## smaller copy, so the .glb stores it once.
const MAX_TEXTURE := 512
const TEXTURE_SLOTS := ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture",
	"emission_texture", "ao_texture"]


static func _shrink_textures(level: Node) -> void:
	var cache := {}
	var done := {}
	for mi in level.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		for i in m3.mesh.get_surface_count():
			var m := m3.get_active_material(i) as BaseMaterial3D
			if m == null or done.has(m):
				continue
			done[m] = true
			for slot in TEXTURE_SLOTS:
				var t := m.get(slot) as Texture2D
				if t == null:
					continue
				var key: String = t.resource_path if t.resource_path else str(t.get_instance_id())
				if not cache.has(key):
					var img := t.get_image()
					if img == null:
						cache[key] = t
						continue
					img = img.duplicate()
					if img.is_compressed():
						img.decompress()
					var big := maxi(img.get_width(), img.get_height())
					if big > MAX_TEXTURE:
						var k := float(MAX_TEXTURE) / big
						img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)),
							Image.INTERPOLATE_LANCZOS)
					img.clear_mipmaps()
					var tex := ImageTexture.create_from_image(img)
					tex.resource_name = key.get_file().get_basename()
					cache[key] = tex
				m.set(slot, cache[key])


static func _owner_body(n: Node) -> Node:
	var p := n.get_parent()
	while p and not p is CollisionObject3D:
		p = p.get_parent()
	return p


## The floor's physics material by name (assets/physics/<name>.tres), which picks the cart's rolling sound.
static func _surface(body: CollisionObject3D) -> String:
	var m: PhysicsMaterial = body.get("physics_material_override")
	return m.resource_path.get_file().get_basename() if m and m.resource_path else ""


static func _friction(body: CollisionObject3D) -> float:
	var m: PhysicsMaterial = body.get("physics_material_override")
	return m.friction if m else 1.0


## A collision shape in world space: {type, xf (unscaled), size/radius/height/points/faces}.
static func _shape(shape: Shape3D, xf: Transform3D) -> Dictionary:
	var sc := xf.basis.get_scale()
	var clean := Transform3D(xf.basis.orthonormalized(), xf.origin)
	var d := {"xf": _xf(clean)}
	if shape is BoxShape3D:
		d.type = "box"
		d.size = _v(shape.size * sc)
	elif shape is CylinderShape3D:
		d.type = "cylinder"
		d.radius = shape.radius * maxf(sc.x, sc.z)
		d.height = shape.height * sc.y
	elif shape is SphereShape3D:
		d.type = "sphere"
		d.radius = shape.radius * sc.x
	elif shape is CapsuleShape3D:
		d.type = "capsule"
		d.radius = shape.radius * maxf(sc.x, sc.z)
		d.height = shape.height * sc.y
	elif shape is ConvexPolygonShape3D:
		d.type = "convex"
		d.points = _flat(Array(shape.points).map(func(p): return p * sc))
	elif shape is ConcavePolygonShape3D:
		d.type = "mesh"
		d.faces = _flat(Array(shape.get_faces()).map(func(p): return p * sc))
	elif shape is WorldBoundaryShape3D:
		d.type = "box"
		var plane: Plane = shape.plane
		d.xf = _xf(Transform3D(Basis.IDENTITY, xf * (plane.normal * plane.d - plane.normal * 0.5)))
		d.size = [400, 1, 400]
	else:
		push_warning("Mobile export: %s isn't supported, skipped" % shape.get_class())
		return {}
	return d


## Re-expresses a world-space shape in the body's frame.
static func _local_shape(sh: Dictionary, body_xf: Transform3D) -> Dictionary:
	var a: Array = sh.xf
	var w := Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
		Vector3(a[9], a[10], a[11]))
	var d := sh.duplicate()
	d.xf = _xf(body_xf.affine_inverse() * w)
	return d


static func _environment(env: Environment) -> Dictionary:
	if env == null:
		return {}
	var d := {
		"background": ["clear", "color", "sky", "canvas", "keep", "camera"][env.background_mode],
		"bg_color": _c(env.background_color), "bg_energy": env.background_energy_multiplier,
		"ambient_source": ["background", "disabled", "color", "sky"][env.ambient_light_source],
		"ambient_color": _c(env.ambient_light_color), "ambient_energy": env.ambient_light_energy,
		"ambient_sky_contribution": env.ambient_light_sky_contribution,
		"tonemap": env.tonemap_mode, "exposure": env.tonemap_exposure,
		"fog": env.fog_enabled, "fog_color": _c(env.fog_light_color), "fog_density": env.fog_density,
	}
	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var s := env.sky.sky_material as ProceduralSkyMaterial
		d.sky = {"top": _c(s.sky_top_color), "horizon": _c(s.sky_horizon_color),
			"ground_bottom": _c(s.ground_bottom_color), "ground_horizon": _c(s.ground_horizon_color),
			"energy": s.sky_energy_multiplier}
	elif env.sky and env.sky.sky_material is PhysicalSkyMaterial:
		var p := env.sky.sky_material as PhysicalSkyMaterial
		d.sky = {"top": _c(p.rayleigh_color), "horizon": _c(p.mie_color), "ground_bottom": _c(p.ground_color),
			"ground_horizon": _c(p.ground_color), "energy": p.energy_multiplier}
	return d


static func _label(l: Label3D) -> Dictionary:
	return {"text": l.text, "xf": _xf(l.global_transform), "pixel_size": l.pixel_size, "font_size": l.font_size,
		"color": _c(l.modulate), "outline_color": _c(l.outline_modulate), "outline_size": l.outline_size,
		"billboard": l.billboard != BaseMaterial3D.BILLBOARD_DISABLED, "double_sided": l.double_sided,
		"shaded": l.shaded, "width": l.width, "autowrap": l.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"h_align": l.horizontal_alignment, "v_align": l.vertical_alignment, "offset": [l.offset.x, l.offset.y],
		"line_spacing": l.line_spacing, "bold": l.font != null and l.font.get_font_style() & TextServer.FONT_BOLD != 0}


# ------------------------------------------------------------------ the cart rig

## The cart rig as the phone builds it: bodies (mass, centre of mass, shapes, layers, damping), the hinges
## between them with their limits, the groceries and the cart's shared materials.
static func export_cart() -> Dictionary:
	var cart: ShoppingCart = (load(CART_SCENE) as PackedScene).instantiate()
	var out := {"source": source_hash(CART_SCENE), "bodies": [], "joints": [], "groceries": [], "materials": {},
		"guard": null}
	var bodies: Array = [cart.get_node("Frame"), cart.get_node("Gate"), cart.get_node("ChildSeat"),
		cart.get_node("SeatFlap")]
	for k in ["RL", "RR", "FL", "FR"]:
		if cart.has_node("Fork_" + k):
			bodies.append(cart.get_node("Fork_" + k))
		bodies.append(cart.get_node("Wheel_" + k))
	for b in bodies:
		out.bodies.append(_rig_body(b))
	for g in cart.get_node("Groceries").get_children():
		if g is RigidBody3D:
			var e := _rig_body(g)
			var mesh := g.get_node_or_null("Mesh") as MeshInstance3D
			if mesh and mesh.mesh:
				var m := mesh.mesh.surface_get_material(0) as StandardMaterial3D
				if m:
					e["color"] = _c(m.albedo_color)
					e["roughness"] = m.roughness
			out.groceries.append(e)
	for j in cart.find_children("*", "HingeJoint3D", false, false):
		var hj := j as HingeJoint3D
		var lim: bool = hj.get("angular_limit/enable")
		out.joints.append({"name": String(hj.name), "a": String(hj.node_a).get_file(), "b": String(hj.node_b).get_file(),
			"xf": _xf(hj.transform), "limit": [hj.get("angular_limit/lower"), hj.get("angular_limit/upper")] if lim else null})
	var zone := cart.get_node_or_null("Frame/Guard/Zone") as CollisionShape3D
	if zone:
		out.guard = _shape(zone.shape, zone.transform)
	for f in DirAccess.get_files_at(CART_MATERIALS_DIR):
		if f.get_extension() == "tres":
			var m := load(CART_MATERIALS_DIR + f) as StandardMaterial3D
			if m:
				out.materials[f.get_basename()] = {"color": _c(m.albedo_color), "metallic": m.metallic,
					"roughness": m.roughness}
	out["rolling_sound"] = _rolling_sound(cart.get_node("Frame/RollingSound"))
	out["wheel_radius"] = cart.get_node("Wheel_FL/Shape").shape.radius
	out["hand_position"] = _v(cart.hand_position)
	cart.free()
	var f := FileAccess.open(out_path("cart.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_tidy(out), "", false) + "\n")
	f.close()
	print("MOBILE CART: %d bodies, %d hinges, %d groceries, %d materials" % [out.bodies.size(), out.joints.size(),
		out.groceries.size(), out.materials.size()])
	return out


## The rolling sound (Frame/RollingSound): its settings, the floor probe and each surface's loop. The phone plays
## mobile/audio/<loop>.wav, cut from the same recordings as the .ogg (tools/audio/make_cart_rolling_loops.py).
static func _rolling_sound(rs: CartRollingSound) -> Dictionary:
	var out := {"probe": _xf(rs.transform * rs.probe.transform), "probe_target": _v(rs.probe.target_position),
		"fallback": String(rs.fallback.name), "sounds": []}
	for key in ["silent_speed", "full_volume_speed", "volume_curve", "recorded_speed", "min_pitch", "max_pitch",
			"pitch_per_speed", "fade_time"]:
		out[key] = rs.get(key)
	for s in rs.get_children():
		if s is RollingSurfaceSound:
			out.sounds.append({"name": String(s.name), "file": "audio/%s.wav" % s.stream.resource_path.get_file().get_basename(),
				"floors": s.floors.map(func(m): return m.resource_path.get_file().get_basename()),
				"loudness_db": s.loudness_db, "unit_size": s.unit_size, "max_distance": s.max_distance})
	return out


static func _rig_body(b: RigidBody3D) -> Dictionary:
	var shapes := []
	for s in b.get_children():
		if s is CollisionShape3D and not s.disabled:
			var sh := _shape(s.shape, s.transform)
			if not sh.is_empty():
				shapes.append(sh)
	var d := {"name": String(b.name), "xf": _xf(b.transform), "mass": b.mass, "friction": _friction(b),
		"layer": b.collision_layer, "mask": b.collision_mask, "shapes": shapes,
		"linear_damp": b.linear_damp if b.linear_damp_mode == RigidBody3D.DAMP_MODE_REPLACE else -1.0,
		"angular_damp": b.angular_damp, "angular_damp_mode": b.angular_damp_mode}
	if b.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		d["com"] = _v(b.center_of_mass)
	return d


# ------------------------------------------------------------------ helpers

static func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _c(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


## Basis columns then origin: [x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z, o.x, o.y, o.z].
static func _xf(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


static func _flat(points: Array) -> Array:
	var a := []
	for p in points:
		a.append_array([p.x, p.y, p.z])
	return a


static func _tidy(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return snappedf(v, 0.00001)
		TYPE_ARRAY:
			return (v as Array).map(_tidy)
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _tidy(v[k])
			return d
	return v


## Exports every level, the cart and the level list (mobile/levels/levels.json).
static func export_all(tree: SceneTree, only: Array = []) -> void:
	DirAccess.make_dir_recursive_absolute(out_path(""))
	export_cart()
	var list := []
	for d in destinations():
		list.append(d)
		if only.is_empty() or only.has(d.key):
			await export_level(tree, d.key, d.scene)
	var f := FileAccess.open(out_path("levels.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(list, "  ", false) + "\n")
	f.close()
