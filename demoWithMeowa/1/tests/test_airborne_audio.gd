extends SceneTree

class Session extends Node:
	signal phase_changed(phase: int)
	signal combat_frozen_changed(frozen: bool)
	signal run_started
	var phase := WavePrototype.Phase.BATTLE
	var combat_frozen := false

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): quit(2))
	run.call_deferred()

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var map := Node3D.new()
	root.add_child(map)
	var session := Session.new()
	map.add_child(session)
	var audio := GameAudio.new()
	audio.load_local_mix = false
	audio.session = session
	audio.balance = load("res://data/audio/combat_balance_world.tres")
	map.add_child(audio)
	var rules: KillAudioRules = load("res://data/audio/kill_feedback_world.tres").duplicate()
	check(audio.has_signal("death_airborne") and "air_motion_enabled" in rules, "抛飞声音需要真实主体与空中生命周期")
	if not audio.has_signal("death_airborne") or not "air_motion_enabled" in rules:
		map.free()
		quit(1)
		return
	var bank: CoreSoundBank = load("res://data/audio/core_sound_bank_world.tres")
	var original: AudioStream = bank.clips_for(&"kill_air")[0]
	check(original.resource_path.ends_with("airborne_flutter.wav") and original.get_length() > 1.9, "S45 使用已选两秒素材")
	var driver := KillFeedbackAudio.new()
	driver.audio = audio
	driver.rules = rules
	driver.bank = bank
	driver.session = session
	map.add_child(driver)
	var first := Node3D.new()
	var second := Node3D.new()
	var third := Node3D.new()
	for subject in [first, second, third]: map.add_child(subject)
	audio.emit_signal(&"death_airborne", first, true)
	var voices := audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:kill_air")
	check(voices.size() == 1 and voices[0].source == first and voices[0].follow_source, "声音由真实尸体主体持有并跟随位置")
	if voices.is_empty():
		map.free()
		quit(1)
		return
	var voice: AudioStreamPlayer3D = voices[0].voice
	check(voice.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and voice.stream.get_meta(&"mix_source_path") == original.resource_path, "慢放中续接中段，仍共用原音源的本机增益")
	check(voice.volume_db <= driver.volume_db + audio.cue_gain_db(&"core:creature_death") - 6.0, "抛飞附属声低于死亡主音，不占主反馈")
	var played: int = audio.get_debug_state().played
	first.position = Vector3(1, 2, 3)
	audio._process(0)
	check(voice.global_position == first.position, "位置随空中主体移动，不固定在死亡点")
	audio.emit_signal(&"death_airborne", first, true)
	check(audio.get_debug_state().played == played, "同一主体持续在空中不重复起声")
	audio._process(.1)
	audio.emit_signal(&"death_airborne", second, true)
	audio._process(.1)
	audio.emit_signal(&"death_airborne", third, true)
	check(audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:kill_air").size() == 2, "密集抛飞最多两个代表声道")
	var before := voice.volume_db
	audio.emit_signal(&"death_airborne", first, false)
	driver._process(.03)
	check(voice.playing and voice.volume_db < before - 4.0, "落地立即开始短淡出")
	driver._process(.04)
	check(not audio._voices.any(func(slot): return slot.active and slot.source == first), "落地主体的声音快速结束")
	check(audio._voices.any(func(slot): return slot.active and slot.source == second), "一只落地不误停另一只仍在翻飞的声音")
	audio.emit_signal(&"death_airborne", second, false)
	audio.emit_signal(&"death_airborne", second, true)
	driver._process(.1)
	check(audio._voices.any(func(slot): return slot.active and slot.source == second), "对象池复用取消旧淡出，不截断新一轮翻飞")
	driver.clear()
	audio.stop_all()
	audio.max_voices = 1
	audio.emit_signal(&"death_airborne", first, true)
	var hurt := audio.request({"source":third, "cue":&"hurt", "clips":[original], "kind":GameAudio.Kind.HURT, "volume_db":-5.0})
	audio.emit_signal(&"death_airborne", first, false)
	driver._process(.1)
	check(hurt != null and hurt.playing and is_equal_approx(hurt.volume_db, -5.0), "被高优先级声音复用的声道不受旧落地淡出影响")
	driver.clear()
	audio.stop_all()
	audio.max_voices = 12
	audio.emit_signal(&"death_airborne", first, true)
	audio.emit_signal(&"death_airborne", first, false)
	session.combat_frozen = true
	audio.set_frozen(true)
	driver._process(.2)
	# AudioServer 在独立混音线程提交新声道的暂停状态。
	for frame in 2:
		await physics_frame
		await process_frame
	check(audio._voices.any(func(slot): return slot.active and slot.voice.stream_paused), "战斗冻结暂停声音及淡出时钟")
	session.combat_frozen = false
	audio.set_frozen(false)
	driver._process(.1)
	check(not audio._voices.any(func(slot): return slot.active), "恢复后完成原落地收尾")
	driver.clear()
	audio.stop_all()
	audio.emit_signal(&"death_airborne", first, true)
	check(audio._voices.any(func(slot): return slot.active and slot.source == first), "清波前主体确实处于空中播放状态")
	session.phase = WavePrototype.Phase.REST
	session.phase_changed.emit(session.phase)
	audio.emit_signal(&"death_airborne", first, false)
	driver._process(.1)
	check(not driver.is_processing() and not audio._voices.any(func(slot): return slot.active), "清波保留的尸体落地仍能结束声音并停止闲置处理")
	session.phase = WavePrototype.Phase.BATTLE
	audio.emit_signal(&"death_airborne", second, true)
	session.run_started.emit()
	check(not driver.is_processing() and not audio._voices.any(func(slot): return slot.active), "重试清理全部主体拥有的抛飞声音")
	map.queue_free()
	await process_frame
	print("Airborne audio: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
