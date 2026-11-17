extends Node
## Autoload "Sfx" — every sound is synthesized at startup into AudioStreamWAV
## buffers; no asset files needed. Same approach as hallway-demo, trimmed to
## M0's needs. Replace _build_streams() entries with imported audio later and
## keep the play()/loop() API.

const RATE := 22050

# Sentinel meaning "play on the 2D bus, not positional".
const CENTER := Vector3(1e9, 1e9, 1e9)

var _streams: Dictionary = {}
var _active: Array = []        # live positional players, for clean shutdown
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_streams()
	_build_buses()


## Stop every looped player AND every live one-shot before exit — active
## AudioStreamPlaybacks keep their streams alive at shutdown otherwise.
func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.queue_free()
	for p in _active:
		if is_instance_valid(p):
			p.stop()
			p.queue_free()
	_active.clear()
	_streams.clear()


## Two audio worlds: Master (dry air) and Hull (transmission through steel).
## "Hull" carries a hard lowpass and a short metallic room; every positional
## sound whose straight path to the listener is occluded gets routed there,
## which is what makes the patroller's steps read as *three rooms away* and
## the knocks read as inside the ship's bones.
func _build_buses() -> void:
	if AudioServer.get_bus_index("Hull") != -1:
		return
	AudioServer.add_bus(AudioServer.bus_count)
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, "Hull")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 1700.0
	AudioServer.add_bus_effect(idx, lp)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.75
	rev.wet = 0.22
	rev.spread = 0.95
	rev.damping = 0.65
	AudioServer.add_bus_effect(idx, rev)
	AudioServer.set_bus_send(idx, "Master")


## Plays a named stream, once. `at` = world position for 3D positional sound,
## or Sfx.CENTER for UI / player-local sound.
func play(sound: String, at: Vector3 = CENTER, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(sound):
		push_warning("Sfx: unknown stream '%s'" % sound)
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	if at != CENTER:
		var p := AudioStreamPlayer3D.new()
		p.stream = _streams[sound]
		p.pitch_scale = maxf(0.05, pitch)
		p.unit_size = 10.0
		p.max_distance = 140.0
		# Occlusion: if a wall stands between the source and the current
		# listener (the player's own ears or the drone's), the sound arrives
		# through steel. This one ray is why distant hosts sound distant.
		var bus_volume := volume_db
		# The game's 3D now lives in PSXLook's own World3D, not the root
		# viewport's. Use the active PSX camera and that world for the one
		# occlusion ray, and parent positional players inside it.
		var host: Node = tree.current_scene
		var scene_node: Node3D = null
		var camera: Camera3D = get_viewport().get_camera_3d()
		if PSXLook.world != null:
			host = PSXLook.world
			scene_node = PSXLook.world
			camera = PSXLook.current_camera()
		elif tree.current_scene is Node3D:
			scene_node = tree.current_scene
		if camera != null and scene_node != null:
			var space: PhysicsDirectSpaceState3D = scene_node.get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(
					at, camera.global_position, 1)
			if space.intersect_ray(query).size() > 0:
				p.bus = "Hull"
				bus_volume -= 3.0
		p.volume_db = bus_volume
		host.add_child(p)
		p.global_position = at
		_active.append(p)
		p.finished.connect(func() -> void:
			_active.erase(p)
			p.queue_free()
		)
		p.play()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = _streams[sound]
		p.volume_db = volume_db
		p.pitch_scale = maxf(0.05, pitch)
		tree.current_scene.add_child(p)
		p.finished.connect(p.queue_free)
		p.play()


## Starts a looping positional-free player parented to the autoload itself
## (survives scene changes). Currently only "hum" is loop-marked.
func loop(sound: String, volume_db: float = 0.0) -> AudioStreamPlayer:
	if not _streams.has(sound):
		push_warning("Sfx: unknown stream '%s'" % sound)
		return null
	var p := AudioStreamPlayer.new()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	add_child(p)
	p.play()
	return p


## A looped 3D source the caller parents to its own body. Distance is handled
## by the caller (the stalker drives volume and pitch from proximity), while
## the 3D position still pans it around the listener.
func loop3d(sound: String, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	if not _streams.has(sound):
		push_warning("Sfx: unknown stream '%s'" % sound)
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.unit_size = 10.0
	p.max_distance = 60.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.panning_strength = 1.0
	p.bus = "Master"
	return p


# --------------------------------------------------------------------------
# Stream construction
# --------------------------------------------------------------------------

func _build_streams() -> void:
	# Bay ambience: deep hull rumble + faint transformer whine, seam-crossfaded
	# so it loops clean. Marked LOOP_FORWARD.
	var hum := _hum()
	var wav := _wav(hum)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = hum.size()
	_streams["hum"] = wav

	# The shadow stalker's long sub-bass hum: an 8 s loop with a slow beat.
	var shum := _stalker_hum()
	var swav := _wav(shum)
	swav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	swav.loop_begin = 0
	swav.loop_end = shum.size()
	_streams["stalker_hum"] = swav

	# Drone motor: closed-loop crawler rumble, volume-driven while piloting.
	var motor := _motor()
	var mwav := _wav(motor)
	mwav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	mwav.loop_begin = 0
	mwav.loop_end = motor.size()
	_streams["motor"] = mwav

	_streams["step"] = _wav(_footstep(1.0, 62.0))
	_streams["step_metal"] = _wav(_step_metal())
	_streams["knock"] = _wav(_knock())
	_streams["thud"] = _wav(_thud())
	_streams["tick"] = _wav(_tick())
	_streams["scrape"] = _wav(_scrape())
	_streams["static"] = _wav(_static_burst())
	_streams["screech"] = _wav(_screech())
	_streams["reel"] = _wav(_reel())
	_streams["ping"] = _wav(_ping())
	_streams["hstep"] = _wav(_hstep())
	_streams["shutter"] = _wav(_shutter())

	# Cold Hold / crawler set piece. All synthesized, filtered and quiet.
	var breath := _breath()
	var bwav := _wav(breath)
	bwav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bwav.loop_begin = 0
	bwav.loop_end = breath.size()
	_streams["breath"] = bwav
	_streams["zone_cue"] = _wav(_zone_cue())
	_streams["crawler_voice"] = _wav(_crawler_voice())
	_streams["crawler_drag"] = _wav(_hstep())
	_streams["crawler_scream"] = _wav(_crawler_scream())
	_streams["wet_crunch"] = _wav(_wet_crunch())
	_streams["wet_snap"] = _wav(_wet_snap())


## Crossfades the tail into the head so a loop wraps clean.
func _loopify(b: PackedFloat32Array, fade_s: float) -> void:
	var n0 := int(fade_s * RATE)
	for i in n0:
		var w := float(i) / float(n0)
		b[i] = b[i] * w + b[b.size() - n0 + i] * (1.0 - w)


## Closed-loop crawler motor: sub-throb + gear whine + LP rumble.
func _motor() -> PackedFloat32Array:
	var b := _buf(3.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		# 7 and 210 Hz both complete integer cycles in 3.0 s -> seamless.
		var throb := sin(TAU * 7.0 * t) * 0.18
		var gear := sin(TAU * 210.0 * t) * 0.05
		lp = lp * 0.99 + _rng.randf_range(-1.0, 1.0) * 0.01
		b[i] = throb + gear + lp * 0.5
	_loopify(b, 0.35)
	return b


## Metal-on-metal scrape: screeching sweep with grit under it.
func _scrape() -> PackedFloat32Array:
	var b := _buf(0.5)
	for i in b.size():
		var t := float(i) / RATE
		var f := 780.0 + 900.0 * t + 260.0 * sin(t * 22.0)
		var screech := sin(TAU * f * t) * exp(-t * 3.2) * 0.3
		var grit := _rng.randf_range(-1.0, 1.0) * exp(-t * 4.0) * 0.28
		b[i] = screech + grit
	_lp(b, 0.6)
	_echo(b, 0.05, 0.3, 2)
	return b


## Camera/feed static hit — snow burst, fast attack, ragged release.
func _static_burst() -> PackedFloat32Array:
	var b := _buf(0.5)
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t * 22.0, 1.0) * exp(-maxf(t - 0.12, 0.0) * 5.0)
		b[i] = _rng.randf_range(-1.0, 1.0) * env * 0.7
	_lp(b, 0.35)
	return b


## Jump-scare stinger: a hard, rising metal shriek with torn noise under it.
func _screech() -> PackedFloat32Array:
	var b := _buf(1.15)
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t * 55.0, 1.0) * exp(-maxf(t - 0.06, 0.0) * 3.4)
		var f := 620.0 + 1500.0 * minf(t * 5.0, 1.0) + 210.0 * sin(t * 31.0)
		var scream := sin(TAU * f * t) * 0.36
		var tear := _rng.randf_range(-1.0, 1.0) * 0.33
		b[i] = (scream + tear) * env
	_lp(b, 0.82)
	_echo(b, 0.045, 0.32, 2)
	return b


## Winch ratchet: rapid click train with a low drag underneath.
func _reel() -> PackedFloat32Array:
	var b := _buf(1.3)
	for i in b.size():
		var t := float(i) / RATE
		var click := exp(-fmod(t, 0.045) * 480.0) * 0.5
		var drag := sin(TAU * 55.0 * t) * sin(t * 3.4) * 0.16
		b[i] = (click + drag) * (1.0 - t * 0.25)
	_lp(b, 0.5)
	return b


## Tiny scanner blip.
func _ping() -> PackedFloat32Array:
	var b := _buf(0.09)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 1180.0 * t) * exp(-t * 60.0) * 0.12
	return b


## Wet host step: squelch under a swaying low thump. Deliberately organic.
func _hstep() -> PackedFloat32Array:
	var b := _buf(0.42)
	for i in b.size():
		var t := float(i) / RATE
		var squel := _rng.randf_range(-1.0, 1.0) * exp(-t * 24.0) * 0.35
		var thump := sin(TAU * (140.0 + 60.0 * sin(t * 9.0)) * t) * exp(-t * 16.0) * 0.3
		b[i] = thump + squel
	_lp(b, 0.55)
	_echo(b, 0.06, 0.25, 2)
	return b


## Old camera shutter: hard clack, then film-advance whirr.
func _shutter() -> PackedFloat32Array:
	var b := _buf(0.55)
	for i in b.size():
		var t := float(i) / RATE
		var clack := 0.0
		if t < 0.05:
			clack = _rng.randf_range(-1.0, 1.0) * exp(-t * 120.0) * 0.7
			clack += sin(TAU * 320.0 * t) * exp(-t * 90.0) * 0.4
		var whirr := 0.0
		if t > 0.12 and t < 0.5:
			var u := t - 0.12
			whirr = sin(TAU * (60.0 + 40.0 * u) * u) * exp(-u * 6.0) * 0.12
			whirr += _rng.randf_range(-1.0, 1.0) * exp(-u * 10.0) * 0.08
		b[i] = clack + whirr
	_lp(b, 0.75)
	_echo(b, 0.04, 0.2, 2)
	return b


## Wet, laboured breathing: a close-mic'd rasp over a slow sub swell. Four
## seconds so two breaths fit one loop and the wrap is inaudible.
func _breath() -> PackedFloat32Array:
	var dur := 4.0
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var breath := 0.5 + 0.5 * sin(TAU * 0.5 * t - PI * 0.5)
		var rasp := _rng.randf_range(-1.0, 1.0) * (0.10 + 0.22 * breath)
		lp = lp * 0.90 + rasp * 0.10
		var sub := sin(TAU * 33.0 * t) * (0.05 + 0.05 * breath)
		b[i] = lp + sub
	_lp(b, 0.55)
	_loopify(b, 0.5)
	return b

## The Cold Hold announcement: a low, descending two-tone through steel.
func _zone_cue() -> PackedFloat32Array:
	var b := _buf(2.2)
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t * 8.0, 1.0) * exp(-maxf(t - 0.15, 0.0) * 1.6)
		var f := 116.0 - 54.0 * minf(t / 1.8, 1.0)
		var tone := sin(TAU * f * t) * 0.34 + sin(TAU * f * 0.5 * t) * 0.18
		var grit := _rng.randf_range(-1.0, 1.0) * exp(-t * 5.0) * 0.05
		b[i] = (tone + grit) * env
	_lp(b, 0.72)
	_echo(b, 0.13, 0.42, 2)
	return b

## Filtered survivor speech, not a clean recording. Three formants under a
## broken syllabic envelope; the words are carried by the subtitle channel.
func _crawler_voice() -> PackedFloat32Array:
	var dur := 1.35
	var b := _buf(dur)
	for i in b.size():
		var t := float(i) / RATE
		var syllable := 0.5 + 0.5 * sin(TAU * 4.6 * t + sin(t * 9.0))
		var env := minf(t * 14.0, 1.0) * minf((dur - t) * 9.0, 1.0) * (0.35 + 0.65 * syllable)
		var f0 := 108.0 + 16.0 * sin(t * 5.3)
		var voice := sin(TAU * f0 * t) * 0.32
		voice += sin(TAU * f0 * 2.7 * t) * 0.16
		voice += sin(TAU * f0 * 5.1 * t) * 0.08
		var air := _rng.randf_range(-1.0, 1.0) * 0.07
		b[i] = (voice + air) * env
	_lp(b, 0.38)
	_echo(b, 0.04, 0.24, 2)
	return b

## A cut-off scream: rises, tears, then stops dead.
func _crawler_scream() -> PackedFloat32Array:
	var dur := 0.95
	var b := _buf(dur)
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t * 35.0, 1.0) * minf((dur - t) * 30.0, 1.0)
		var f := 480.0 + 1180.0 * minf(t / 0.62, 1.0) + 90.0 * sin(t * 27.0)
		var cry := sin(TAU * f * t) * 0.36 + sin(TAU * f * 1.5 * t) * 0.14
		var tear := _rng.randf_range(-1.0, 1.0) * 0.26
		b[i] = (cry + tear) * env
	_lp(b, 0.68)
	_echo(b, 0.05, 0.3, 2)
	return b

## Three wet bites in one stream: the Collector's last few seconds.
func _wet_crunch() -> PackedFloat32Array:
	var dur := 0.75
	var b := _buf(dur)
	for i in b.size():
		var t := float(i) / RATE
		var bite := exp(-fmod(t, 0.19) * 36.0)
		var wet := _rng.randf_range(-1.0, 1.0) * bite * 0.34
		var bone := sin(TAU * (88.0 - 26.0 * t) * t) * bite * 0.40
		b[i] = wet + bone
	_lp(b, 0.55)
	_echo(b, 0.03, 0.22, 2)
	return b

## The arm's snap: a hard wet crack and one low impact.
func _wet_snap() -> PackedFloat32Array:
	var b := _buf(0.35)
	for i in b.size():
		var t := float(i) / RATE
		var crack := _rng.randf_range(-1.0, 1.0) * exp(-t * 95.0) * 0.65
		var thump := sin(TAU * 62.0 * t) * exp(-t * 24.0) * 0.55
		b[i] = crack + thump
	_lp(b, 0.42)
	_echo(b, 0.04, 0.25, 2)
	return b


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	for i in samples.size():
		samples[i] = clampf(samples[i], -1.0, 1.0)
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(samples[i] * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## One-pole lowpass — for making things sound hull-borne / muffled.
func _lp(samples: PackedFloat32Array, alpha: float) -> void:
	var y := 0.0
	for i in samples.size():
		y = y * alpha + samples[i] * (1.0 - alpha)
		samples[i] = y


## Real-space echo, borrowed from the hallway-demo Sfx.
func _echo(samples: PackedFloat32Array, delay_s: float, gain: float, taps: int = 2) -> void:
	var d := int(delay_s * RATE)
	for t in taps:
		var g := gain * pow(0.45, float(t))
		for i in range(samples.size() - 1, d - 1, -1):
			samples[i] += samples[i - d] * g


## Seamless bay ambience: two slow-beating sub-basses + filtered rumble +
## a whisper of transformer whine. Crossfade tail into head for clean looping.
func _hum() -> PackedFloat32Array:
	var dur := 6.0
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var sub1 := sin(TAU * 38.0 * t) * 0.20
		var sub2 := sin(TAU * 41.3 * t) * 0.18
		lp = lp * 0.995 + _rng.randf_range(-1.0, 1.0) * 0.005
		var whine := sin(TAU * 120.0 * t) * sin(t * 0.9) * 0.012
		b[i] = sub1 + sub2 + lp * 0.55 + whine
	# Crossfade last 0.4 s into the first 0.4 s.
	var n0 := int(0.4 * RATE)
	for i in n0:
		var w := float(i) / float(n0)
		b[i] = b[i] * w + b[b.size() - n0 + i] * (1.0 - w)
	return b


## Heavy, slow sub-bass for the shadow stalker. 8 s loop; 42 / 45.5 / 84 Hz
## all complete whole cycles in that time, so it wraps without a seam. The
## 3.5 Hz beat between the first two is the thing that makes it feel alive.
func _stalker_hum() -> PackedFloat32Array:
	var dur := 8.0
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var sub1 := sin(TAU * 42.0 * t) * 0.22
		var sub2 := sin(TAU * 45.5 * t) * 0.18
		var body := sin(TAU * 84.0 * t) * (0.045 + 0.025 * sin(t * 0.75))
		lp = lp * 0.998 + _rng.randf_range(-1.0, 1.0) * 0.002
		b[i] = sub1 + sub2 + body + lp * 0.6
	_loopify(b, 0.6)
	return b


## Heavy suit boot: deep heel, drag, no springiness.
func _footstep(body_gain: float, freq: float) -> PackedFloat32Array:
	var b := _buf(0.26)
	for i in b.size():
		var t := float(i) / RATE
		var heel := sin(TAU * freq * t) * exp(-t * 26.0)
		var drag := _rng.randf_range(-1.0, 1.0) * exp(-t * 50.0) * 0.28
		var scuff := _rng.randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.06
		b[i] = (heel * 0.62 + drag + scuff) * body_gain
	_echo(b, 0.06, 0.26, 2)
	return b


## Same boot on decking that rings a little.
func _step_metal() -> PackedFloat32Array:
	var b := _footstep(1.0, 74.0)
	for i in b.size():
		var t := float(i) / RATE
		b[i] += sin(TAU * 190.0 * t) * exp(-t * 30.0) * 0.16
		b[i] += sin(TAU * 640.0 * t) * exp(-t * 90.0) * 0.05
	return b


## Hull-borne knock: dull impact, hard lowpassed so it reads as "through steel".
func _knock() -> PackedFloat32Array:
	var b := _buf(0.9)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 96.0 * t) * exp(-t * 32.0) * 0.85
		b[i] += _rng.randf_range(-1.0, 1.0) * exp(-t * 110.0) * 0.35
	_lp(b, 0.86)
	_echo(b, 0.12, 0.42, 3)
	return b


## Something heavy settling somewhere it shouldn't.
func _thud() -> PackedFloat32Array:
	var b := _buf(0.8)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 58.0 * t) * exp(-t * 15.0) * 0.9
		b[i] += _rng.randf_range(-1.0, 1.0) * exp(-t * 80.0) * 0.3
	_lp(b, 0.88)
	_echo(b, 0.1, 0.3, 2)
	return b


## Soft UI tick for interactions.
func _tick() -> PackedFloat32Array:
	var b := _buf(0.12)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 620.0 * t) * exp(-t * 70.0) * 0.15
	return b
