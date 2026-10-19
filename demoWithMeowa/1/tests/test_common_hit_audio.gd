extends "res://tests/test_core_feedback_audio.gd"

func physical_bounces() -> void:
	var bank := feedback.sounds
	var entries := bank.audition_entries()
	check(bank.clips_for(&"kill_slime").size() == 1 and bank.clips_for(&"kill_slime")[0].resource_path.ends_with("slime_kill_02.wav"), "史莱姆击杀池只保留变体二")
	check(entries[41].id == "S42" and entries[41].purpose.contains("停用") and entries[42].clip.resource_path.ends_with("slime_kill_02.wav"), "停用候选留作对照，S42／S43 编号不漂移")
	check(feedback.get("common_hit_enabled") == true, "World 明确启用通用命中池")
	var clips := bank.clips_for(&"enemy_hit_common")
	check(clips.size() == 3, "通用真实命中登记三条独立音源")
	if clips.size() != 3 or feedback.get("common_hit_enabled") != true: return
	var city := FileAccess.get_file_as_string("res://scenes/city/city.tscn")
	check(not city.contains("common_hit_enabled = true"), "City 保留当前声音配置")
	var sword := player.sword
	check(sword.rules.hit_sounds.is_empty(), "World 停用攻击组件的第二份旧命中声")
	check(load("res://data/player/basic_sword.tres").hit_sounds.size() == 2, "共享旧剑术音源仍保留")
	check(wave._spawn_enemy(), "保留活怪隔离清波与声音路由")
	var guard := wave.enemies[-1]
	guard.set_wave_tick_enabled(false)
	guard.health = 100000.0
	check(wave._spawn_enemy(), "真实怪物用于受击链路验证")
	var target := wave.enemies[-1]
	target.set_wave_tick_enabled(false)
	target.spawn_delay = 0.0
	target.global_position = player.global_position + Vector3.RIGHT
	target.commit_spatial_state()
	target.health = 100000.0
	sword.rules.enabled = true
	sword.set_physics_process(false)
	reset_audio()
	sword._play_sound(false, player.global_position)
	check(audio.get_debug_state().active == 0, "空挥没有通用怪物命中声")
	for flying in [false, true]:
		reset_audio()
		var before := target.health
		sword._pending_hits.append({"enemy": target, "damage": 1.0, "flying": flying,
			"heading": Vector3.RIGHT, "origin": player.global_position, "time": 0.0})
		sword._drain_hits()
		check(target.health == before - 1.0 and playing(&"core:enemy_hit_common"), "普通／弹射攻击的真实结算触发通用命中：%s" % flying)
		check(audio.get_debug_state().active == 1 and not playing(&"basic_sword_hit") and not playing(&"core:enemy_hit_soft"), "单次命中只随机一条，不重复旧入口")
	var previous: AudioStream
	for index in 10:
		reset_audio()
		target.take_damage(1.0, {"source": &"basic_sword"})
		var voices := audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:enemy_hit_common")
		check(voices.size() == 1 and voices[0].voice.stream in clips, "随机使用通用池成品")
		if voices.size() == 1:
			check(voices[0].voice.stream != previous, "可用变体多于一条时不连续重复")
			previous = voices[0].voice.stream
	reset_audio()
	for index in 100: target.take_damage(1.0, {"source": &"flight_sword"})
	check(audio.get_debug_state().active == 1, "密集一百次真实命中沿用公共节流，不叠一百条声音")
	reset_audio()
	target.health_loss_disabled = true
	var simulated_health := target.health
	target.take_damage(10.0, {"source": &"flight_sword"})
	check(target.health == simulated_health and not target.dead and playing(&"core:enemy_hit_common") and not playing(&"core:kill_slime"), "巨量免死模拟仍有命中声，不伪造击杀")
	target.health_loss_disabled = false
	reset_audio()
	target.take_damage(1.0, {"source": &"ricochet_storm"})
	check(audio.get_debug_state().active == 0, "奔雷继续按片发声，不逐怪叠通用命中")
	reset_audio()
	feedback.set("hit_material_layer_enabled", true)
	target.take_damage(1.0, {"source": &"basic_sword"})
	check(playing(&"core:enemy_hit_common") and playing(&"core:enemy_hit_soft") and audio.get_debug_state().active == 2, "可选混合模式只加一条轻材质层")
	var material := audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:enemy_hit_soft")
	check(material.size() == 1 and is_equal_approx(material[0].gain_db, feedback.enemy_volume_db + float(feedback.get("hit_material_gain_db"))), "材质层音量比通用主音更轻")
	for index in 100: target.take_damage(1.0, {"source": &"basic_sword"})
	check(audio.get_debug_state().active == 2, "混合层同样合并密集命中")
	reset_audio()
	var original_definition := target.definition
	target.definition = load("res://data/enemies/pot_brood.tres")
	target.take_damage(1.0, {"source": &"flight_sword"})
	check(playing(&"core:enemy_hit_common") and playing(&"core:enemy_hit_hard") and audio.get_debug_state().active == 2, "硬壳怪也使用通用主音，仅轻材质层区分身体")
	target.definition = original_definition
	for clip in clips: audio.mix.set_clip_muted(clip.resource_path, true)
	reset_audio()
	target.take_damage(1.0, {"source": &"basic_sword"})
	check(audio.get_debug_state().active == 0, "通用主音全静音时不漏出孤立材质层")
	audio.mix.reset_all()
	feedback.set("hit_material_layer_enabled", false)
	reset_audio()
	feedback.enabled = false
	target.take_damage(1.0, {"source": &"basic_sword"})
	check(audio.get_debug_state().active == 0, "核心声音总开关关闭统一命中")
	feedback.enabled = true
	wave.set_combat_frozen(true)
	feedback._enemy_damaged(CombatDamageEvent.from_hit(target, 1.0, 1.0, {"source": &"basic_sword"}), target)
	check(audio.get_debug_state().active == 0, "冻结期间不创建新的统一命中声")
	wave.set_combat_frozen(false)
	reset_audio()
	target.take_damage(target.health + 1.0, {"source": &"basic_sword"})
	check(playing(&"core:kill_slime") and not playing(&"core:enemy_hit_common"), "致死优先击杀确认，不叠满普通命中")
	var kills := audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:kill_slime")
	check(kills.size() == 1 and kills[0].voice.stream.resource_path.ends_with("slime_kill_02.wav"), "真实击杀不会再抽到被否定的变体一")
	feedback._kills.clear()
	guard.cancel()
	wave.enemies.erase(guard)
	sword.rules.enabled = false
	sword.cancel()
	await settle()
	reset_audio()
