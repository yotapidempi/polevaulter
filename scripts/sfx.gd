extends Node
## Sound effects synthesised in code at startup, so the project needs no audio files.
## Sfx.play("thump", where, volume_db, pitch). The swing whoosh is a loop driven by whoosh().
## Swap any entry in _streams for a recorded sample later without touching the callers.
##
## Kept soft on purpose: noise is low-passed (no hiss), every sound fades in over a few
## milliseconds (no clicks), and everything runs through an "SFX" bus with a high-cut,
## a compressor and a little room reverb so the sounds sit together.

const RATE := 44100
const VOICES := 20
const BUS := "SFX"
const BUS_DB := -5.0

var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _whoosh: AudioStreamPlayer3D
var _whoosh_target := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus()
	seed(1234)  # same sounds every run
	_streams["thump"] = _thump()
	_streams["crunch"] = _crunch()
	_streams["crack"] = _crack()
	_streams["splat"] = _splat()
	_streams["tap_grass"] = _tap_grass()
	_streams["tap_stone"] = _tap_stone()
	_streams["tap_wood"] = _tap_wood()
	_streams["tap_metal"] = _tap_metal()
	_streams["thud"] = _thud()
	_streams["kick"] = _kick()
	_streams["whoosh"] = _whoosh_loop()
	randomize()
	for i in VOICES:
		_pool.append(_make_player())
	_whoosh = _make_player()
	_whoosh.stream = _streams["whoosh"]
	_whoosh.volume_db = -80.0
	_whoosh.play()


func _make_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, BUS)
	AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, BUS_DB)
	var cut := AudioEffectLowPassFilter.new()
	cut.cutoff_hz = 6500.0
	AudioServer.add_bus_effect(i, cut)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14.0
	comp.ratio = 3.0
	comp.attack_us = 2000.0
	comp.release_ms = 120.0
	AudioServer.add_bus_effect(i, comp)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.3
	rev.damping = 0.7
	rev.spread = 0.6
	rev.hipass = 0.25
	rev.dry = 1.0
	rev.wet = 0.1
	AudioServer.add_bus_effect(i, rev)


func _make_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.panning_strength = 0.4
	p.bus = BUS
	add_child(p)
	return p


func play(name: String, at: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch * randf_range(0.95, 1.05), 0.3, 3.0)
	p.global_position = at
	p.play()


## Which pole-tap sound a surface makes. Level pieces carry a "surface" metadata entry
## (grass, stone, wood, metal); anything without one sounds like stone.
func tap_for(collider: Object) -> String:
	var surface := "stone"
	if collider is Node and (collider as Node).has_meta("surface"):
		surface = str((collider as Node).get_meta("surface"))
	var key := "tap_" + surface
	return key if _streams.has(key) else "tap_stone"


## Drive the swing whoosh from the pole tip speed (m/s).
func whoosh(tip_speed: float, at: Vector3) -> void:
	_whoosh_target = clampf((tip_speed - 7.0) / 28.0, 0.0, 1.0)
	_whoosh.global_position = at
	_whoosh.pitch_scale = 0.7 + clampf(tip_speed / 45.0, 0.0, 0.8)


func _process(delta: float) -> void:
	# Freeze-frames go silent on the whoosh so the impact sound stands alone.
	var target := _whoosh_target if Engine.time_scale > 0.5 else 0.0
	var cur := db_to_linear(_whoosh.volume_db)
	cur = lerpf(cur, target * 0.4, clampf(delta / maxf(Engine.time_scale, 0.01) * 14.0, 0.0, 1.0))
	_whoosh.volume_db = linear_to_db(maxf(cur, 0.00001))


## Write every sound to `dir` as .wav, for listening outside the game.
func export_wavs(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for name in _streams:
		(_streams[name] as AudioStreamWAV).save_to_wav(dir.path_join(name + ".wav"))


# --- synthesis ---------------------------------------------------------------

func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var peak := 0.0001
	for x in s:
		peak = maxf(peak, absf(x))
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i] / peak * 0.7, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


## Fade in over `attack` seconds, then decay exponentially.
func _env(t: float, attack: float, decay: float) -> float:
	return minf(1.0, t / attack) * exp(-t * decay)


## One-pole low-pass coefficient for a cutoff in Hz.
func _lp(hz: float) -> float:
	return 1.0 - exp(-TAU * hz / RATE)


## Soft saturation: rounds off peaks instead of clipping them.
func _warm(x: float, drive := 1.5) -> float:
	return tanh(x * drive) / tanh(drive)


## Body hit: a deep, rounded thump with a muffled smack.
func _thump() -> AudioStreamWAV:
	var s := _buf(0.32)
	var ph := 0.0
	var n := 0.0
	var a := _lp(500.0)
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (52.0 + 85.0 * exp(-t * 20.0)) / RATE
		n += a * (randf_range(-1, 1) - n)
		var body := (sin(ph) + 0.25 * sin(ph * 2.01)) * _env(t, 0.003, 10.0)
		s[i] = _warm(body + n * 2.0 * _env(t, 0.002, 32.0))
	return _wav(s)


## Heavy-hit layer: a short, dull, grainy crunch (no crackle spikes).
func _crunch() -> AudioStreamWAV:
	var s := _buf(0.2)
	var hi := 0.0
	var lo := 0.0
	var a := _lp(1800.0)
	var b := _lp(250.0)
	var grain := 1.0
	for i in s.size():
		var t := float(i) / RATE
		if i % int(RATE * 0.007) == 0:
			grain = randf_range(0.45, 1.0)
		var x := randf_range(-1, 1)
		hi += a * (x - hi)
		lo += b * (x - lo)
		s[i] = (hi - lo) * grain * _env(t, 0.004, 22.0)
	return _wav(s)


## Decapitation: a woody snap, more knock than hiss.
func _crack() -> AudioStreamWAV:
	var s := _buf(0.18)
	var n := 0.0
	var a := _lp(2200.0)
	for i in s.size():
		var t := float(i) / RATE
		n += a * (randf_range(-1, 1) - n)
		s[i] = _warm(sin(TAU * 420.0 * t) * _env(t, 0.001, 38.0) + sin(TAU * 980.0 * t) * 0.35 * _env(t, 0.001, 55.0)
			+ n * 0.6 * _env(t, 0.001, 90.0))
	return _wav(s)


## Wet splat: soft, low and squelchy.
func _splat() -> AudioStreamWAV:
	var s := _buf(0.35)
	var n := 0.0
	var a := _lp(380.0)
	for i in s.size():
		var t := float(i) / RATE
		n += a * (randf_range(-1, 1) - n)
		var wobble := 0.6 + 0.4 * sin(TAU * 22.0 * t + sin(TAU * 6.0 * t) * 2.5)
		s[i] = n * wobble * _env(t, 0.01, 9.0)
	return _wav(s)


## Pole taps: the pole is wood, so every tap starts with a short wooden knock of the pole
## itself, then the surface adds its own character.
func _pole_knock(t: float) -> float:
	return sin(TAU * 410.0 * t) * _env(t, 0.0015, 60.0) + sin(TAU * 1030.0 * t) * 0.3 * _env(t, 0.0015, 85.0)


## Grass and dirt: mostly a muffled thud, the knock barely there.
func _tap_grass() -> AudioStreamWAV:
	var s := _buf(0.18)
	var n := 0.0
	var a := _lp(350.0)
	for i in s.size():
		var t := float(i) / RATE
		n += a * (randf_range(-1, 1) - n)
		s[i] = n * 2.2 * _env(t, 0.003, 30.0) + sin(TAU * 95.0 * t) * 0.5 * _env(t, 0.003, 28.0) \
			+ _pole_knock(t) * 0.25
	return _wav(s)


## Stone: a hard, dry knock with a bright tick and almost no ring.
func _tap_stone() -> AudioStreamWAV:
	var s := _buf(0.14)
	var n := 0.0
	var a := _lp(3000.0)
	for i in s.size():
		var t := float(i) / RATE
		n += a * (randf_range(-1, 1) - n)
		s[i] = _pole_knock(t) + sin(TAU * 1650.0 * t) * 0.25 * _env(t, 0.001, 120.0) + n * 0.35 * _env(t, 0.001, 160.0)
	return _wav(s)


## Wood on wood: hollow and resonant, a lower body that rings a little longer.
func _tap_wood() -> AudioStreamWAV:
	var s := _buf(0.24)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = _pole_knock(t) * 0.7 + sin(TAU * 220.0 * t) * _env(t, 0.002, 22.0) \
			+ sin(TAU * 575.0 * t) * 0.45 * _env(t, 0.002, 32.0) + sin(TAU * 1240.0 * t) * 0.12 * _env(t, 0.002, 55.0)
	return _wav(s)


## Metal (for later levels): the knock plus a short, slightly inharmonic clang.
func _tap_metal() -> AudioStreamWAV:
	var s := _buf(0.6)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = _pole_knock(t) * 0.6 + (sin(TAU * 640.0 * t) + 0.6 * sin(TAU * 1712.0 * t)
			+ 0.35 * sin(TAU * 2960.0 * t)) * 0.35 * _env(t, 0.001, 9.0)
	return _wav(s)


## Landing: a soft low thud.
func _thud() -> AudioStreamWAV:
	var s := _buf(0.22)
	var ph := 0.0
	var n := 0.0
	var a := _lp(300.0)
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (46.0 + 30.0 * exp(-t * 25.0)) / RATE
		n += a * (randf_range(-1, 1) - n)
		s[i] = _warm(sin(ph) * _env(t, 0.004, 16.0) + n * 1.4 * _env(t, 0.004, 26.0))
	return _wav(s)


## Kick off the pole: a soft whump with a puff of air.
func _kick() -> AudioStreamWAV:
	var s := _buf(0.2)
	var ph := 0.0
	var n := 0.0
	var a := _lp(900.0)
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (85.0 + 60.0 * (1.0 - exp(-t * 25.0))) / RATE
		n += a * (randf_range(-1, 1) - n)
		s[i] = _warm(sin(ph) * _env(t, 0.006, 15.0) + n * 0.7 * _env(t, 0.01, 22.0))
	return _wav(s)


## Looping soft whoosh: low band-passed noise, crossfaded so the loop has no seam.
func _whoosh_loop() -> AudioStreamWAV:
	var n := int(1.0 * RATE)
	var fade := int(0.15 * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var hi := 0.0
	var lo := 0.0
	var a := _lp(900.0)
	var b := _lp(120.0)
	for i in raw.size():
		var x := randf_range(-1, 1)
		hi += a * (x - hi)
		lo += b * (x - lo)
		raw[i] = hi - lo
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = raw[i]
		if i < fade:
			var w := float(i) / fade
			s[i] = raw[i] * w + raw[n + i] * (1.0 - w)
	return _wav(s, true)
