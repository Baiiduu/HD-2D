extends "res://tests/test_crowd_deflection.gd"

func path_checks() -> void:
	terrain.data.resize(Vector2i(-16, -16), Vector2i(32, 32))
	player.ricochet_rules = load("res://data/player/body_ricochet.tres").duplicate()
	# 完整路线对比使用固定耗速，独立于正式资源正在调整的续航。
	player.ricochet_rules.flight_deceleration = 4.0
	player.sword.rules.enabled = false
	# 前排中间有缝但三只仍然相连；旧的单怪触发圆会晚于整群安全外沿。
	for angle in [0.0, PI / 6.0, -PI / 6.0]:
		var center := Vector3(3, 0, 0)
		for offset in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(0.65, 0, 0)]:
			enemy(center + offset.rotated(Vector3.UP, angle))
		var route := await predict(Vector3.RIGHT, 8, 30.0)
		check(route.segments.any(func(piece): return piece.orbiting), "正撞／斜撞前排缝隙都能提前接入外围：%s" % angle)
		fly(1.0 / 60.0)
		check(body.crowd_deflection_count > 0 and TerrainPath.horizontal_distance(player.global_position, route.segments.back().end) < 0.04, "缝隙接群的实际路线与预览一致：%s" % angle)
		await clear()

	group(Vector3(2.6, 0, 0), 3, 3)
	var steering := PlayerCrowdDeflection.new(player.ricochet_rules, session)
	var inside := Vector3(2.6, 0.03, 0)
	check(steering.begin_contact({"enemy": session.enemies[0]}, inside, Vector3.RIGHT), "已在外包线内时回退基础短弧，不直接穿过")
	check(not steering.orbiting and not steering._eccentric.detached, "首次安全校验失败不冒充主动脱离，后续仍可接其它群")
	check(not steering._points.is_empty(), "回退保留从当前位置出发的连续路线")
	group(Vector3(9, 0, 0), 3, 3)
	var later := steering.contact(Vector3(6, 0.03, 0), Vector3(10, 0.03, 0), Vector3.RIGHT)
	check(not later.is_empty(), "首次未能环绕不禁用本次飞行的其它怪群")
	check(steering.detach() and steering.contact(Vector3(6, 0.03, 0), Vector3(10, 0.03, 0), Vector3.RIGHT).is_empty(), "明确主动脱离仍禁用本次后续接群")
	await clear()
	var lone := enemy(Vector3(2.2, 0, 0.9))
	for offset in [Vector3(0, 0, 0), Vector3(0.65, 0, 0), Vector3(0.65, 0, -0.65)]:
		enemy(Vector3(2.3, 0, -1) + offset)
	steering = PlayerCrowdDeflection.new(player.ricochet_rules, session)
	var earlier := steering.contact(Vector3(0, 0.03, 0), Vector3(5, 0.03, 0), Vector3.RIGHT)
	check(not earlier.is_empty() and earlier.enemy != lone and not earlier.focus.is_empty(), "单怪收回近身距离后，仍按实际最早接触选择另一侧的可环绕群")
	await clear()
	await storm_reach_checks()

func storm_reach_checks() -> void:
	var storm: RicochetStorm = load("res://scenes/combat/ricochet_storm.tscn").instantiate()
	storm.session = session
	storm.audio_enabled = false
	world.add_child(storm)
	session._path_ready = true
	session._path = navigation
	session.combat_modifiers.damage_disabled = true
	var hits := {}
	var rounds := [0]
	storm.discharge_started.connect(func(_point): rounds[0] += 1)
	var sword_hits := {}
	player.sword.rules.enabled = true
	player.sword.hit_landed.connect(func(actor, _damage, flying):
		if flying: sword_hits[actor.get_instance_id()] = true)
	storm.hit_landed.connect(func(actor, _damage): hits[actor.get_instance_id()] = int(hits.get(actor.get_instance_id(), 0)) + 1)
	for formation in ["single", "pair", "overlap", "crowd", "gap", "graze"]:
		for step in [1.0 / 30.0, 1.0 / 120.0]:
			storm.cancel_current()
			hits.clear()
			rounds[0] = 0
			sword_hits.clear()
			if formation == "single": enemy(Vector3(2.6, 0, 0))
			elif formation == "pair": group(Vector3(2.6, 0, 0), 2, 1)
			elif formation == "overlap":
				for index in 5: enemy(Vector3(2.6, 0, 0))
			elif formation == "graze": enemy(Vector3(2.6, 0, 1.1))
			elif formation == "crowd": group(Vector3(2.6, 0, 0), 3, 3)
			else:
				for offset in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(0.65, 0, 0)]:
					enemy(Vector3(3, 0, 0) + offset)
			for actor in session.enemies: actor.health_loss_disabled = true
			check(storm.apply_skill_level(1) and is_equal_approx(storm.get_attack_stats().range, 1.25), "使用无范围成长的一级奔雷")
			await predict(Vector3.RIGHT, 8, 30.0)
			storm.set_physics_process(false)
			check(body.release_charge(), "携带一级奔雷发射")
			for frame in ceili(6.0 / step):
				if not body.flying: break
				body.advance(step, Vector3.ZERO, false)
				player.sword._physics_process(step)
				storm._physics_process(step)
			for frame in 20: storm._physics_process(0.05)
			check(not hits.is_empty(), "接群转向后一级奔雷仍能切入命中：%s / %s" % [formation, step])
			if formation == "graze":
				check(body.crowd_deflection_count == 0, "只有进入提前捕获圆的单怪不应改变实际近身路线")
			else:
				check(not sword_hits.is_empty(), "同一路线的基础剑术仍可命中：%s / %s" % [formation, step])
			check(hits.values().all(func(count): return count <= rounds[0]), "接群调整保留每轮去重，持续环绕允许下一轮再次命中")
			await clear()
	storm.queue_free()
	player.sword.rules.enabled = false
	session.combat_modifiers.damage_disabled = false

func target_checks() -> void:
	pass
