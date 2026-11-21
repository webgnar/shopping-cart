class_name RollingSurfaceSound
extends AudioStreamPlayer3D
## One looping rolling sound of the cart (a recording of a real cart on one kind of ground), used while the cart
## rolls on any of `floors`. CartRollingSound (the parent) fades it in and out and sets its pitch; its loudness at
## full speed is `loudness_db`. The loops are cut from zack's recordings by tools/audio/make_cart_rolling_loops.py.

## The floors' physics materials (assets/physics/*.tres) this sound is for.
@export var floors: Array[PhysicsMaterial] = []
## dB at full speed (full_volume_speed on the parent). The loops are levelled to the same loudness, so this is
## how loud this ground is next to the others.
@export var loudness_db := 0.0
## 0 to 1: how far this sound is faded in. CartRollingSound drives it.
var gain := 0.0


func set_gain(g: float) -> void:
	gain = g
	volume_db = loudness_db + linear_to_db(maxf(g, 0.0001))
	if g > 0.0 and not playing:
		# Start somewhere random in the loop, so carts rolling side by side don't sound in step.
		var length := stream.get_length() if stream else 0.0
		play(randf() * length)
	elif g <= 0.0 and playing:
		stop()
