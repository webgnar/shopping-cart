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
##    loose props (mass, shapes), CartSpawn, the spare carts, the bot carts and the navigation mesh they drive on,
##    sky/fog/ambient, the sun, lamps and 3D labels, the race (grid, finish box, bots' route), the lanes of moving
##    traffic (TrafficLane: speed, length, each car's place and shapes; cars are kin_<n>; a TrafficRoute also has its
##    points), the background loop ("music"), and for the endless sandbox, the chunk grid ("stream"). Nodes with
##    metadata/mobile_skip (the coast's far trees) are left out.
##  - mobile/levels/chunks/<name>.glb and .json: each chunk the sandbox streams (scenes/sandbox/chunks/), the same way.
## And once for the cart (scenes/cart/cart.tscn): mobile/levels/cart.json with the rig (bodies, masses, shapes,
## hinges and their limits), the cart's shared materials (assets/materials/cart/*.tres) and the bot's settings
## (scenes/cart/bot_cart.tscn: the CartBot exports and its NavigationAgent3D).
##
## Run headless from shopping-cart/:  godot --headless -s res://tools/export_mobile_levels_cli.gd
## tests/mobile_levels_sync_test.gd fails when a level or the cart changed since the last export.

const CONSOLE_SCENE := "res://scenes/ui/console.tscn"
const CART_SCENE := "res://scenes/cart/cart.tscn"
const SPARE_CART_SCENE := "res://scenes/cart/spare_cart.tscn"
const BOT_CART_SCENE := "res://scenes/cart/bot_cart.tscn"
const SKYLINE_SKY_SHADER := "res://scenes/environment/skyline_sky.gdshader"
const CART_MATERIALS_DIR := "res://assets/materials/cart/"
const OUT_DIR := "../mobile/levels"
const NAMES := {"sandbox": "Sandbox", "plot": "Parking lot", "garage": "Parking garage", "market": "Supermarket",
	"hill": "San Francisco hill", "coast": "Coast highway"}
const ORDER := ["sandbox", "plot", "garage", "market", "hill", "coast"]
const ROUTE_STEP := 2.0   ## m between the points of an exported TrafficRoute


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
	_collect_deps(BOT_CART_SCENE, seen)
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
		"spawn": null, "spare_carts": [], "bot_carts": [], "navmesh": null, "environment": {}, "sun": null, "lights": [], "labels": [],
		"statics": [], "bodies": [], "traffic": [],
	}
	if level.has_meta("mobile_merge_cell"):   # a long level can merge its meshes in bigger cells (fewer draws)
		out["merge_cell"] = float(level.get_meta("mobile_merge_cell"))
	var spawn := level.get_node_or_null("CartSpawn") as Node3D
	out.spawn = {"pos": _v(spawn.global_position if spawn else Vector3(2, 0, 0)), "yaw": spawn.global_rotation.y if spawn else 0.0}
	var sweep: Sweep = null
	for n in level.find_children("*", "", true, false):
		if n is Race:
			out["race"] = _race(n)
		elif n is Sweep:
			sweep = n
	# A sweep's labels that change (a display's "8 left") or move (an inflatable's price) go with the sweep's data.
	var sweep_labels := {}
	if sweep:
		for d in sweep.display_list():
			sweep_labels[d.left_label] = true
		for b in sweep.inflatable_list():
			for l in b.find_children("*", "Label3D", true, false):
				sweep_labels[l] = true

	# An endless level (ChunkStreamer): its settings go in the JSON and each chunk is exported on its own
	# (export_chunk); the chunks it has loaded around the cart and its far ground are left out of the level.
	for st in level.find_children("*", "ChunkStreamer", true, false):
		out["stream"] = _stream(st)
		st.get_parent().remove_child(st)
		st.free()

	# Things the phone builds itself: the player's cart, spare carts, camera, HUD, UI.
	# A spare cart tucked into another (a stack, scenes/cart/cart_stack_*.tscn) names the spare it is nested in.
	var drop: Array[Node] = []
	var spares: Array[ShoppingCart] = []
	for n in level.find_children("*", "", true, false):
		if n is ShoppingCart:
			if n.driver is CartBot:
				out.bot_carts.append({"pos": _v(n.global_position), "yaw": n.global_rotation.y})
			elif n.scene_file_path == SPARE_CART_SCENE or not n.player_controlled:
				spares.append(n)
			drop.append(n)
		elif n is Camera3D or n is CanvasLayer or n is CartNest:
			drop.append(n)
		elif n.is_in_group("mobile_export_skip"):
			# Local-only content (the garage's Manhattan skyline from Google Earth tiles) never goes to the web.
			drop.append(n)
	for n in spares:
		var e := {"pos": _v(n.global_position), "yaw": n.global_rotation.y}
		if n.nested_in != null and spares.has(n.nested_in):
			e["nested_in"] = spares.find(n.nested_in)
		out.spare_carts.append(e)
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
		elif n is Label3D and n.is_visible_in_tree() and not sweep_labels.has(n):
			out.labels.append(_label(n))
		elif n is NavigationRegion3D and n.navigation_mesh and out.navmesh == null:
			out.navmesh = _navmesh(n)
		elif n is AudioStreamPlayer and n.autoplay and n.stream:
			out["music"] = _music(n)

	# Moving traffic: each lane's place, speed and length, and its cars (kin_<n>) with their shapes and their
	# places in the queue. The phone drives them the same way (TrafficLane).
	var moving := {}
	for lane in level.find_children("*", "Node3D", true, false):
		if not lane is TrafficLane:
			continue
		var entry := {"xf": _xf(lane.global_transform), "speed": lane.speed, "length": lane.length, "cars": []}
		var cars: Array = lane.get("_cars")
		for i in cars.size():
			var car: AnimatableBody3D = cars[i]
			var id := "kin_%d" % moving.size()
			moving[car] = true
			car.name = id
			var shapes := []   # in the car's own frame
			for s in car.get_children():
				if s is CollisionShape3D and not s.disabled and s.shape:
					var sh := _shape(s.shape, s.transform)
					if not sh.is_empty():
						shapes.append(sh)
			entry.cars.append({"node": id, "offset": lane.distance(i, 0.0), "friction": _friction(car), "shapes": shapes})
		out.traffic.append(entry)
	# Traffic along a winding road (TrafficRoute): the route as points every ROUTE_STEP m from its start, and the
	# cars' places along it. The phone samples the points the way Godot samples the curve.
	for route in level.find_children("*", "Path3D", true, false):
		if not route is TrafficRoute:
			continue
		var pts := []
		var n := int(ceil(route.length / ROUTE_STEP))
		for k in n + 1:
			pts.append(route.global_transform * route.curve.sample_baked(minf(k * ROUTE_STEP, route.length)))
		var entry := {"route": _flat(pts), "step": ROUTE_STEP, "speed": route.speed, "length": route.length, "cars": []}
		var cars: Array = route.get("_cars")
		for i in cars.size():
			var car: AnimatableBody3D = cars[i]
			var id := "kin_%d" % moving.size()
			moving[car] = true
			car.name = id
			var shapes := []
			for s in car.get_children():
				if s is CollisionShape3D and not s.disabled and s.shape:
					var sh := _shape(s.shape, s.transform)
					if not sh.is_empty():
						shapes.append(sh)
			entry.cars.append({"node": id, "offset": route.distance(i, 0.0), "friction": _friction(car), "shapes": shapes})
		out.traffic.append(entry)

	# Things a level marks as too much for a phone (metadata/mobile_skip): left out of the export.
	for n in level.find_children("*", "", true, false):
		if is_instance_valid(n) and n.get_meta("mobile_skip", false):
			n.get_parent().remove_child(n)
			n.free()

	# Collision: static shapes go in one list, loose props keep their shapes per body.
	var dyn_count := 0
	var dyn_ids := {}   # body -> its dyn_<n> name
	for n in level.find_children("*", "CollisionObject3D", true, false):
		var body := n as CollisionObject3D
		if body is Area3D or moving.has(body):
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
		if body is RigidBody3D and (not body.freeze or body is Product):
			# Loose props, and a sweep's products, which sit frozen on their displays until someone takes them.
			var rb := body as RigidBody3D
			var id := "dyn_%d" % dyn_count
			dyn_count += 1
			dyn_ids[rb] = id
			rb.name = id
			var entry := {"node": id, "xf": _xf(rb.global_transform), "mass": rb.mass, "friction": friction,
				"layer": rb.collision_layer, "mask": rb.collision_mask, "can_sleep": rb.can_sleep,
				"shapes": shapes.map(func(sh): return _local_shape(sh, rb.global_transform))}
			if rb.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
				entry["com"] = _v(rb.center_of_mass)
			if rb.freeze:
				entry["frozen"] = true
			out.bodies.append(entry)
		else:
			var surface := _surface(body)
			for sh in shapes:
				sh["friction"] = friction
				if surface:
					sh["surface"] = surface
				out.statics.append(sh)

	if sweep:
		out["sweep"] = _sweep(sweep, dyn_ids, sweep_labels)

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
	print("MOBILE LEVEL %s: %d static shapes, %d loose props, %d spare carts, %d bot carts, %d nav polygons, %d lamps, %d labels, %d traffic lanes" % [
		key, out.statics.size(), out.bodies.size(), out.spare_carts.size(), out.bot_carts.size(),
		out.navmesh.polygons.size() if out.navmesh else 0, out.lights.size(), out.labels.size(), out.traffic.size()])
	return out


## A ChunkStreamer's settings for mobile/game/stream.js: the grid, the chunks (exported to levels/chunks/<name>),
## their weights, the far ground, and a table of picks the browser checks its own hash against.
static func _stream(st: ChunkStreamer) -> Dictionary:
	var d := {"origin": _v(st.global_position), "chunk_size": st.chunk_size, "seed": st.world_seed, "turns": st.turns,
		"load_distance": st.load_distance, "unload_distance": st.unload_distance,
		"home_cells": st.home_cells.map(func(c): return [c.x, c.y]), "weights": Array(st.weights),
		"chunks": st.chunks.map(func(c): return {"key": chunk_key(c.resource_path), "scene": c.resource_path}),
		"far_ground": null, "check": []}
	var fg := st.far_ground as MeshInstance3D
	if fg and fg.mesh is PlaneMesh:
		var m := fg.mesh.surface_get_material(0) as StandardMaterial3D
		d.far_ground = {"y": fg.position.y, "size": (fg.mesh as PlaneMesh).size.x,
			"color": _c(m.albedo_color if m else Color.GRAY)}
	for i in range(-6, 7, 3):
		for j in range(-6, 7, 2):
			var p := st.pick(Vector2i(i * 7 - 3, j * 13 + 5))
			d.check.append([i * 7 - 3, j * 13 + 5, p[0], p[1]])
	return d


## Where a chunk scene's export goes, under mobile/levels/: chunks/<scene name>.
static func chunk_key(scene_path: String) -> String:
	return "chunks/" + scene_path.get_file().get_basename()


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
		# An endless floor: the phone uses Rapier's half-space (a box tens of km wide costs contact precision).
		# xf: a point on the plane, local +Y along its normal.
		d.type = "plane"
		var plane: Plane = shape.plane
		var normal := (xf.basis * plane.normal).normalized()
		d.xf = _xf(Transform3D(Basis(Quaternion(Vector3.UP, normal)), xf * (plane.normal * plane.d)))
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
		"fog_mode": ["exponential", "depth"][env.fog_mode], "fog_depth_begin": env.fog_depth_begin,
		"fog_depth_end": env.fog_depth_end,
	}
	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var s := env.sky.sky_material as ProceduralSkyMaterial
		d.sky = {"top": _c(s.sky_top_color), "horizon": _c(s.sky_horizon_color),
			"ground_bottom": _c(s.ground_bottom_color), "ground_horizon": _c(s.ground_horizon_color),
			"energy": s.sky_energy_multiplier}
	elif env.sky and env.sky.sky_material is ShaderMaterial and env.sky.sky_material.shader \
			and env.sky.sky_material.shader.resource_path == SKYLINE_SKY_SHADER:
		# The garage's sky: a procedural sky in a shader (plus a skyline the phone doesn't get).
		var m := env.sky.sky_material as ShaderMaterial
		d.sky = {"top": _c(m.get_shader_parameter("sky_top_color")),
			"horizon": _c(m.get_shader_parameter("sky_horizon_color")),
			"ground_bottom": _c(m.get_shader_parameter("ground_bottom_color")),
			"ground_horizon": _c(m.get_shader_parameter("ground_horizon_color")),
			"energy": float(m.get_shader_parameter("sky_energy"))}
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
	out["wheel_sound"] = _wheel_sound(cart.get_node("Wheel_RL/WheelSound"))
	out["wheel_radius"] = cart.get_node("Wheel_FL/Shape").shape.radius
	out["hand_position"] = _v(cart.hand_position)
	out["touching"] = ShoppingCart.TOUCHING_PARTS
	out["nest"] = _nest_settings(cart.get_node("Frame/NestMouth"))
	cart.free()
	out["bot"] = _bot_settings()
	var f := FileAccess.open(out_path("cart.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_tidy(out), "", false) + "\n")
	f.close()
	print("MOBILE CART: %d bodies, %d hinges, %d groceries, %d materials" % [out.bodies.size(), out.joints.size(),
		out.groceries.size(), out.materials.size()])
	return out


## How carts nest (scenes/cart/nest_joint.tscn and the cart's Frame/NestMouth): the slide, its grip, the play,
## where the pivot sits, the gate motor, what breaks a nest and when a nose is caught.
static func _nest_settings(mouth: CartNestMouth) -> Dictionary:
	var j: CartNest = mouth.nest_scene.instantiate()
	var out := {"spacing": j.spacing, "pivot": _v(j.pivot), "gate_speed": j.gate_speed, "gate_impulse": j.gate_impulse,
		"break_impulse": j.break_impulse, "impulse_window": j.impulse_window, "release_margin": j.release_margin,
		"slide": [j.get("linear_limit_x/lower_distance"), j.get("linear_limit_x/upper_distance")],
		"grip": j.get("linear_motor_x/force_limit") if j.get("linear_motor_x/enabled") else 0.0,
		"yaw": [j.get("angular_limit_y/lower_angle"), j.get("angular_limit_y/upper_angle")],
		"pitch": [j.get("angular_limit_z/lower_angle"), j.get("angular_limit_z/upper_angle")],
		"roll": [j.get("angular_limit_x/lower_angle"), j.get("angular_limit_x/upper_angle")],
		"capture_depth": mouth.capture_depth, "capture_offset": mouth.capture_offset, "capture_angle": mouth.capture_angle,
		"capture_tilt": mouth.capture_tilt, "capture_speed": mouth.capture_speed, "nose": _v(mouth.nose)}
	var zone := mouth.get_node("Zone") as CollisionShape3D
	out["mouth"] = _shape(zone.shape, zone.transform)
	j.free()
	var cart: ShoppingCart = mouth.get_parent().get_parent()
	out["ghost_clearance"] = cart.ghost_clearance
	return out


## The navigation mesh the bots drive on (a level's NavigationRegion3D), in world space: vertices and polygons.
static func _navmesh(region: NavigationRegion3D) -> Dictionary:
	var nm := region.navigation_mesh
	var xf := region.global_transform
	var verts := []
	for v in nm.get_vertices():
		verts.append(xf * v)
	var polys := []
	for i in nm.get_polygon_count():
		polys.append(Array(nm.get_polygon(i)))
	return {"vertices": _flat(verts), "polygons": polys}


## A level's race (scripts/race/race.gd) for mobile/game/race.js: its settings, the grid's slots, the finish box
## (centre transform and size), the bots' route and the spot past the line they drive to.
static func _race(r: Race) -> Dictionary:
	var shape: CollisionShape3D = r.finish.find_children("*", "CollisionShape3D", true, false)[0]
	var way := []
	if r.route:
		for m in r.route.get_children():
			if m is Marker3D:
				way.append(_v(m.global_position))
	return {
		"countdown": r.countdown, "go_hold": r.go_hold, "bots_race": r.bots_race, "finish_grace": r.finish_grace,
		"slots": r.slots().map(func(m): return {"pos": _v(m.global_position), "yaw": m.global_basis.get_euler().y}),
		"finish": {"xf": _xf(shape.global_transform), "size": _v((shape.shape as BoxShape3D).size)},
		"route": way, "bot_goal": _v(r.bot_goal.global_position),
	}


## A level's supermarket sweep (scripts/sweep/sweep.gd) for mobile/game/sweep.js: its settings, the starting slots,
## each display (its product, price, the items on it by their dyn_<n> body, where a bot stops, its grab zone and its
## "left" label), the inflatables (body, bonus, label) and the bonus stations (box, bonus, hold time).
static func _sweep(sw: Sweep, ids: Dictionary, labels: Dictionary) -> Dictionary:
	var box := func(area: Area3D) -> Dictionary:
		var shape: CollisionShape3D = area.find_children("*", "CollisionShape3D", true, false)[0]
		return {"xf": _xf(shape.global_transform), "size": _v((shape.shape as BoxShape3D).size)}
	var out := {
		"duration": sw.duration, "countdown": sw.countdown, "go_hold": sw.go_hold, "item_limit": sw.item_limit,
		"grab_speed": sw.grab_speed, "grab_interval": sw.grab_interval, "bots_shop": sw.bots_shop,
		"bot_linger": sw.bot_linger,
		"slots": sw.slots().map(func(m): return {"pos": _v(m.global_position), "yaw": m.global_basis.get_euler().y}),
		"displays": [], "bonuses": [], "stations": [],
	}
	for d in sw.display_list():
		var items := d.items()
		out.displays.append({"name": d.product_name(), "price": d.price(), "stop": _v(d.stop.global_position),
			"zone": box.call(d.zone), "items": items.map(func(p): return ids[p]),
			"left_label": _label(d.left_label)})
	for b in sw.inflatable_list():
		var l: Array = b.find_children("*", "Label3D", true, false)
		out.bonuses.append({"node": ids[b], "name": b.bonus_name, "bonus": b.bonus, "stash": _v(b.stash_offset),
			"label": _label(l[0]) if not l.is_empty() else null,
			"label_offset": _v(b.global_transform.affine_inverse() * l[0].global_position) if not l.is_empty() else null})
	for st in sw.station_list():
		out.stations.append({"title": st.title, "bonus": st.bonus, "hold_time": st.hold_time,
			"still_speed": st.still_speed, "zone": box.call(st)})
	return out


## The bot's settings from scenes/cart/bot_cart.tscn: every CartBot export, plus where its NavigationAgent3D sits on
## the frame and how close it gets to a path point or the target.
static func _bot_settings() -> Dictionary:
	var cart: ShoppingCart = (load(BOT_CART_SCENE) as PackedScene).instantiate()
	var bot: CartBot = cart.find_children("*", "", true, false).filter(func(n): return n is CartBot)[0]
	var out := {}
	for p in bot.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_EDITOR and p.type in [TYPE_FLOAT, TYPE_INT]:
			out[p.name] = bot.get(p.name)
	var agent := bot.agent
	out["nav_point"] = _v((agent.get_parent() as Node3D).position)
	out["path_desired_distance"] = agent.path_desired_distance
	out["target_desired_distance"] = agent.target_desired_distance
	cart.free()
	return out


## A level's background loop (an autoplaying AudioStreamPlayer, e.g. the parking lot's BackgroundMusic). The phone
## plays mobile/audio/<name>.mp3, cut by the same script as the .ogg (tools/audio/make_ambience_loops.py): the loop
## plus a few seconds of what follows it, which mobile/game/music.js crossfades into the next pass.
static func _music(p: AudioStreamPlayer) -> Dictionary:
	var bus := AudioServer.get_bus_index(p.bus)
	return {"file": "audio/%s.mp3" % p.stream.resource_path.get_file().get_basename(), "loop_length": p.stream.get_length(),
		"volume_db": p.volume_db + (AudioServer.get_bus_volume_db(bus) if bus >= 0 else 0.0), "bus": String(p.bus)}


## The wheel sound (scenes/cart/wheel_sound.tscn, the same under every wheel): its settings, each floor's roll and
## scrub loops, the knocks and the landing. The phone plays mobile/audio/<name>.wav, cut from the same recordings
## as the Godot files (tools/audio/make_cart_rolling_loops.py).
static func _wheel_sound(ws: WheelSound) -> Dictionary:
	var wav := func(stream: AudioStream) -> String: return "audio/%s.wav" % stream.resource_path.get_file().get_basename()
	var floor_dict := func(f: CartFloorSound) -> Dictionary: return {"name": f.resource_path.get_file().get_basename(),
		"floors": f.floors.map(func(m): return m.resource_path.get_file().get_basename()),
		"roll": wav.call(f.roll), "roll_db": f.roll_db, "scrub": wav.call(f.scrub), "scrub_db": f.scrub_db}
	var shots := func(p: AudioStreamPlayer3D) -> Dictionary:
		var r := p.stream as AudioStreamRandomizer
		var files := []
		for i in r.streams_count:
			files.append(wav.call(r.get_stream(i)))
		return {"files": files, "random_pitch": r.random_pitch}
	var out := {"floors": ws.floor_sounds.map(floor_dict), "fallback": ws.fallback.resource_path.get_file().get_basename(),
		"knock": shots.call(ws.knock_player), "land": shots.call(ws.land_player),
		"unit_size": ws.roll_player.unit_size, "max_distance": ws.roll_player.max_distance}
	for key in ["contact_gap", "wheel_db", "silent_speed", "full_volume_speed", "volume_curve", "recorded_speed",
			"min_pitch", "max_pitch", "pitch_per_speed", "fade_time", "scrub_start", "scrub_full", "skid_tolerance", "scrub_pitch_low",
			"scrub_pitch_per_speed", "scrub_max_pitch", "knock_start", "knock_full", "knock_db", "knock_gap",
			"land_air_time", "land_start", "land_full", "land_db"]:
		out[key] = ws.get(key)
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
	var chunks := {}
	for d in destinations():
		list.append(d)
		if only.is_empty() or only.has(d.key):
			var out: Dictionary = await export_level(tree, d.key, d.scene)
			if out.has("stream"):
				for c in out.stream.chunks:
					chunks[c.key] = c.scene
	# The endless level's chunks, each like a small level of its own (centred on its square, unturned).
	DirAccess.make_dir_recursive_absolute(out_path("chunks"))
	for k in chunks:
		await export_level(tree, k, chunks[k])
	var f := FileAccess.open(out_path("levels.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(list, "  ", false) + "\n")
	f.close()
