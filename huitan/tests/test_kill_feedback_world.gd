extends "res://tests/test_core_feedback_audio.gd"

func physical_bounces() -> void:
	await super.physical_bounces()
	check(feedback.kill_audio_rules != null and feedback._kills != null, "World 明确启用击杀声音驱动")
	var city_text := FileAccess.get_file_as_string("res://scenes/city/city.tscn")
	check(not city_text.contains("kill_feedback_world.tres") and not city_text.contains("kill_audio_rules ="), "City 不自动启用新的击杀声音配置")
	check(wave._spawn_enemy(), "保留一只活怪，隔离清波回调")
	var guard := wave.enemies[-1]
	guard.set_wave_tick_enabled(false)
	guard.health = 1000.0
	var count_before := wave.kills
	var health_before := player.current_health
	feedback._kills.clear()
	reset_audio()
	var corpses: Array[EnemyDeathEffect] = []
	for index in 3:
		check(wave._spawn_enemy(), "真实创建并绑定击杀声音：%d" % index)
		var target := wave.enemies[-1]
		target.global_position = player.global_position + Vector3(1.0, 0, index * .05)
		target.commit_spatial_state()
		target.health = 1.0
		target.take_damage(10.0, {"source": &"flight_sword", "motion_velocity": Vector3.RIGHT * 12.0})
		check(target.dead, "击杀声音不延后真实死亡")
	check(playing(&"core:kill_slime") and not playing(&"core:enemy_hit_soft") and not playing(&"core:slime_death"), "真实致死使用专属确认，不叠加完整旧受击与死亡声")
	check(wave.kills == count_before + 3 and player.current_health == health_before, "听感层保留真实击杀计数与人物生命")
	feedback._kills._process(.11)
	check(playing(&"core:kill_group"), "实际相邻三杀通过公共预算播放一次群杀强调")
	var pool := wave._attack_root.get_node_or_null("EnemyFeedbackPool") as EnemyFeedbackPool
	if pool:
		for child in pool.get_children():
			if child is EnemyDeathEffect and child.is_processing() and not child.get("_burst_only"):
				corpses.append(child)
	for corpse in corpses:
		corpse.set_process(false)
		corpse._process(corpse._pause_seconds + .01)
	check(playing(&"core:kill_air"), "真实死亡演出经反馈池触发抛飞气流")
	for corpse in corpses: corpse._process(corpse._air_seconds)
	check(playing(&"core:kill_land"), "真实落地段触发轻落地音")
	feedback.enabled = false
	reset_audio()
	audio.death_presentation.emit(&"air", player.global_position)
	check(not playing(&"core:kill_air") and not feedback._kills.is_processing(), "关闭核心反馈后尸体阶段也不继续发声")
	feedback.enabled = true
	feedback._kills.clear()
	for corpse in corpses: corpse._process(10.0)
	guard.cancel()
	wave.enemies.erase(guard)
	reset_audio()
