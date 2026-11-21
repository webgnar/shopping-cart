@tool
extends Node3D
## Puts a backdrop into the level if its files are on this computer, and does nothing if they aren't.
## For content kept out of git, like the Manhattan skyline baked from zack's Google Earth tiles
## (`assets/manhattan_skyline/`, made by `tools/manhattan_skyline.sh`): the level opens and plays
## the same on a fresh clone, just without it.

## The backdrop scene, instanced as a child of this node when the file exists.
@export_file("*.tscn") var scene_path: String = ""
## An equirectangular panorama (transparent sky) handed to the sky shader's `skyline` when it exists.
@export_file var panorama_path: String = ""
## The level's WorldEnvironment, whose sky uses `scenes/environment/skyline_sky.gdshader`.
@export var world_environment: WorldEnvironment


func _ready() -> void:
	# In the editor too, so the level shows its backdrop; children added here have no owner, so they
	# are never saved into the level.
	if scene_path != "" and ResourceLoader.exists(scene_path):
		add_child((load(scene_path) as PackedScene).instantiate())
	# The sky only in the game: set in the editor it would be saved into the level's environment.
	if Engine.is_editor_hint():
		return
	if panorama_path != "" and ResourceLoader.exists(panorama_path) and world_environment != null:
		var sky_material := world_environment.environment.sky.sky_material as ShaderMaterial
		if sky_material != null:
			sky_material.set_shader_parameter("skyline", load(panorama_path))
