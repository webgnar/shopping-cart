class_name AsphaltSection
extends Node3D
## A piece of simulated asphalt in 3D (scenes/asphalt/asphalt_section.tscn), centred on its origin. Its AsphaltSim
## is aged to `year`, drawn once into ColorViewport, and shown on Surface displaced by the sim's height map. The
## same heights go into a HeightMapShape3D, so wheels drop into the cracks, ruts and potholes.

@export var sim: AsphaltSim
@export var color_viewport: SubViewport
@export var surface: MeshInstance3D
@export var collision: CollisionShape3D       ## a HeightMapShape3D; one sample per height_res, scaled to fit
@export var seed := 1
@export var year := 20.0
@export var height_res := 0.02                ## m between height samples (collision and displacement)


func _ready() -> void:
	sim.seed = seed
	sim.reset()
	sim.seek(year)
	var hmap := sim.bake_height(height_res)
	var w := int(round(sim.size.x / height_res)) + 1
	var h := int(round(sim.size.y / height_res)) + 1
	# Collision: the shape is one unit per sample, so it is scaled by height_res and the heights divided by it.
	var shape := collision.shape as HeightMapShape3D
	var scaled := PackedFloat32Array(hmap)
	for i in scaled.size():
		scaled[i] /= height_res
	shape.map_width = w
	shape.map_depth = h
	shape.map_data = scaled
	collision.scale = Vector3.ONE * height_res
	var mat := surface.get_surface_override_material(0) as ShaderMaterial
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, hmap.to_byte_array())
	mat.set_shader_parameter("height_map", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("height_texel", Vector2(1.0 / (w - 1), 1.0 / (h - 1)))
	mat.set_shader_parameter("size_m", sim.size)
	# The colour map is drawn once; keep a copy and drop the viewport.
	await RenderingServer.frame_post_draw
	var color: Image = color_viewport.get_texture().get_image()
	color.generate_mipmaps()
	mat.set_shader_parameter("albedo_map", ImageTexture.create_from_image(color))
	color_viewport.queue_free()
