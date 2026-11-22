extends SceneTree
## Headless: builds the coast highway's resources from the models tools/coast_models.py wrote.
##  - Collision: one trimesh shape per object of assets/models/coast/collision/collision.glb (the road deck, the
##    guardrail, the terrain of each segment, the headlands and tunnels) -> assets/models/coast/collision/<name>.res.
##  - Trees: each tree model's objects (trunk and crown, one material each) merged into one mesh with LODs, for the
##    MultiMeshes -> assets/models/coast/<tree>/<tree>_mesh.res.
##  - Tree placements: one MultiMesh per segment and kind from assets/models/coast/coast_plan.json
##    -> assets/models/coast/trees/segment_NN_<kind>.tres. The segment scenes (scenes/coast/) draw them.
## Run after tools/coast_models.py (see its docstring for the whole sequence). It needs a renderer (a MultiMesh keeps
## its instances on the rendering server, which --headless doesn't have), so on a machine without a display:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tools/make_coast_resources_cli.gd

const DIR := "res://assets/models/coast/"
const TREES := ["pine", "cypress", "shrub"]
const KINDS := {"pine": "pine", "cypress": "cypress", "shrub": "shrub", "far_pine": "pine", "far_cypress": "cypress"}


func _initialize() -> void:
	var col: Node = (load(DIR + "collision/collision.glb") as PackedScene).instantiate()
	for mi in col.find_children("*", "MeshInstance3D", true, false):
		var shape: ConcavePolygonShape3D = mi.mesh.create_trimesh_shape()
		shape.backface_collision = true   # the terrain and tunnels are open surfaces: solid from both sides
		var path: String = DIR + "collision/%s.res" % mi.name
		ResourceSaver.save(shape, path)
		print("SHAPE %s: %d triangles" % [mi.name, shape.get_faces().size() / 3])
	col.free()

	var meshes := {}
	for kind in TREES:
		var scene: Node = (load(DIR + "%s/%s.glb" % [kind, kind]) as PackedScene).instantiate()
		var im := ImporterMesh.new()
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mi.mesh
			for s in m.get_surface_count():
				im.add_surface(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(s), [], {}, m.surface_get_material(s),
					String(mi.name))
		im.generate_lods(25.0, 60.0, [])
		var mesh := im.get_mesh()
		var path: String = DIR + "%s/%s_mesh.res" % [kind, kind]
		ResourceSaver.save(mesh, path)
		meshes[kind] = load(path)
		scene.free()
		print("TREE MESH %s: %d surfaces" % [kind, mesh.get_surface_count()])

	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "coast_plan.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "trees"))
	var total := 0
	for seg in plan.trees:
		for kind in KINDS:
			var list: Array = plan.trees[seg][kind]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[KINDS[kind]]
			mm.instance_count = list.size()
			for i in list.size():
				var e: Array = list[i]
				var b := Basis(Vector3.UP, e[3]).scaled(Vector3.ONE * e[4])
				mm.set_instance_transform(i, Transform3D(b, Vector3(e[0], e[1], e[2])))
			total += list.size()
			ResourceSaver.save(mm, DIR + "trees/segment_%02d_%s.tres" % [int(seg), kind])
	print("TREES: %d placed" % total)
	quit()
