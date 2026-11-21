class_name CartFloorSound
extends Resource
## How one kind of ground sounds under a cart wheel: its rolling loop and its scrub (the wheel sliding sideways or
## skidding), for the floors whose physics materials are listed. Shared by every wheel (scenes/cart/wheel_sound.tscn).
## The loops are cut from zack's recordings by tools/audio/make_cart_rolling_loops.py.

## The floors' physics materials (assets/physics/*.tres) this sound is for.
@export var floors: Array[PhysicsMaterial] = []
@export var roll: AudioStream          ## looping roll, levelled like the others
@export var roll_db := 0.0             ## how loud this ground rolls next to the others
@export var scrub: AudioStream         ## looping scrub: a gritty scrape on rough ground, a squeak on tile
@export var scrub_db := 0.0
