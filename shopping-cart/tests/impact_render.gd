extends SceneTree
## Renders the cart's generated impact sound (scenes/cart/impact_synth.tscn) for a set of physics events, so it can
## be listened to: drops from several heights, a wheelie set down, a tip-over. Each is its own WAV, plus all.wav.
##   godot --headless --fixed-fps 120 -s res://tests/impact_render.gd -- <out dir>

var out := "user://impact_render"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _spawn(level: Node, spawn: Marker3D, lift: float) -> ImpactSynth:
	level.spawn_cart(spawn.global_position + Vector3(0, lift, 0), spawn.global_rotation.y)
	await process_frame
	var s: ImpactSynth = level.cart.frame.get_node("ImpactSynth")
	s.capture = true
	return s


func _save(s: ImpactSynth, name: String, all: PackedFloat32Array) -> void:
	s.captured_wav().save_to_wav(out.path_join(name + ".wav"))
	all.append_array(s.captured)
	var gap := PackedFloat32Array()
	gap.resize(12000)
	all.append_array(gap)
	print("%-18s %d strikes, peak %.2f, %.1f s" % [name, s.strikes, s.peak, s.captured.size() / 24000.0])


func _run() -> void:
	var level: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(level)
	await _wait(0.3)
	var spawn: Marker3D = level.get_node("CartSpawn")
	spawn.global_position += Vector3(0, 0, 10)   # open ground, clear of the test strip's carts
	var all := PackedFloat32Array()
	for h in [0.02, 0.05, 0.10, 0.20, 0.40]:
		var s := await _spawn(level, spawn, h)
		await _wait(1.5)
		await _save(s, "drop_%02dcm" % roundi(h * 100), all)

	var s := await _spawn(level, spawn, 0.0)
	await _wait(1.0)
	s.captured.clear()
	Input.action_press("push_left")
	Input.action_press("push_right")
	await _wait(0.6)
	Input.action_press("lean_front_up") if InputMap.has_action("lean_front_up") else null
	Input.action_release("push_left")
	Input.action_release("push_right")
	var cart: ShoppingCart = level.cart
	cart.frame.apply_torque_impulse(cart.frame.global_transform.basis.x * 80.0)
	await _wait(3.0)
	await _save(s, "tip_over", all)

	var wav := AudioStreamWAV.new()
	var data := PackedByteArray()
	data.resize(all.size() * 2)
	for i in all.size():
		data.encode_s16(i * 2, int(clampf(all[i], -1.0, 1.0) * 32767.0))
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 24000
	wav.data = data
	wav.save_to_wav(out.path_join("all.wav"))
	quit()
