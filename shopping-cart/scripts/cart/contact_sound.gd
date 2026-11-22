class_name ContactSound
extends Node3D
## The sound of a cart body (the frame) touching anything that isn't its own wheels: dragging on its side, scraping
## along a wall, banging into a kerb or another cart. Instanced (scenes/cart/contact_sound.tscn) under the body,
## which needs contact_monitor on. Everything comes from the contacts the physics reports each tick:
##  - Scrape: friction. Each sliding contact turns friction into heat and noise at a rate of its friction force
##    times its sliding speed (W). The loop's volume follows that power summed over the contacts, its pitch the
##    sliding speed, and its sound what is rubbing: the part of this body (the collision shape) doing the most
##    rubbing picks its loop from `shape_scrapes`, else `scrape` (zack's pipe-on-concrete recording, made into one
##    loop per material by tools/audio/make_scrape_loops.py: tube, wire cage, plastic seat).
##  - Hit: the push the floor or wall gives the body along the contact normal, as velocity (impulse / mass), summed
##    over the ticks a hit lasts. A light hit knocks, a hard one slams, louder the harder.
## No timers: nothing plays unless the physics reports that much friction or that hard a push.

@export var scrape_player: AudioStreamPlayer3D
@export var hit_player: AudioStreamPlayer3D
## Generated hits (the cart's ImpactSynth): when set, hits also strike it with their impulse, under the recording.
@export var synth: ImpactSynth
@export var contact_time := 0.0004    ## s steel on stone lasts at 1 m/s
@export var scrape: AudioStream                        ## this body's scrape loop
@export var shape_scrapes: Dictionary = {}             ## collision shape name -> its own scrape loop (a tube on a wire cage)
@export var floor_sounds: Array[CartFloorSound] = []   ## what was hit, for how hard it is (generated hits)
@export var fallback: CartFloorSound                   ## for anything no CartFloorSound lists (walls, props, carts)
@export_group("Scrape")
@export var scrape_start := 5.0       ## W of friction before it is heard
@export var scrape_full := 300.0      ## W of friction for full volume (an 18 kg frame dragged on its side at a jog)
@export var scrape_curve := 0.6       ## gain = (power / scrape_full) ^ this
@export var scrape_db := -2.0
@export var scrape_pitch_low := 0.8   ## pitch sliding slowly
@export var scrape_pitch_per_speed := 0.2   ## pitch rise per m/s of sliding
@export var scrape_max_pitch := 1.5
## s: the loop follows the friction power averaged over about this long. Contacts on a tumbling frame come and go
## every tick; a real scrape rings on between them, so the sound follows the average, not each tick.
@export var power_smoothing := 0.05
@export_group("Hit")
## m/s per tick of push beyond the body's weight (gravity alone is 0.08 at 120 ticks): more than this is a hit
@export var hit_floor := 0.15
@export var hit_start := 0.4          ## m/s: a softer hit is silent
@export var hit_slam_speed := 1.2     ## m/s: from here it slams instead of knocking
@export var hit_full := 3.0           ## m/s: full volume
@export var hit_db := -2.0
@export var knock: AudioStream        ## a light hit
@export var slam: AudioStream         ## a hard hit

var power := 0.0          ## W of friction on all the body's contacts this tick
var heard_power := 0.0    ## W: power averaged over power_smoothing, which the loop follows
var slip := 0.0           ## m/s: sliding speed of those contacts, weighted by their friction
var scrape_gain := 0.0
var floor_sound: CartFloorSound = null   ## the floor doing the most rubbing (null: nothing rubbing)
var scrape_stream: AudioStream = null    ## the loop of the part doing the most rubbing (null: nothing rubbing)
var hits := 0             ## hits heard (for tests)
var slams := 0
var last_hit := 0.0       ## m/s of the last hit, heard or not

@onready var _body := get_parent() as RigidBody3D
var _cart: ShoppingCart = null
var _hit := 0.0
var _hit_impulse := 0.0
var _hit_at := Vector3.ZERO          ## impulse-weighted sum of the hit's contact points (the body's space)
var _hit_floor: CartFloorSound = null
var _hit_floor_push := 0.0


func _ready() -> void:
	var n := _body.get_parent()
	_cart = n as ShoppingCart
	scrape_player.volume_db = -80.0


func _physics_process(delta: float) -> void:
	power = 0.0
	slip = 0.0
	var push := 0.0
	var at := Vector3.ZERO
	var floor_push := 0.0
	var floor_hit: CartFloorSound = null
	var to_local := (_cart.frame if _cart else _body).global_transform.affine_inverse()   # hits in the frame's space
	var best := 0.0
	floor_sound = null
	scrape_stream = null
	var st := PhysicsServer3D.body_get_direct_state(_body.get_rid()) if not _body.freeze else null
	if st:
		for i in st.get_contact_count():
			if _cart and _cart._own_rids.has(st.get_contact_collider(i)):
				continue   # its own wheels, groceries, a cart nested into it
			var n := st.get_contact_local_normal(i)
			var imp := st.get_contact_impulse(i)
			var rv := st.get_contact_local_velocity_at_position(i) - st.get_contact_collider_velocity_at_position(i)
			var vt := (rv - n * rv.dot(n)).length()
			var p := (imp - n * imp.dot(n)).length() / delta * vt   # friction force x sliding speed
			power += p
			slip += p * vt
			var pn := maxf(0.0, imp.dot(n))
			push += pn
			at += to_local * st.get_contact_local_position(i) * pn
			if pn > floor_push:
				floor_push = pn
				floor_hit = _floor_for(st.get_contact_collider_object(i))
			if p > best:
				best = p
				floor_sound = _floor_for(st.get_contact_collider_object(i))
				var part := _body.shape_owner_get_owner(_body.shape_find_owner(st.get_contact_local_shape(i))) as Node
				scrape_stream = shape_scrapes.get(String(part.name), scrape) if part else scrape
		if power > 0.0:
			slip /= power

	# Hit: the push beyond holding the body's weight, as velocity.
	var dv := push / _body.mass - _body.get_gravity().length() * delta
	if dv > hit_floor:
		_hit += dv
		_hit_impulse += push
		_hit_at += at
		if floor_push > _hit_floor_push:
			_hit_floor_push = floor_push
			_hit_floor = floor_hit
	elif _hit > 0.0:
		_play_hit(_hit)
		_hit = 0.0
		_hit_impulse = 0.0
		_hit_at = Vector3.ZERO
		_hit_floor = null
		_hit_floor_push = 0.0

	# Scrape: the loop of the part doing the most rubbing, as loud as the friction is strong.
	heard_power = lerpf(heard_power, power, minf(1.0, delta / power_smoothing))
	var target := 0.0
	if heard_power > scrape_start:
		target = pow(clampf(heard_power / scrape_full, 0.0, 1.0), scrape_curve)
	if scrape_stream and scrape_stream != scrape_player.stream:
		scrape_player.stop()   # another part rubbing now: its loop starts below
		scrape_player.stream = scrape_stream
	scrape_gain = target
	scrape_player.volume_db = scrape_db + linear_to_db(maxf(scrape_gain, 0.0001))
	scrape_player.pitch_scale = clampf(scrape_pitch_low + slip * scrape_pitch_per_speed, scrape_pitch_low, scrape_max_pitch)
	if scrape_gain > 0.0 and not scrape_player.playing and scrape_player.stream:
		scrape_player.play()
	elif scrape_gain <= 0.0 and scrape_player.playing:
		scrape_player.stop()


func _floor_for(collider: Object) -> CartFloorSound:
	var mat: PhysicsMaterial = collider.get("physics_material_override") if collider else null
	for f in floor_sounds:
		if mat and f.floors.has(mat):
			return f
	return fallback


func _play_hit(speed: float) -> void:
	last_hit = speed
	if synth:
		var where := _hit_at / maxf(_hit_impulse, 1e-6)
		var scale := _hit_floor.contact_time_scale if _hit_floor else 1.0
		synth.strike(ImpactSynth.Source.FRAME, speed, _hit_impulse, contact_time * scale, where)
	if speed <= hit_start:
		return
	hits += 1
	var hard := speed >= hit_slam_speed
	if hard:
		slams += 1
	hit_player.stream = slam if hard else knock
	var g := clampf((speed - hit_start) / (hit_full - hit_start), 0.05, 1.0)
	hit_player.volume_db = hit_db + linear_to_db(g)
	hit_player.play()
	if synth:
		synth.note_recording(hit_player.stream, hit_player.volume_db)
