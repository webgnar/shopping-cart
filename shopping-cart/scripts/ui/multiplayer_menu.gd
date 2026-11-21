class_name MultiplayerMenu
extends CanvasLayer
## The Multiplayer menu (M): host online with a join code, join by code or from the public game list, or play over
## the local network by address. Layout lives in scenes/ui/multiplayer_menu.tscn, which the Net autoload
## (scenes/net/net_session.tscn) instances, so it works in every level. The game keeps running while it is open.

@export var toggle_key: Key = KEY_M   ## physical key that opens and closes the menu

@onready var _net: NetSession = get_parent() as NetSession
@onready var _game_name: LineEdit = %GameName
@onready var _listed: CheckBox = %Listed
@onready var _code_row: Control = %CodeRow
@onready var _code: Label = %Code
@onready var _join_code: LineEdit = %JoinCode
@onready var _games: ItemList = %Games
@onready var _address: LineEdit = %Address
@onready var _status: RichTextLabel = %Status
@onready var _leave: Button = %LeaveButton
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var _last_message := ""


func _ready() -> void:
	_game_name.text = _net.game_name
	_listed.button_pressed = _net.listed
	_net.status_changed.connect(func(_t): _refresh_status())
	_net.message.connect(func(text: String):
		_last_message = text
		_refresh_status())
	_net.hosted_online.connect(func(_code_text): _refresh_status())
	_net.games_listed.connect(_show_games)
	_refresh_status()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var console := get_node_or_null("/root/Console")
	if console and console.is_open():
		return
	if key.physical_keycode == toggle_key and not _typing():
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func open() -> void:
	if visible:
		return
	visible = true
	_game_name.text = _net.game_name
	_listed.button_pressed = _net.listed
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_status()
	_on_refresh_pressed()


func close() -> void:
	if not visible:
		return
	visible = false
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()
	Input.mouse_mode = _mouse_mode


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _refresh_status() -> void:
	var online_host := _net.is_host() and _net.join_code != ""
	_code_row.visible = online_host
	if online_host:
		_code.text = NetSession.pretty_code(_net.join_code)
	_leave.disabled = _net.role == NetSession.Role.OFFLINE
	_status.text = _net.status_text() + ("\n" + _last_message if _last_message else "")


func _show_games(games: Array) -> void:
	_games.clear()
	for g in games:
		var i := _games.add_item("%s   ·   %s   ·   %d/%d players" % [g.name, g.level, g.players, g.max_players])
		_games.set_item_metadata(i, g.code)
	if games.is_empty():
		_games.add_item("No public games right now.")
		_games.set_item_disabled(0, true)


func _on_host_pressed() -> void:
	_net.game_name = _game_name.text.strip_edges() if _game_name.text.strip_edges() != "" else "Shopping cart"
	_net.listed = _listed.button_pressed
	_net.host_online()


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_code.text)
	_last_message = "Copied %s. Send it to your friend." % _code.text
	_refresh_status()


func _on_join_pressed() -> void:
	_on_join_code_submitted(_join_code.text)


func _on_join_code_submitted(text: String) -> void:
	if _net.join_online(text):
		_join_code.release_focus()


func _on_refresh_pressed() -> void:
	_net.list_games()


func _on_join_selected_pressed() -> void:
	var picked := _games.get_selected_items()
	if not picked.is_empty():
		_on_game_activated(picked[0])


func _on_game_activated(index: int) -> void:
	var code = _games.get_item_metadata(index)
	if code is String:
		_net.join_online(code)


func _on_join_lan_pressed() -> void:
	var text := _address.text.strip_edges()
	if text != "":
		_net._join_address(text)


func _on_host_lan_pressed() -> void:
	_net.host()


func _on_leave_pressed() -> void:
	_net.leave()
