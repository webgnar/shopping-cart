extends Control
## The 2D asphalt lab (scenes/asphalt/asphalt_lab.tscn): scrub or play the years, try repairs, change the
## conditions, and watch the colour and height maps of the road section. Everything here is UI wiring; the
## simulation is AsphaltSim and the drawing is AsphaltCanvas.

@export var sim: AsphaltSim
@export var color_view: Control
@export var height_view: Control
@export var max_years := 40.0
@export var years_per_second := 2.0

var playing := false
var _dragging := false
var _play_t := 0.0     ## years: where Play has got to (the sim catches up a step at a time)
var _replay_at := -1   ## msec: replay once the condition sliders settle

@onready var _year: Label = %YearLabel
@onready var _timeline: HSlider = %Timeline
@onready var _play: Button = %PlayButton
@onready var _stats: Label = %Stats
@onready var _history: Label = %History
@onready var _auto: CheckBox = %AutoMaintain
@onready var _seed: SpinBox = %Seed


func _ready() -> void:
	_timeline.max_value = max_years
	_auto.set_pressed_no_signal(sim.auto_maintain)
	_seed.set_value_no_signal(sim.seed)
	for slider: Range in get_tree().get_nodes_in_group("asphalt_condition"):
		slider.set_value_no_signal(sim.get(slider.get_meta("property")))
		_label_condition(slider)
	sim.changed.connect(_update_ui)
	_update_ui()


func _process(delta: float) -> void:
	if _replay_at >= 0 and Time.get_ticks_msec() >= _replay_at:
		_replay_at = -1
		_replay()
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
	var s := sim.stats()
	_year.text = "Year %.1f" % s.year
	var kinds := PackedStringArray()
	for k in AsphaltSim.Kind.size():
		if s.by_kind[k] > 0.05:
			kinds.append("  %s %.1f m" % [AsphaltSim.KIND_NAMES[k], s.by_kind[k]])
	var surface := "chip seal" if sim.surface_kind == AsphaltSim.Surface.CHIP_SEAL else "asphalt"
	_stats.text = "Surface: %s, %.1f years old\nCondition index: %.0f / 100\nOpen cracks: %.0f m (%.0f m wider than 3 mm)\n%s\nFatigue cells: %.1f %% of the road\nPotholes: %d (%.1f %%)\nFilled %.1f %%, patched %.1f %%" % [
		surface, s.surface_age, s.pci, s.crack_m, s.wide_crack_m, "\n".join(kinds), s.alligator_pct,
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


func _on_repair_pressed(action: int) -> void:
	sim.do_action(action)


func _on_clear_pressed() -> void:
	sim.clear_events()


func _on_auto_toggled(on: bool) -> void:
	sim.auto_maintain = on
	_replay()


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
	height_view.visible = index != 0
