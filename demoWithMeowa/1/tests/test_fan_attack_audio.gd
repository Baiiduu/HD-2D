extends SceneTree

var scene: Node3D
var wave: WavePrototype
var player: Player
var fan: FanAutoAttack
var audio: GameAudio
var checks := 0
var failures: Array[String] = []
var landed := 0

func _initialize() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)

func settle(count := 5) -> void:
	for frame in count: await physics_frame
	await process_frame
	await process_frame

func tick(delta: float) -> void:
	audio._process(delta)
	fan._physics_process(delta)

func enemy_at(offset: Vector3) -> WaveEnemy:
	assert(wave._spawn_enemy())
	var enemy := wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	enemy.health = 5000.0
	enemy.global_position = player.global_position + offset
	return enemy

func prepare() -> void:
	fan.cancel_current()
	fan._stop_audio()
	fan._cooldown = 0.0
	landed = 0

func voice(cue: StringName) -> AudioStreamPlayer3D:
	for slot in audio._voices:
		if slot.active and slot.source == fan and slot.cue == cue: return slot.voice
	return null

func run() -> void:
	scene = load("res://scenes/world/world.tscn").instantiate()
	scene.get_node("LoadoutUI").save_enabled = false
	scene.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(scene)
	current_scene = scene
	await settle(12)
	wave = scene.get_node("WavePrototype")
	player = scene.get_node("Player")
	fan = wave.get_node("FanAutoAttack")
	audio = scene.get_node("MapEffects/GameAudio")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	fan.set_physics_process(false)
	check(fan.sweep_sounds.size() == 2 and fan.hit_sounds.size() == 2, "Actual world inherits two sweep and two impact sounds")
	for clip in fan.sweep_sounds + fan.hit_sounds:
		check(clip is AudioStreamWAV and clip.get_length() > 0.05 and clip.get_length() <= 0.6, "Each production sound is a short decodable WAV")
		check(clip.loop_mode == AudioStreamWAV.LOOP_DISABLED and clip.format == AudioStreamWAV.FORMAT_16_BITS, "Short combat clips import as non-looping lossless PCM")
	check(audio.get_debug_state().active == 0 and fan.audio_manager == audio, "Map startup is silent and the weapon shares the global manager")
	player.global_position = wave.global_position + Vector3.UP * 0.03
	check(wave.start_run(), "Current wave starts normally")
	wave._spawn_queue.clear()
	player.global_position = scene.get_node("BattleArea").global_position + Vector3.UP * 0.03
	player.reset_physics_interpolation()
	(scene.get_node("MapEffects/Camera3D") as FollowCamera).snap_to_target()
	fan.apply_skill_level(1)
	fan.knockback_distance = 0.0
	fan.hit_landed.connect(func(_enemy, _damage): landed += 1)
	check(not fan.start_swing() and audio.get_debug_state().active == 0, "No target produces no swing or sound")
	var primary := enemy_at(Vector3(0, 0, -1.0))
	var left := enemy_at(Vector3(-0.9, 0, -1.5))
	var right := enemy_at(Vector3(0.9, 0, -1.5))
	check(fan.start_swing() and audio.get_debug_state().active == 0, "Anticipation remains silent")
	tick(0.05)
	check(audio.get_debug_state().active == 0 and fan._hit_audio_count == 0, "No sound before the visible sweep")
	tick(0.10)
	var sweep := voice(&"fan_sweep")
	check(sweep != null and sweep.playing and fan._sweep_audible, "Visible slash starts one global sweep voice")
	check(is_equal_approx(sweep.volume_db, fan.audio_volume_db) and sweep.bus == &"Combat", "Weapon gain routes through the common combat bus")
	check(absf(sweep.pitch_scale / fan.audio_pitch - 1.0) <= fan.audio_pitch_variation + 0.001, "Pitch variation stays within its configured range")
	tick(0.06)
	tick(0.08)
	check(landed == 3 and primary.health == 4990.0 and left.health == 4990.0 and right.health == 4990.0, "Audio throttling does not suppress group damage")
	check(fan._hit_audio_count >= 1 and fan._hit_audio_count <= 2 and audio.get_debug_state().merged > 0, "Local and global throttling preserve representative group impacts")
	check(is_equal_approx(voice(&"fan_hit").volume_db, fan.audio_volume_db + fan.hit_volume_db), "Impact gain is relative to sweep gain")
	var previous: AudioStream = sweep.stream
	prepare()
	check(fan.start_swing(), "Next swing starts independently")
	tick(0.12)
	sweep = voice(&"fan_sweep")
	check(sweep.stream != previous, "Consecutive sweeps use different variants")
	wave.set_combat_frozen(true)
	await settle(2)
	check(sweep.stream_paused, "Growth selection pauses the global combat voices")
	wave.set_combat_frozen(false)
	await settle(2)
	check(not sweep.stream_paused, "Weapon audio resumes after combat-only freeze")
	var blink_start := player.global_position
	player.global_position += Vector3.RIGHT
	player.blink_travelled.emit(blink_start, player.global_position)
	audio._process(0.0)
	check(voice(&"fan_sweep") == sweep and fan._swinging and not sweep.stream_paused and sweep.global_position.distance_to(fan.global_position) < 0.001, "Blink keeps the active sweep and moves its existing shared voice to the landing point")
	player.global_position = blink_start
	prepare()
	fan.audio_enabled = false
	var health := primary.health
	assert(fan.start_swing())
	tick(0.30)
	check(primary.health == health - 10.0 and voice(&"fan_sweep") == null and fan._hit_audio_count == 0, "Sound switch does not change damage")
	fan.audio_enabled = true
	prepare()
	fan.damage = 0.0
	assert(fan.start_swing())
	tick(0.30)
	check(voice(&"fan_sweep") != null and fan._hit_audio_count == 0, "Zero-damage preview plays the slash without false impact sounds")
	fan.damage = 10.0
	prepare()
	fan.hit_sound_limit = 0
	assert(fan.start_swing())
	tick(0.30)
	check(fan._hit_audio_count == 0 and voice(&"fan_sweep") != null, "Impact sounds can be disabled independently")
	fan.hit_sound_limit = 2
	prepare()
	fan.apply_skill_level(4)
	assert(fan.start_swing())
	tick(0.11)
	previous = voice(&"fan_sweep").stream
	tick(0.36)
	check(fan._combo_index == 1 and audio._last_clip[&"fan_sweep"] != previous, "Each combo segment has its own sweep sound")
	prepare()
	fan.apply_skill_level(8)
	tick(0.01)
	check(voice(&"fan_sweep") != null and is_equal_approx(voice(&"fan_sweep").volume_db, fan.audio_volume_db - 3.0), "Continuous rotation uses a quieter pulse")
	previous = voice(&"fan_sweep").stream
	for frame in 10: tick(0.01)
	check(audio._last_clip[&"fan_sweep"] == previous, "Rotation does not retrigger sound every frame or per blade")
	for frame in 50: tick(0.01)
	check(audio._last_clip[&"fan_sweep"] != previous and fan._hit_audio_count <= 2, "Rotation pulses and impacts stay bounded over time")
	fan.audio_enabled = false
	check(audio.get_debug_state().active == 0, "Live weapon mute stops its managed voices")
	fan.audio_enabled = true
	fan.apply_skill_level(1)
	prepare()
	assert(fan.start_swing())
	tick(0.12)
	wave._set_phase(WavePrototype.Phase.RESULT)
	check(audio.get_debug_state().active == 0, "Ending a run clears weapon audio")
	# Play every imported clip through a complete mixer cycle, including its tail.
	for clip in fan.sweep_sounds + fan.hit_sounds:
		var playback := audio.request({"source": fan, "cue": &"validation", "clips": [clip], "position": player.global_position})
		assert(playback != null)
		await playback.finished
		check(not playback.playing, "Every WAV ends naturally without looping")
	var catalog = load("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array = catalog.collect(scene)
	check(entries.any(func(entry): return entry.property == "audio_volume_db" and entry.category == "声音"), "Attack gain is searchable in the existing sound parameter category")
	print("Fan attack audio: %d checks, %d failures; timing, valid hits, global limits, combo/rotation, controls, freeze, blink continuity and full WAV playback" % [checks, failures.size()])
	scene.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)
