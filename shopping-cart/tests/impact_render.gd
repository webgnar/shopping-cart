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


var scrape_log := []   ## [s, loop file, volume dB, pitch] per tick per scraping part, since the last save


func _log_scrapes(cart: ShoppingCart, s: ImpactSynth) -> void:
	for body in [cart.frame, cart.gate, cart.child_seat, cart.seat_flap]:
		var cs: ContactSound = body.get_node_or_null("ContactSound")
		if cs and cs.scrape_player.playing and cs.scrape_player.stream:
			scrape_log.append([s.captured.size() / 24000.0, ProjectSettings.globalize_path(cs.scrape_player.stream.resource_path),
				cs.scrape_player.volume_db, cs.scrape_player.pitch_scale])


func _save(s: ImpactSynth, name: String, all: PackedFloat32Array) -> void:
	s.captured_wav().save_to_wav(out.path_join(name + ".wav"))
	# The recordings played for the same hits, for mixing in (seconds, clip files, volume dB).
	var log := []
	for r in s.recordings:
		var files := []
		if r[1] is AudioStreamRandomizer:
			for i in r[1].streams_count:
				files.append(ProjectSettings.globalize_path(r[1].get_stream(i).resource_path))
		else:
			files.append(ProjectSettings.globalize_path(r[1].resource_path))
		log.append({"t": r[0] / 24000.0, "files": files, "db": r[2]})
	var f := FileAccess.open(out.path_join(name + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"hits": log, "scrapes": scrape_log}))
	scrape_log = []
	f.close()
	s.recordings.clear()
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

	# Tipped over to the left and to the right: different parts of the frame land first.
	for side in [["tip_left", 1.0], ["tip_right", -1.0]]:
		var s := await _spawn(level, spawn, 0.0)
		await _wait(1.0)
		s.captured.clear()
		s.recordings.clear()
		Input.action_press("push_left")
		Input.action_press("push_right")
		await _wait(0.6)
		Input.action_release("push_left")
		Input.action_release("push_right")
		var cart: ShoppingCart = level.cart
		cart.frame.apply_torque_impulse(cart.frame.global_transform.basis.x * 40.0 * side[1])
		for i in 360:
			await physics_frame
			_log_scrapes(cart, s)
		await _save(s, side[0], all)

	# Tipped over, then dragged along on its side at a walking pace (about 1.4 m/s), then let go: it slides to a
	# stop. The tip is part of the recording; the drag holds the pace (a hand pulling), not a set force.
	var sd := await _spawn(level, spawn, 0.0)
	await _wait(1.0)
	var dc: ShoppingCart = level.cart
	sd.captured.clear()
	sd.recordings.clear()
	scrape_log = []
	Input.action_press("push_left")
	Input.action_press("push_right")
	await _wait(0.3)
	Input.action_release("push_left")
	Input.action_release("push_right")
	dc.frame.apply_torque_impulse(dc.frame.global_transform.basis.x * 40.0)   # just enough to fall onto its side
	for i in 180:
		await physics_frame
		_log_scrapes(dc, sd)
	var pull := -dc.frame.global_transform.basis.x.slide(Vector3.UP).normalized()
	for i in 480:
		if i < 360:
			var short := 1.4 * minf(1.0, i / 90.0) - dc.frame.linear_velocity.dot(pull)
			dc.frame.apply_central_force(pull * clampf(short * 400.0, 0.0, 300.0))
		await physics_frame
		_log_scrapes(dc, sd)
	await _save(sd, "drag_on_side", all)

	# The same knock (10 N s at 2 m/s on the frame) at five spots: where a hit lands changes what rings.
	var s0 := await _spawn(level, spawn, 0.0)
	await _wait(1.0)
	for spot in [["knock_handle", Vector3(0, 1.0, 0.2)], ["knock_basket_corner", Vector3(0.95, 0.95, 0.3)],
			["knock_basket_side", Vector3(0.55, 0.7, 0.31)], ["knock_basket_floor", Vector3(0.57, 0.46, 0.05)],
			["knock_chassis", Vector3(0.3, 0.15, 0.0)]]:
		s0.captured.clear()
		s0.recordings.clear()
		s0.strikes = 0
		s0.peak = 0.0
		s0.strike(ImpactSynth.Source.FRAME, 2.0, 10.0, 0.0004, spot[1])
		await _wait(1.2)
		await _save(s0, spot[0], all)
	level.queue_free()
	await _wait(0.2)

	# The same 20 cm drop on the supermarket's tile: harder floor, shorter contact, brighter.
	var market: Node3D = load("res://scenes/levels/supermarket.tscn").instantiate()
	root.add_child(market)
	await _wait(0.3)
	var s1 := await _spawn(market, market.get_node("CartSpawn"), 0.20)
	await _wait(1.5)
	await _save(s1, "drop_20cm_tile", all)

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
