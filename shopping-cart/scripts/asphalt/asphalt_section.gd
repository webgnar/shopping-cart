class_name AsphaltSection
extends Node3D
## A piece of simulated asphalt in 3D (scenes/asphalt/asphalt_section.tscn), centred on its origin. Its AsphaltSim
## is aged to `year`, drawn once into ColorViewport, and shown on Surface displaced by the sim's height map. The
## same heights go into a HeightMapShape3D, so wheels drop into the cracks, ruts and potholes.
## Simulating takes up to a few seconds a section, so a level can bake its sections once
## (tools/bake_asphalt_sections_cli.gd): with color_map and height_map set, the section loads those instead.

@export var sim: AsphaltSim
@export var color_viewport: SubViewport
@export var surface: MeshInstance3D
@export var collision: CollisionShape3D       ## a HeightMapShape3D; one sample per height_res, scaled to fit
@export var seed := 1
@export var year := 20.0
@export var road_crew := false               ## the crew repairs it as it ages (AsphaltSim.auto_maintain)
@export var height_res := 0.02                ## m between height samples (collision and displacement)

@export_group("Baked")
@export var color_map: Texture2D              ## the colour map, baked; with height_map set, no simulation runs
@export var height_map: Image                 ## heights in metres (FORMAT_RF), one pixel per height_res

var color_image: Image                        ## what this section shows, kept for baking
var height_image: Image


func _ready() -> void:
	var mat := surface.get_surface_override_material(0) as ShaderMaterial
	if color_map and height_map:
		color_viewport.queue_free()
		_set_heights(height_map, mat)
		mat.set_shader_parameter("albedo_map", color_map)
		return
	sim.seed = seed
	sim.auto_maintain = road_crew
	sim.reset()
	sim.seek(year)
	var w := int(round(sim.size.x / height_res)) + 1
	var h := int(round(sim.size.y / height_res)) + 1
	_set_heights(Image.create_from_data(w, h, false, Image.FORMAT_RF, sim.bake_height(height_res).to_byte_array()), mat)
	# The colour map is drawn once; keep a copy and drop the viewport.
	await RenderingServer.frame_post_draw
	color_image = color_viewport.get_texture().get_image()
	color_image.generate_mipmaps()
	mat.set_shader_parameter("albedo_map", ImageTexture.create_from_image(color_image))
	color_viewport.queue_free()


func _set_heights(img: Image, mat: ShaderMaterial) -> void:
	height_image = img
	var w := img.get_width()
	var h := img.get_height()
	# Collision: the shape is one unit per sample, so it is scaled by height_res and the heights divided by it.
	var shape := collision.shape as HeightMapShape3D
	var scaled := img.get_data().to_float32_array()
	for i in scaled.size():
		scaled[i] /= height_res
	shape.map_width = w
	shape.map_depth = h
	shape.map_data = scaled
	collision.scale = Vector3.ONE * height_res
	mat.set_shader_parameter("height_map", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("height_texel", Vector2(1.0 / (w - 1), 1.0 / (h - 1)))
	mat.set_shader_parameter("size_m", Vector2(w - 1, h - 1) * height_res)
