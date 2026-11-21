extends SceneTree
## Headless: rebuilds the sandbox hill's collision shapes from its meshes (assets/models/sandbox/hill/hill.glb),
## so the ground you drive on is exactly the ground you see. Writes assets/models/sandbox/hill/<mesh>_shape.res
## for the road, sidewalk and lawn; scenes/sandbox/chunks/hill.tscn uses them, one StaticBody3D per floor.
## Run after tools/sandbox_models.py changed the hill:
##   godot --headless -s res://tools/make_sandbox_shapes_cli.gd

const MODEL := "res://assets/models/sandbox/hill/hill.glb"
const SOLID := ["road", "sidewalk", "lawn"]


func _init() -> void:
	var scene: Node = (load(MODEL) as PackedScene).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if not mi.name in SOLID:
			continue
		var shape: ConcavePolygonShape3D = mi.mesh.create_trimesh_shape()
		var path := MODEL.get_base_dir().path_join("%s_shape.res" % mi.name)
		ResourceSaver.save(shape, path)
		print("SHAPE %s: %d triangles -> %s" % [mi.name, shape.get_faces().size() / 3, path])
	scene.free()
	quit()
