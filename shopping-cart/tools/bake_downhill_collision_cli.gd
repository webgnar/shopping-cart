extends SceneTree
## Bakes the downhill highway's collision from its road sweep (scenes/levels/downhill_highway.tscn):
##   godot --headless -s res://tools/bake_downhill_collision_cli.gd
## The road, barriers and slopes are CSGPolygon3D nodes swept along the `Road` Path3D, which you edit in the editor.
## CSG can't carry a physics material, so their collision lives on StaticBody3Ds (RoadBody, Barriers, Slopes) whose
## shapes are baked from the CSG into assets/downhill/collision/. Re-run this after moving the road's curve points
## or changing a cross-section.

const LEVEL := "res://scenes/levels/downhill_highway.tscn"
const OUT := "res://assets/downhill/collision/"
## Collision shape file -> the CSG nodes under Road whose faces go into it.
const GROUPS := {
	"road": ["Asphalt"],
	"barriers": ["BarrierLeft", "BarrierRight"],
	"slopes": ["SlopeLeft", "SlopeRight"],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Load the scene without its collision files (they may not exist yet): just the Road branch.
	var level := (load(LEVEL) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	var road := level.get_node("Road") as Path3D
	level.remove_child(road)
	level.free()
	root.add_child(road)
	for i in 3:
		await process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	for file in GROUPS:
		var faces := PackedVector3Array()
		for n in GROUPS[file]:
			var csg := road.get_node(n) as CSGShape3D
			var shape := csg.bake_collision_shape()
			var xf := road.transform * csg.transform
			for v in shape.get_faces():
				faces.append(xf * v)
		var out := ConcavePolygonShape3D.new()
		out.set_faces(faces)
		var err := ResourceSaver.save(out, OUT + file + ".res")
		print("%s: %d triangles (%s)" % [file, faces.size() / 3, error_string(err)])
	quit()
