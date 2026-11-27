extends Control
## The 2D asphalt lab (scenes/asphalt/asphalt_lab.tscn): scrub or play the years, set the pavement section it is
## built on, and watch the colour and height maps of the road section. Everything here is UI wiring; the
## simulation is AsphaltSim and the drawing is AsphaltCanvas.

@export var sim: AsphaltSim
@export var color_view: Control
@export var height_view: Control
@export var relief_view: TextureRect        ## AsphaltSim.bake_height in metres, shaded as if lit from the top left
@export var relief_res := 0.02               ## m per relief pixel
@export var relief_exaggeration := 6.0       ## slopes are shaded this many times steeper than they are
@export var preview_view: TextureRect        ## the 3D preview: the road displaced by the real height map
@export var section_view: CrossSectionCanvas  ## the cross-section across the road; click or drag on the plan to move it
@export var map_view: DistressMapCanvas      ## the LTPP distress map of both lanes, with the data sheet totals
@export var preview_road: MeshInstance3D
@export var preview_pivot: Node3D            ## drag on the preview to orbit it, wheel to zoom
@export var preview_camera: Camera3D
@export var preview_res := 0.01              ## m per height-map pixel in the 3D preview
@export var max_years := 30.0
@export var years_per_second := 2.0

var playing := false
var _dragging := false
var _play_t := 0.0     ## years: where Play has got to (the sim catches up a step at a time)
var _relief_at := -1   ## msec: redraw the relief view (it takes a moment, so not every frame)
var _rebuild_at := -1  ## msec: rebuild the road once the build-up spin boxes settle

@onready var _year: Label = %YearLabel
@onready var _timeline: HSlider = %Timeline
@onready var _play: Button = %PlayButton
@onready var _stats: Label = %Stats
@onready var _seed: SpinBox = %Seed
@onready var _section_info: Label = %SectionInfo
@onready var _asphalt_mm: SpinBox = %AsphaltMM
@onready var _base_mm: SpinBox = %BaseMM
@onready var _cbr: SpinBox = %Cbr


func _ready() -> void:
	_timeline.max_value = max_years
	_seed.set_value_no_signal(sim.seed)
	# The spin boxes show the build-up the sim starts with.
	var b := sim.pavement()
	_asphalt_mm.set_value_no_signal(b.asphalt_thickness() * 1000.0)
	_base_mm.set_value_no_signal(b.base().thickness * 1000.0 if b.base() else 0.0)
	_cbr.set_value_no_signal(b.subgrade_cbr)
	_show_section()
	sim.changed.connect(_update_ui)
	sim.changed.connect(_queue_relief)
	_update_ui()


func _process(delta: float) -> void:
	if _rebuild_at >= 0 and Time.get_ticks_msec() >= _rebuild_at:
		_rebuild_at = -1
		_replay()
	if _relief_at >= 0 and Time.get_ticks_msec() >= _relief_at:
		_relief_at = -1
		if relief_view.visible:
			draw_relief()
		if preview_view.visible:
			draw_preview()
		if section_view.visible:
			section_view.refresh()
		if map_view.visible:
			map_view.refresh()
	if not playing:
		return
	# Keep our own clock: one frame is far less than a simulation step, so adding a frame to sim.time each time
	# would never reach the next step.
	if absf(_play_t - sim.time) > AsphaltSim.DT:
		_play_t = sim.time   # scrubbed or replayed while playing
	_play_t = minf(_play_t + years_per_second * delta, max_years)
	sim.advance_to(_play_t)
	if _play_t >= max_years:
		_play.button_pressed = false


func _update_ui() -> void:
	_timeline.set_value_no_signal(sim.time)
	_year.text = "Year %.1f" % sim.time
	if not sim.placeholders:
		_stats.text = "Surface %.1f years old.\nSimulated so far: the structure (layers, slip length, wheel spread). No time-driven model is sourced yet, so the road does not age; see docs/ASPHALT_SCIENCE.md." % sim.surface_age()
		return
	var s := sim.stats()
	_stats.text = "Placeholder models on (not sourced).\nSurface %.1f years old, open cracks %.0f m." % [s.surface_age, s.crack_m]


func _replay() -> void:
	var t := sim.time
	sim.reset()
	sim.advance_to(t)


## The pavement section the road is built on, layer by layer with its sources (read-only: only vetted inputs).
func _show_section() -> void:
	var b := sim.pavement()
	var lines := PackedStringArray([b.title])
	for l in b.layers:
		lines.append("  %s: %.0f mm (%.1f in)" % [l.title, l.thickness * 1000.0, l.thickness / 0.0254])
	lines.append("  Subgrade: CBR %.0f" % b.subgrade_cbr)
	lines.append("Slip length %.2f m (Li & Marasteanu 2005), wheel spread %.2f m (Westergaard)." % [sim.slip_length(), sim.wheel_spread()])
	lines.append("Sources: " + b.source)
	_section_info.text = "\n".join(lines)


func _on_timeline_value_changed(value: float) -> void:
	_year.text = "Year %.1f" % value
	if not _dragging:
		sim.seek(value)


func _on_timeline_drag_started() -> void:
	_dragging = true


func _on_timeline_drag_ended(_changed: bool) -> void:
	_dragging = false
	sim.seek(_timeline.value)


func _on_play_toggled(on: bool) -> void:
	playing = on
	_play.text = "Pause" if on else "Play"
	if on and sim.time >= max_years - 0.01:
		sim.seek(0.0)
	_play_t = sim.time


## A build-up spin box changed: the road is rebuilt on a copy of the build-up with the new asphalt and base thicknesses
## and subgrade CBR, from year 0 (a moment after the last change). The asphalt box sets the top (only) asphalt layer.
func _on_buildup_changed(_value: float) -> void:
	if sim.buildup == null or sim.buildup.resource_path != "":   # the shared preset: edit a copy
		sim.buildup = sim.pavement().duplicate(true)
		sim.buildup.title = "Edited from " + sim.pavement().title
	var b := sim.buildup
	b.layers[0].thickness = _asphalt_mm.value / 1000.0
	if b.base():
		b.base().thickness = _base_mm.value / 1000.0
	b.subgrade_cbr = _cbr.value
	_show_section()
	_rebuild_at = Time.get_ticks_msec() + 300


func _on_seed_changed(value: float) -> void:
	sim.seed = int(value)
	_replay()


func _on_view_selected(index: int) -> void:
	color_view.visible = index != 1
	height_view.visible = index == 1 or index == 2
	relief_view.visible = index == 3
	preview_view.visible = index == 4
	section_view.visible = index == 5
	map_view.visible = index == 6
	color_view.get_parent().visible = index != 6
	color_view.queue_redraw()
	_queue_relief()


func _queue_relief() -> void:
	if (relief_view.visible or preview_view.visible or section_view.visible or map_view.visible) and _relief_at < 0:
		_relief_at = Time.get_ticks_msec() + (400 if playing else 50)


## Shades the sim's real height map: slopes facing the light are bright, holes and cracks dark.
func draw_relief() -> void:
	var hmap := sim.bake_height(relief_res)
	var w := int(round(sim.size.x / relief_res)) + 1
	var h := int(round(sim.size.y / relief_res)) + 1
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	var k := relief_exaggeration / relief_res
	var light := Vector3(-1.0, -1.0, 1.2).normalized()
	for y in h:
		for x in w:
			var i := y * w + x
			var z := hmap[i]
			var dx := z - hmap[i - 1] if x > 0 else 0.0
			var dy := z - hmap[i - w] if y > 0 else 0.0
			var n := Vector3(-dx * k, -dy * k, 1.0).normalized()
			var lit := 0.15 + 0.75 * maxf(n.dot(light), 0.0) + z * 3.0
			bytes[i] = int(clampf(lit, 0.0, 1.0) * 255.0)
	relief_view.texture = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_L8, bytes))


## Hands the sim's height map (metres) and colour map to the 3D preview's road material.
func draw_preview() -> void:
	var hmap := sim.bake_height(preview_res)
	var w := int(round(sim.size.x / preview_res)) + 1
	var h := int(round(sim.size.y / preview_res)) + 1
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, hmap.to_byte_array())
	var mat := preview_road.get_surface_override_material(0) as ShaderMaterial
	mat.set_shader_parameter("height_map", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("height_texel", Vector2(1.0 / (w - 1), 1.0 / (h - 1)))
	mat.set_shader_parameter("size_m", sim.size)
	# A copy of the colour map rather than the viewport itself: it is decoded from sRGB the same way on every renderer.
	var color: Image = color_view.texture.get_image()
	color.generate_mipmaps()
	mat.set_shader_parameter("albedo_map", ImageTexture.create_from_image(color))


## With the section shown, clicking or dragging on the plan moves the cut.
func _on_plan_input(event: InputEvent) -> void:
	if not section_view.visible:
		return
	var press: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var drag: bool = event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT
	if press or drag:
		var y := section_view.plan_to_y(event.position)
		if y >= 0.0:
			section_view.set_cut(y)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		preview_pivot.rotate_y(-event.relative.x * 0.006)
		var cam := preview_camera.transform
		var a := clampf(atan2(cam.origin.y, cam.origin.z) + event.relative.y * 0.004, 0.08, 1.45)
		var d := cam.origin.length()
		preview_camera.position = Vector3(0.0, sin(a), cos(a)) * d
		preview_camera.look_at(preview_pivot.global_position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var k := 0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
			preview_camera.position = preview_camera.position * k
			preview_camera.position = preview_camera.position.limit_length(14.0)
