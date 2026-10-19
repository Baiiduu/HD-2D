extends "res://tests/test_core_feedback_audio.gd"

func physical_bounces() -> void:
	var balance: Resource = audio.get("balance")
	check(balance != null, "World 独立配置战斗声音平衡，不依赖本机加大全局音量")
	if not balance: return
	var city := FileAccess.get_file_as_string("res://scenes/city/city.tscn")
	check(not city.contains("combat_balance_world.tres"), "City 保留现有默认混音")
	var panel := world.get_node("AudioMixUI") as AudioMixUI
	var bank := feedback.sounds
	for cue in [&"enemy_hit_common", &"launch", &"player_hurt", &"kill_slime", &"storm_strike", &"storm_chain", &"leaf_windup", &"lantern_shot", &"frog_pulse", &"pot_shatter"]:
		check(not bank.clips_for(cue).is_empty(), "关键声音可独立试听：" + cue)
		reset_audio()
		panel._index = panel._entries.find_custom(func(entry): return entry.cue == cue)
		panel.menu_open = true
		panel.play_selected()
		var kind := GameAudio.Kind.HURT if cue == &"player_hurt" else GameAudio.Kind.ATTACK
		var event_cue: StringName = bank.call("playback_cue", cue)
		var base: float = panel._event_volume(cue) - float(audio.call("cue_gain_db", event_cue))
		var voice := audio.request({"source": feedback, "cue": event_cue, "clips": bank.clips_for(cue),
			"kind": kind, "position": player.global_position, "volume_db": base})
		check(voice != null and is_equal_approx(voice.volume_db, panel._preview.volume_db), "试听与真实播放叠加同一默认平衡：" + cue)
	panel.menu_open = false
	panel.stop_preview()
	reset_audio()
	var owners: Array[Node] = []
	for index in 20:
		var owner := Node.new()
		world.add_child(owner)
		owners.append(owner)
		audio.request({"source": owner, "cue": &"frog_pulse", "clips": bank.clips_for(&"frog_pulse"),
			"kind": GameAudio.Kind.DANGER, "position": player.global_position, "volume_db": -12.0})
	check(audio.get_debug_state().active == 1, "密集苔蛙鼓舞按全局间隔合并，不占满十二声道")
	var frog := audio._voices.filter(func(slot): return slot.active and slot.cue == &"frog_pulse")
	check(frog.size() == 1 and frog[0].priority < 40, "鼓舞无需使用人物危险提示优先级")
	feedback._play_world(&"enemy_hit_common", player.global_position, GameAudio.Kind.HIT, feedback.enemy_volume_db - feedback.action_volume_db)
	check(playing(&"core:enemy_hit_common"), "鼓舞密集时人物命中仍能播放")
	reset_audio()
	for owner in owners:
		audio.request({"source": owner, "cue": &"leaf_windup", "clips": bank.clips_for(&"leaf_windup"),
			"kind": GameAudio.Kind.DANGER, "position": player.global_position, "volume_db": -12.0})
	check(audio.get_debug_state().active == 1, "同瞬间冲锋预告仅留一个代表声，视觉预告不受影响")
	audio._process(0.2)
	audio.request({"source": owners[1], "cue": &"leaf_windup", "clips": bank.clips_for(&"leaf_windup"), "kind": GameAudio.Kind.DANGER, "position": player.global_position})
	audio._process(0.2)
	audio.request({"source": owners[2], "cue": &"leaf_windup", "clips": bank.clips_for(&"leaf_windup"), "kind": GameAudio.Kind.DANGER, "position": player.global_position})
	check(audio._voices.filter(func(slot): return slot.active and slot.cue == &"leaf_windup").size() <= 2, "危险预告也遵守此地图的独立同类上限")
	feedback._play_world(&"player_hurt", player.global_position, GameAudio.Kind.HURT, 1.0)
	check(playing(&"core:player_hurt"), "人物受伤保留最高优先级")
	reset_audio()
	feedback._play_world(&"enemy_hit_common", player.global_position, GameAudio.Kind.HIT, feedback.enemy_volume_db - feedback.action_volume_db)
	var hit := audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:enemy_hit_common")
	check(hit.size() == 1 and hit[0].priority > 40, "人物命中高于普通怪物动作，仍低于危险与受伤")
	var gain: float = audio.call("cue_gain_db", &"core:enemy_hit_common")
	audio.mix.set_clip_gain(hit[0].voice.stream.resource_path, -4.0)
	audio._process(0)
	check(is_equal_approx(hit[0].voice.volume_db, feedback.enemy_volume_db + gain - 4.0), "平衡增益不会覆盖本机单条音量")
	audio.mix.reset_all()
	for owner in owners: owner.queue_free()
	reset_audio()
