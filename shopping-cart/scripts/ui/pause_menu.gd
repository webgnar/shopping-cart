class_name PauseMenu
extends CanvasLayer
## The pause menu (Esc), loaded as the `Pause` autoload so it works in every level. It has a button for each
## console command (built from the console's own list every time it opens, so new commands show up by themselves),
## plus Resume and Quit. Places (the console's fast-travel destinations, race and sweep) go in the top grid, the
## rest under Commands. Layout lives in scenes/ui/pause_menu.tscn; buttons are copies of its ButtonTemplate.
##
## Esc closes the console or the multiplayer menu first when one of those is open. In a multiplayer game the menu
## opens without pausing, so the host's world keeps running for everyone else.

const ESC_KEY := KEY_ESCAPE

## Console commands left off the menu: ones that need typed words, or only print into the console.
@export var hidden_commands: PackedStringArray = ["help", "clear", "where", "net", "games", "join"]
## Console commands that go under Places as well as the fast-travel destinations.
@export var place_commands: PackedStringArray = ["race", "sweep"]
## Extra buttons for a command typed with words after it; each is run exactly as written.
@export var extra_commands: PackedStringArray = ["race downhill"]

@onready var _places: GridContainer = %Places
@onready var _commands: GridContainer = %Commands
@onready var _template: Button = %ButtonTemplate
var _was_paused := false
var _mouse_mode := Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_build_buttons()
	visible = true
	_was_paused = get_tree().paused
	if not _online():
		get_tree().paused = true
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()
	get_tree().paused = _was_paused
	Input.mouse_mode = _mouse_mode


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != ESC_KEY:
		return
	# The console and the multiplayer menu close themselves on Esc.
	var console := get_node_or_null("/root/Console")
	if console and console.is_open():
		return
	var mp_menu := get_node_or_null("/root/Net/Menu") as CanvasLayer
	if mp_menu and mp_menu.visible:
		return
	toggle()
	get_viewport().set_input_as_handled()


## True while hosting or in someone else's game: then the menu doesn't pause the tree.
func _online() -> bool:
	var net := get_node_or_null("/root/Net") as NetSession
	return net != null and net.role != NetSession.Role.OFFLINE


func _guest() -> bool:
	var net := get_node_or_null("/root/Net") as NetSession
	return net != null and net.is_guest()


func _build_buttons() -> void:
	for grid in [_places, _commands]:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	var console := get_node_or_null("/root/Console") as DebugConsole
	if console == null:
		return
	var lines: Array = []
	for name in console.command_names():
		if not name in hidden_commands:
			lines.append(name)
	lines.append_array(extra_commands)
	for line: String in lines:
		var name := line.split(" ")[0]
		var is_place := console.destinations.has(name) or name in place_commands
		var button := _template.duplicate() as Button
		button.unique_name_in_owner = false
		button.visible = true
		button.text = line
		button.tooltip_text = console.command_help(name)
		# Only the host picks the level in a multiplayer game.
		button.disabled = is_place and _guest()
		button.pressed.connect(_run.bind(line))
		(_places if is_place else _commands).add_child(button)


func _run(line: String) -> void:
	close()
	var console := get_node_or_null("/root/Console") as DebugConsole
	if console:
		console.run_command(line)


func _on_resume_pressed() -> void:
	close()


func _on_quit_pressed() -> void:
	get_tree().quit()
