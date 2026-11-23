extends Control
## The 2D asphalt lab (scenes/asphalt/asphalt_lab.tscn): scrub or play the years, try repairs, change the
## conditions, and watch the colour and height maps of the road section. Everything here is UI wiring; the
## simulation is AsphaltSim and the drawing is AsphaltCanvas.

@export var sim: AsphaltSim
@export var color_view: Control
@export var height_view: Control
@export var relief_view: TextureRect        ## AsphaltSim.bake_height in metres, shaded as if lit from the top left
@export var relief_res := 0.02               ## m per relief pixel
@export var relief_exaggeration := 6.0       ## slopes are shaded this many times steeper than they are
@export var preview_view: TextureRect        ## the 3D preview: the road displaced by the real height map
@export var preview_road: MeshInstance3D
@export var preview_pivot: Node3D            ## drag on the preview to orbit it, wheel to zoom
@export var preview_camera: Camera3D
@export var preview_res := 0.01              ## m per height-map pixel in the 3D preview
@export var max_years := 40.0
@export var years_per_second := 2.0

var playing := false
var _dragging := false
var _play_t := 0.0     ## years: where Play has got to (the sim catches up a step at a time)
var _epoch := 0.0      ## road year the timeline starts at ("Start timeline here"); it runs max_years on from it
var _replay_at := -1   ## msec: replay once the condition sliders settle
var _relief_at := -1   ## msec: redraw the relief view (it takes a moment, so not every frame)

@onready var _year: Label = %YearLabel
@onready var _timeline: HSlider = %Timeline
@onready var _play: Button = %PlayButton
@onready var _stats: Label = %Stats
@onready var _history: Label = %History
@onready var _start_here: Button = %StartHere
@onready var _repairs: Array[CheckBox] = [%Repair0, %Repair1, %Repair2, %Repair3, %Repair4]   ## by AsphaltSim.Action
@onready var _seed: SpinBox = %Seed


func _ready() -> void:
	_timeline.max_value = max_years
	for r in _repairs:
		r.set_meta("name", r.text)
	_seed.set_value_no_signal(sim.seed)
	for slider: Range in get_tree().get_nodes_in_group("asphalt_condition"):
		slider.set_value_no_signal(sim.get(slider.get_meta("property")))
		_label_condition(slider)
	sim.changed.connect(_update_ui)
	sim.changed.connect(_queue_relief)
	_update_ui()


func _process(delta: float) -> void:
	if _replay_at >= 0 and Time.get_ticks_msec() >= _replay_at:
		_replay_at = -1
		_replay()
	if _relief_at >= 0 and Time.get_ticks_msec() >= _relief_at:
		_relief_at = -1
		if relief_view.visible:
			draw_relief()
		if preview_view.visible:
			draw_preview()
	if not playing:
		return
	# Keep our own clock: one frame is far less than a simulation step, so adding a frame to sim.time each time
	# would never reach the next step.
	if absf(_play_t - sim.time) > AsphaltSim.DT:
		_play_t = sim.time   # scrubbed or replayed while playing
	_play_t = minf(_play_t + years_per_second * delta, _epoch + max_years)
	sim.advance_to(_play_t)
	if _play_t >= _epoch + max_years:
		_play.button_pressed = false


func _update_ui() -> void:
	_timeline.set_value_no_signal(sim.time - _epoch)
	for a in _repairs.size():
		var at := sim.repair_year(a)
		_repairs[a].set_pressed_no_signal(at >= 0.0)
		_repairs[a].text = _repairs[a].get_meta("name") + ("  (year %.1f)" % at if at >= 0.0 else "")
	var s := sim.stats()
	_year.text = _year_text(sim.time - _epoch)
	var kinds := PackedStringArray()
	for k in AsphaltSim.Kind.size():
		if s.by_kind[k] > 0.05:
			kinds.append("  %s %.1f m" % [AsphaltSim.KIND_NAMES[k], s.by_kind[k]])
	_stats.text = "Surface: %.1f years old\nCondition index: %.0f / 100\nOpen cracks: %.0f m (%.0f m wider than 3 mm)\n%s\nFatigue cells: %.1f %% of the road\nPotholes: %d (%.1f %%)\nFilled %.1f %%, patched %.1f %%" % [
		s.surface_age, s.pci, s.crack_m, s.wide_crack_m, "\n".join(kinds), s.alligator_pct,
		s.potholes, s.pothole_pct, s.filled_pct, s.patched_pct]
	var lines := sim.log_lines
	_history.text = "\n".join(lines.slice(maxi(0, lines.size() - 8))) if lines.size() > 0 else "No repairs yet."


func _replay() -> void:
	var t := sim.time
	sim.reset()
	sim.advance_to(t)


func _label_condition(slider: Range) -> void:
	var label := slider.get_parent().get_node_or_null("Value") as Label
	if label:
		label.text = "%.2f" % slider.value


func _on_timeline_value_changed(value: float) -> void:
	_year.text = _year_text(value)
	if not _dragging:
		sim.seek(_epoch + value)


func _on_timeline_drag_started() -> void:
	_dragging = true


func _on_timeline_drag_ended(_changed: bool) -> void:
	_dragging = false
	sim.seek(_epoch + _timeline.value)


func _on_play_toggled(on: bool) -> void:
	playing = on
	_play.text = "Pause" if on else "Play"
	if on and sim.time >= _epoch + max_years - 0.01:
		sim.seek(_epoch)
	_play_t = sim.time


## The slider counts years from where the timeline starts.
func _year_text(value: float) -> String:
	return "Year %.1f" % value if _epoch <= 0.0 else "Year %.1f (road year %.1f)" % [value, _epoch + value]


## Pressed: the timeline starts at this year and runs max_years on, to age the road (and its repairs) further.
## Released: back to the road's own years.
func _on_start_here_toggled(on: bool) -> void:
	_epoch = sim.time if on else 0.0
	_start_here.text = "Timeline starts at road year %.1f" % _epoch if on else "Start timeline here"
	_update_ui()


## Ticked: that repair is done at the slider's year. Unticked: it never happened.
func _on_repair_toggled(on: bool, action: int) -> void:
	sim.set_repair(action, on, sim.time)


func _on_condition_changed(value: float, property: String) -> void:
	sim.set(property, value)
	for slider: Range in get_tree().get_nodes_in_group("asphalt_condition"):
		_label_condition(slider)
	_replay_at = Time.get_ticks_msec() + 250


func _on_seed_changed(value: float) -> void:
	sim.seed = int(value)
	_replay()


func _on_view_selected(index: int) -> void:
	color_view.visible = index != 1
	height_view.visible = index == 1 or index == 2
	relief_view.visible = index == 3
	preview_view.visible = index == 4
	_queue_relief()


func _queue_relief() -> void:
	if (relief_view.visible or preview_view.visible) and _relief_at < 0:
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
