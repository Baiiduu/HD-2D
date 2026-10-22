extends "res://tests/test_core_feedback_audio.gd"

func physical_bounces() -> void:
	var shared: CoreSoundBank = load("res://data/audio/core_sound_bank.tres")
	check(feedback.sounds.clips_for(&"charge_wind") == shared.clips_for(&"charge_wind"), "正式场景保留已认可聚力风，不接入未经认可的候选")
	check(feedback.sounds.audition_entries().size() == 55, "保留原试听编号，新受伤提示追加末尾")
	check(feedback._charge_volume(1.0) - feedback._charge_volume(0.0) >= 6.0, "半秒内保留可辨的力量积累")
	check("charge_energy_audio_enabled" in feedback, "旧起手与循环可独立停用，满蓄确认仍保留")
	if "charge_energy_audio_enabled" in feedback:
		var map := FileAccess.get_file_as_string("res://scenes/world/world.tscn")
		check(map.contains("charge_energy_audio_enabled = false"), "World 明确只保留聚力风")
		player.body_ricochet.cancel(true)
		reset_audio()
		feedback.set("charge_energy_audio_enabled", false)
		check(player.body_ricochet.begin_charge(Vector3.RIGHT), "单风声模式可以真实开始蓄力")
		feedback._physics_process(0.02)
		check(playing(&"core:charge_wind") and not playing(&"core:charge_start") and not playing(&"core:charge_loop"), "起手即只有聚力风，不叠加旧蓄力声")
		player.body_ricochet.advance(0.9, Vector3.ZERO, false)
		feedback._physics_process(0.02)
		check(playing(&"core:charge_ready"), "关闭旧蓄力声后仍在真实满蓄时确认一次")
		var played: int = audio.get_debug_state().played
		feedback._physics_process(0.02)
		check(audio.get_debug_state().played == played and not playing(&"core:charge_loop"), "满蓄保持不重放提示、不重启旧循环")
		player.body_ricochet.cancel(true)
		feedback._physics_process(0.2)
		check(not playing(&"core:charge_wind"), "取消后聚力风正常收尾")
		feedback.set("charge_energy_audio_enabled", true)
	reset_audio()
	var owners: Array[Node] = []
	for index in 10:
		var source := Node.new()
		world.add_child(source)
		owners.append(source)
		audio.request({"source":source, "cue":StringName("busy_hit_%d" % index),
			"clips":shared.clips_for(&"enemy_hit_common"), "kind":GameAudio.Kind.ATTACK,
			"priority":60, "position":player.global_position})
	check(audio.get_debug_state().active >= 10, "模拟普通战斗声道已满")
	feedback._request_charge_loop(0.0)
	check(playing(&"core:charge_loop"), "怪群声音密集时蓄力主体当帧获得声道")
	reset_audio()
	for index in owners.size():
		audio.request({"source":owners[index], "cue":StringName("busy_wind_%d" % index),
			"clips":shared.clips_for(&"enemy_hit_common"), "kind":GameAudio.Kind.ATTACK,
			"priority":60, "position":player.global_position})
	feedback.set("charge_energy_audio_enabled", false)
	check(player.body_ricochet.begin_charge(Vector3.RIGHT), "密集声道中重新蓄力")
	feedback._physics_process(0.02)
	check(playing(&"core:charge_wind"), "聚力风作为唯一持续声时仍可即时取得声道")
	player.body_ricochet.cancel(true)
	feedback._physics_process(0.2)
	feedback.set("charge_energy_audio_enabled", true)
	for source in owners: source.queue_free()
	reset_audio()
