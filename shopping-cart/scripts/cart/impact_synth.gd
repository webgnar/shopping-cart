class_name ImpactSynth
extends AudioStreamPlayer3D
## Generated impact sound: no recordings. The cart's parts (`parts`, each a RingingPart worked out from its real size
## and material) ring at their own frequencies; every hit the physics reports strikes them.
##  - How hard: the impulse of the hit (N s) sets how far each mode is set ringing.
##  - How bright: a hit is a short pulse of force lasting the contact time. Harder materials and faster hits make it
##    shorter (Hertz contact: time ~ speed^-1/5), and a pulse lasting tau carries frequencies up to about 1 / tau. So
##    each mode is struck by the pulse's spectrum at its frequency: a fast hit rings the high modes, a slow one only
##    the low ones.
##  - Where: a hit on the frame shakes the parts by their frame_coupling, a wheel hitting the ground by their
##    wheel_coupling, and the hit point (in the frame's space) picks the parts near it, the bars near it and, by
##    each mode's shape along the bar, which of their modes ring. A corner, a wheel, the handle each sound different.
##  - What it hits: the floor's hardness scales the contact time (tile is harder and brighter than asphalt).
## Each mode is a two-pole resonator (a decaying sine), run on its own clock each physics tick and pushed to this
## player's AudioStreamGenerator, so the sound is exactly what the physics did, tick by tick.

enum Source { FRAME, WHEEL }

@export var parts: Array[RingingPart] = []
@export var strike_gain := 0.004      ## output per N s of impulse on a mode of gain 1 (soft-clipped by tanh near 1)
@export var capture := false          ## keep every sample made (tests render it to a file)

var captured := PackedFloat32Array()
var recordings := []                  ## with capture on: [sample index, stream, volume dB] of each recording played
var peak := 0.0                       ## loudest sample so far (for tests)
var strikes := 0

var _rate := 24000.0
var _f := PackedFloat64Array()
var _c1 := PackedFloat64Array()       ## 2 r cos(w)
var _c2 := PackedFloat64Array()       ## r^2
var _kick := PackedFloat64Array()     ## sin(w) / r: what a unit strike adds to the state
var _gain := PackedFloat64Array()
var _couple := [PackedFloat64Array(), PackedFloat64Array()]
var _part: Array[RingingPart] = []    ## each mode's part, shape index and span
var _n := PackedInt32Array()
var _span := PackedInt32Array()
var _y1 := PackedFloat64Array()
var _y2 := PackedFloat64Array()
var _due := 0.0
var _ringing := false
var _playback: AudioStreamGeneratorPlayback = null


func _ready() -> void:
	var gen := stream as AudioStreamGenerator
	if gen:
		_rate = gen.mix_rate
	for p in parts:
		for m in p.modes(_rate * 0.45):
			var w: float = TAU * m[0] / _rate
			var r := exp(-m[1] / _rate)
			_f.append(m[0])
			_c1.append(2.0 * r * cos(w))
			_c2.append(r * r)
			_kick.append(sin(w) / r)
			_gain.append(m[2])
			_couple[Source.FRAME].append(p.frame_coupling)
			_couple[Source.WHEEL].append(p.wheel_coupling)
			_part.append(p)
			_n.append(m[3])
			_span.append(m[4])
			_y1.append(0.0)
			_y2.append(0.0)
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


## A hit: `impulse` N s delivered at `speed` m/s at `where` (the frame's space), with a contact time of
## `contact_time` s at 1 m/s.
func strike(source: Source, speed: float, impulse: float, contact_time: float, where: Vector3) -> void:
	var tau := contact_time * pow(1.0 / maxf(speed, 0.05), 0.2)
	var couple: PackedFloat64Array = _couple[source]
	for k in _f.size():
		if couple[k] <= 0.0:
			continue
		# Spectrum of a half-sine force pulse of length tau at this mode's frequency (1 at low frequency).
		var x := 2.0 * _f[k] * tau
		var s := PI / 4.0 if absf(1.0 - x * x) < 1e-6 else absf(cos(PI * x / 2.0) / (1.0 - x * x))
		var at := _part[k].weight_at(where, _n[k], _span[k])
		_y2[k] -= strike_gain * impulse * couple[k] * at * _gain[k] * s * _kick[k]
	strikes += 1
	_ringing = true


func _physics_process(delta: float) -> void:
	_due += delta * _rate
	var n := int(_due)
	_due -= n
	if n <= 0:
		return
	var buf := PackedFloat32Array()
	buf.resize(n)
	if _ringing:
		_ringing = false
		for k in _f.size():
			var y1 := _y1[k]
			var y2 := _y2[k]
			if absf(y1) + absf(y2) < 1e-6:
				_y1[k] = 0.0
				_y2[k] = 0.0
				continue
			_ringing = true
			var c1 := _c1[k]
			var c2 := _c2[k]
			for i in n:
				var y := c1 * y1 - c2 * y2
				y2 = y1
				y1 = y
				buf[i] += y
			_y1[k] = y1
			_y2[k] = y2
		for i in n:
			buf[i] = tanh(buf[i])
			peak = maxf(peak, absf(buf[i]))
	if capture:
		captured.append_array(buf)
	if _playback and _playback.can_push_buffer(n):
		var frames := PackedVector2Array()
		frames.resize(n)
		for i in n:
			frames[i] = Vector2(buf[i], buf[i])
		_playback.push_buffer(frames)


## A recording played for the same hit (WheelSound, ContactSound): logged with capture on, so a render can mix it in.
func note_recording(s: AudioStream, db: float) -> void:
	if capture:
		recordings.append([captured.size(), s, db])


## The captured sound as a 16-bit WAV.
func captured_wav() -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(captured.size() * 2)
	for i in captured.size():
		data.encode_s16(i * 2, int(clampf(captured[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(_rate)
	wav.data = data
	return wav
