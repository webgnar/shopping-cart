class_name DebugConsole
extends CanvasLayer
## In-game debug console, loaded as the `Console` autoload so it works in every level.
## The ` / ~ key opens and closes it; type `help` for the commands. While it is open the game is
## paused and the mouse is free. Up / Down step through earlier commands, Esc closes it.
##
## Layout lives in scenes/ui/console.tscn. The fast-travel destinations are the `destinations`
## export on its root node: each key is a command, each value the level scene it loads.

@export var destinations: Dictionary[String, String] = {}
@export var toggle_key: Key = KEY_QUOTELEFT   ## physical key that opens the console (` / ~)

@onready var _output: RichTextLabel = %Output
@onready var _entry: LineEdit = %Input

var _commands := {}          ## name -> {"run": Callable(args: PackedStringArray), "help": String}
var _history: PackedStringArray = []
var _history_pos := 0
var _was_paused := false
var _mouse_mode := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	_add_command("help", _cmd_help, "list the commands")
	_add_command("clear", func(_a): _output.clear(), "clear this window")
	_add_command("where", _cmd_where, "show which level is loaded")
	for place in destinations:
		_add_command(place, _travel.bind(place), "fast travel to %s" % destinations[place].get_file())
	log_line("[color=#8a93a6]Console ready. Type [b]help[/b] for commands.[/color]")


func _add_command(name: String, run: Callable, help: String) -> void:
	_commands[name] = {"run": run, "help": help}


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_entry.clear()
	_entry.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_entry.release_focus()
	get_tree().paused = _was_paused
	Input.mouse_mode = _mouse_mode


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.physical_keycode == toggle_key:
		if not key.echo:
			toggle()
		get_viewport().set_input_as_handled()   # keeps the ` out of the text box
	elif visible and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif visible and key.keycode in [KEY_UP, KEY_DOWN] and not _history.is_empty():
		_history_pos = clampi(_history_pos + (-1 if key.keycode == KEY_UP else 1), 0, _history.size())
		_entry.text = _history[_history_pos] if _history_pos < _history.size() else ""
		_entry.caret_column = _entry.text.length()
		get_viewport().set_input_as_handled()


## Connected in the scene to the text box's `text_submitted`.
func _on_input_submitted(text: String) -> void:
	_entry.clear()
	run_command(text)


## Runs one line as if it had been typed. Returns false for an empty or unknown command.
func run_command(line: String) -> bool:
	var words := line.strip_edges().split(" ", false)
	if words.is_empty():
		return false
	if _history.is_empty() or _history[-1] != line.strip_edges():
		_history.append(line.strip_edges())
	_history_pos = _history.size()
	log_line("[color=#6fd08c]>[/color] " + line.strip_edges())
	var name := words[0].to_lower()
	if not _commands.has(name):
		log_line("[color=#ff8a7a]Unknown command '%s'. Type help for the list.[/color]" % name)
		return false
	_commands[name].run.call(words.slice(1))
	return true


func log_line(bbcode: String) -> void:
	_output.append_text(bbcode + "\n")
	print_rich(bbcode)


func _cmd_help(_args: PackedStringArray) -> void:
	var names := _commands.keys()
	var width := 0
	for n in names:
		width = maxi(width, n.length())
	log_line("Commands:")
	for n in names:
		log_line("  [b]%s[/b]%s  %s" % [n, " ".repeat(width - n.length()), _commands[n].help])


func _cmd_where(_args: PackedStringArray) -> void:
	var scene := get_tree().current_scene
	log_line("Loaded: %s" % (scene.scene_file_path if scene else "nothing"))


func _travel(_args: PackedStringArray, place: String) -> void:
	var path: String = destinations[place]
	if not ResourceLoader.exists(path):
		log_line("[color=#ffc66d]Can't travel to %s yet: %s isn't in the project.[/color]" % [place, path])
		return
	log_line("Travelling to %s..." % place)
	close()
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		log_line("[color=#ff8a7a]Couldn't load %s (error %d).[/color]" % [path, err])
