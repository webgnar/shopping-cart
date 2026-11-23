extends Node3D
## The parking lot lab (scenes/lot_gen/lot_lab.tscn, console `lotlab`): the LotGenerator with its settings on a
## panel. Every change rebuilds the lot at once (flat asphalt, painted stripe meshes), and the panel lists the
## sizes it used, next to Table 1 of References/Levels/c620content.pdf. The view is from straight above, or in 3D:
## drag to orbit, wheel to zoom, either way.

const FT := 0.3048
const ANGLES := [90, 60, 45, 30]           ## the Angle list's items, in order

@export var generator: LotGenerator
@export var pivot: Node3D                   ## the camera orbits this, at the middle of the lot
@export var camera: Camera3D
@export var settings_panel: Control         ## the top view fits the lot between these two
@export var stats_panel: Control
@export var top_view_height := 120.0        ## m above the lot for the top view
@export var orbit_speed := 0.006            ## radians per pixel dragged

@onready var _angle: OptionButton = %Angle
@onready var _two_way: CheckBox = %TwoWay
@onready var _width: SpinBox = %LotWidth
@onready var _depth: SpinBox = %LotDepth
@onready var _islands: CheckBox = %Islands
@onready var _island_length: SpinBox = %IslandLength
@onready var _stops: CheckBox = %WheelStops
@onready var _perimeter: CheckBox = %Perimeter
@onready var _corrals: SpinBox = %Corrals
@onready var _seed: SpinBox = %Seed
@onready var _top: CheckBox = %TopView
@onready var _stats: Label = %Stats

var _queued := false
var _dragging := false
var _distance := 70.0


func _ready() -> void:
	# The panel starts from the generator's own settings.
	_angle.select(ANGLES.find(generator.stall_angle))
	_two_way.button_pressed = generator.two_way
	_width.value = generator.size.x
	_depth.value = generator.size.y
	_islands.button_pressed = generator.end_islands
	_island_length.value = generator.island_length
	_stops.button_pressed = generator.wheel_stops
	_perimeter.button_pressed = generator.perimeter_curb
	_corrals.value = generator.corrals
	_seed.value = generator.seed
	for r: Range in [_width, _depth, _island_length, _corrals, _seed]:
		r.value_changed.connect(func(_v: float) -> void: _queue())
	for b: BaseButton in [_two_way, _islands, _stops, _perimeter]:
		b.toggled.connect(func(_on: bool) -> void: _queue())
	_angle.item_selected.connect(func(_i: int) -> void: _queue())
	_top.toggled.connect(func(_on: bool) -> void: _place_camera())
	_rebuild()


func _queue() -> void:
	if not _queued:
		_queued = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	generator.stall_angle = ANGLES[_angle.selected]
	generator.two_way = _two_way.button_pressed
	generator.size = Vector2(_width.value, _depth.value)
	generator.end_islands = _islands.button_pressed
	generator.island_length = _island_length.value
	generator.wheel_stops = _stops.button_pressed
	generator.perimeter_curb = _perimeter.button_pressed
	generator.corrals = int(_corrals.value)
	generator.seed = int(_seed.value)
	generator.generate()
	pivot.position = Vector3(generator.size.x * 0.5, 0.0, 0.0)
	_place_camera()
	_show_stats()


func _show_stats() -> void:
	var g := generator
	var a := deg_to_rad(g.stall_angle)
	var d := g.stall_depth()
	var e := g.aisle_width()
	var c := g.stall_width / sin(a)
	var aisles := maxi(1, int(g.size.y / (2.0 * d + e)))
	var lines := PackedStringArray([
		"%d stalls (%d corrals)" % [g.stall_count, mini(g.corrals, g.stall_count)],
		"%d aisles, %d double rows, 2 single rows" % [aisles, aisles - 1],
		"",
		"Table 1, %d deg        lot    (table)" % g.stall_angle,
		"stall width B       %5.1f ft (8.5)" % (g.stall_width / FT),
		"along aisle C       %5.1f ft (%s)" % [c / FT, {90: "8.5", 60: "9.8", 45: "12", 30: "17"}[g.stall_angle]],
		"stall depth D       %5.1f ft (%s)" % [d / FT, {90: "18", 60: "19.8", 45: "18.7", 30: "16.4"}[g.stall_angle]],
		"stripe length G     %5.1f ft (%s)" % [d / sin(a) / FT, {90: "18", 60: "22.9", 45: "26.5", 30: "32.7"}[g.stall_angle]],
		"aisle E             %5.1f ft (%s)" % [e / FT, "24 two-way" if g.two_way else "%d one-way" % LotGenerator.ONE_WAY_AISLE_FT[g.stall_angle]],
		"bay (row+aisle+row) %5.1f ft" % ((2.0 * d + e) / FT),
	])
	_stats.text = "\n".join(lines)


func _place_camera() -> void:
	if _top.button_pressed:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		# Fit the lot in the gap between the panels (an orthogonal camera's size is the view's height in metres).
		var view := get_viewport().get_visible_rect().size
		var left := settings_panel.get_global_rect().end.x
		var right := view.x - stats_panel.get_global_rect().position.x
		var gap := maxf(view.x - left - right, 100.0)
		camera.size = maxf(generator.size.y, generator.size.x * view.y / gap) * 1.12
		camera.h_offset = (right - left) * 0.5 * camera.size / view.y
		pivot.rotation = Vector3.ZERO
		camera.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, top_view_height, 0.0))
	else:
		if pivot.rotation.x > -0.05:
			pivot.rotation = Vector3(-0.75, -0.6, 0.0)   # coming back from the top view
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.h_offset = 0.0
		camera.transform = Transform3D.IDENTITY
		camera.position = Vector3(0.0, 0.0, _distance)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var f := 0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
			if _top.button_pressed:
				camera.size = clampf(camera.size * f, 5.0, 400.0)
			else:
				_distance = clampf(_distance * f, 3.0, 300.0)
				camera.position = Vector3(0.0, 0.0, _distance)
	elif event is InputEventMouseMotion and _dragging and not _top.button_pressed:
		var m := event as InputEventMouseMotion
		pivot.rotation.y -= m.relative.x * orbit_speed
		pivot.rotation.x = clampf(pivot.rotation.x - m.relative.y * orbit_speed, -PI * 0.49, -0.05)
	elif event is InputEventMouseMotion and _dragging and _top.button_pressed:
		var m := event as InputEventMouseMotion
		var per_px := camera.size / float(get_viewport().get_visible_rect().size.y)
		pivot.position -= Vector3(m.relative.x, 0.0, m.relative.y) * per_px
