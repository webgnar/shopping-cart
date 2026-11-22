extends SceneTree
## Sound bench test: picks up the cinder block, carries it over the cart, drops it in the basket and checks the cart
## heard the hit; then turns the cart with the arrows. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/sound_bench_test.gd

var bench: Node3D
var failures := 0


func _initialize() -> void:
	bench = load("res://scenes/sound_bench.tscn").instantiate()
	root.add_child(bench)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(name: String, ok: bool, info: String) -> void:
	print("%s %s: %s" % ["PASS" if ok else "FAIL", name, info])
	if not ok:
		failures += 1


func _run() -> void:
	await _wait(2.0)   # the cart comes to rest and is pinned
	var cart: ShoppingCart = bench.cart
	var block: RigidBody3D = bench.get_node("CinderBlock")
	var sound: ContactSound = cart.frame.get_node("ContactSound")
	_check("cart at rest", cart.frame.freeze, "frozen=%s" % cart.frame.freeze)

	# Lift the block by its top and carry it up and over the basket, slowly, like a person would.
	bench.grab(block, block.global_position + Vector3(0, 0.095, 0))
	var start: Vector3 = bench.hand
	var over := cart.frame.global_transform * Vector3(0.55, 1.3, 0)
	var ticks := int(1.5 * Engine.physics_ticks_per_second)
	for i in ticks:
		var t := float(i + 1) / ticks
		bench.hand = start.lerp(over, t) + Vector3(0, sin(t * PI) * 0.4, 0)
		await physics_frame
	await _wait(1.0)
	_check("block held up over the basket", block.global_position.distance_to(over + Vector3(0, -0.095, 0)) < 0.15,
		"block %s, hand %s" % [block.global_position, over])
	var hits0 := sound.hits
	bench.release()
	var loudest := 0.0
	for i in int(2.0 * Engine.physics_ticks_per_second):
		await physics_frame
		loudest = maxf(loudest, sound.last_hit)
	_check("block landed in the basket", cart.in_basket(block.global_position), "block at %s" % block.global_position)
	_check("cart heard it land", sound.hits > hits0, "hits %d -> %d, hardest %.2f m/s" % [hits0, sound.hits, loudest])

	# Turn the cart left on the spot with the arrow.
	await _wait(1.0)
	var h0 := cart.heading()
	bench.turn = 1.0
	await _wait(1.5)
	bench.turn = 0.0
	var dh := wrapf(cart.heading() - h0, -PI, PI)
	_check("left arrow turns the cart left", dh > 0.5, "turned %.2f rad" % dh)
	_check("block still in the basket", cart.in_basket(block.global_position), "block at %s" % block.global_position)

	print("sound bench test: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(1 if failures else 0)
