extends "res://tests/test_crowd_deflection.gd"

func formation(name: String) -> Vector3:
	if name == "pair": group(Vector3(2.6, 0, 0), 2, 1)
	elif name == "side_pair":
		enemy(Vector3(2.6, 0, -0.4))
		enemy(Vector3(2.6, 0, 0.4))
	elif name == "graze": enemy(Vector3(2.6, 0, 1.17))
	elif name == "oblique": enemy(Vector3(2.6, 0, 0).rotated(Vector3.UP, PI / 6.0))
	else: enemy(Vector3(2.6, 0, 0))
	return Vector3.RIGHT.rotated(Vector3.UP, PI / 6.0) if name == "oblique" else Vector3.RIGHT

func path_checks() -> void:
	player.ricochet_rules = load("res://data/combat/scenes/world/player/body_ricochet.tres").duplicate()
	check(player.ricochet_rules.eccentric_minimum_members == 1 and PlayerRicochetRules.new().eccentric_minimum_members == 3, "World 独立开放单怪，默认资源保持原门槛")
	for minimum in [0, 4]:
		var invalid: PlayerRicochetRules = player.ricochet_rules.duplicate()
		invalid.eccentric_minimum_members = minimum
		check(not invalid.validation_error().is_empty(), "拒绝无效环绕成员门槛")
	# 固定耗速缩短逻辑回归，不改变正式地图的续航数值。
	player.ricochet_rules.flight_deceleration = 4.0
	player.sword.rules = load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate()
	player.sword.rules.audio_enabled = false
	session._path_ready = true
	session._path = navigation
	session.combat_modifiers.damage_disabled = true
	var storm: RicochetStorm = load("res://scenes/combat/ricochet_storm.tscn").instantiate()
	storm.session = session
	storm.audio_enabled = false
	world.add_child(storm)
	var sword_hits := {}
	var lightning := {}
	var rounds := [0]
	player.sword.hit_landed.connect(func(actor, _damage, flying):
		if flying: sword_hits[actor.get_instance_id()] = true)
	storm.discharge_started.connect(func(_point): rounds[0] += 1)
	storm.hit_landed.connect(func(actor, _damage): lightning[actor.get_instance_id()] = int(lightning.get(actor.get_instance_id(), 0)) + 1)
	for name in ["single", "pair", "side_pair", "graze", "oblique"]:
		for step in [1.0 / 30.0, 1.0 / 120.0]:
			var heading := formation(name)
			for actor in session.enemies: actor.health_loss_disabled = true
			storm.cancel_current()
			check(storm.apply_skill_level(1) and is_equal_approx(storm.get_attack_stats().range, 1.25), "使用无范围成长的一级奔雷")
			var route := await predict(heading, 8, 30.0)
			check(route.segments.any(func(piece): return piece.orbiting), "World 单怪与少量目标也能进入持续绕行：" + name)
			var plain := AimPathData.new()
			var batched := AimPathData.new()
			body.predict_path(query, plain, 8.0, 1, 1.0, false)
			body.predict_path(query, batched, 8.0, 1, 1.0, true)
			check(not plain.crowd_contacts.is_empty() and plain.crowd_contacts == batched.crowd_contacts and plain.segments.back().end.is_equal_approx(batched.segments.back().end), "普通与批量短预览同源：" + name)
			check(plain.segments.any(func(piece): return piece.orbiting) and plain.total_distance < 8.0, "蓄力只画首次绕行和短尾，不推演完整绕圈：" + name)
			sword_hits.clear()
			lightning.clear()
			rounds[0] = 0
			storm.set_physics_process(false)
			check(body.release_charge(), "单怪与小群真实发射")
			var orbit_distance := 0.0
			var clearance_ok := true
			for frame in ceili(6.0 / step):
				if not body.flying: break
				var before := player.global_position
				body.advance(step, Vector3.ZERO, false)
				if body.orbiting: orbit_distance += TerrainPath.horizontal_distance(before, player.global_position)
				for actor in session.enemies:
					clearance_ok = clearance_ok and TerrainPath.horizontal_distance(player.global_position, actor.global_position) >= actor.get_crowd_body_radius() + 0.24 - 0.015
				player.sword._physics_process(step)
				storm._physics_process(step)
			for frame in 20: storm._physics_process(0.05)
			check(orbit_distance > 3.0, "持续沿目标外侧续接，而非短弧后离开：%s / %s" % [name, step])
			check(clearance_ok, "小目标绕行保留怪物体型和人物胶囊间隔：" + name)
			check(body.crowd_deflection_count == 1, "绕行续段不重复接触计数与耗速：" + name)
			check(TerrainPath.horizontal_distance(player.global_position, route.segments.back().end) < 0.05, "小目标绕行的完整预览与真实终点一致：%s / %s" % [name, step])
			check(not sword_hits.is_empty() and not lightning.is_empty(), "提前转向后基础剑术和一级奔雷仍真实命中：" + name)
			check(lightning.values().all(func(count): return count <= rounds[0]), "持续绕行保留奔雷每轮每怪去重：" + name)
			check(session.enemies.all(func(actor): return actor.stun_remaining == 0.0 and actor._push_remaining == 0.0), "接入绕行不附加碰撞伤害、拨怪或眩晕")
			await clear()
	storm.queue_free()
	player.sword.rules.enabled = false
	session.combat_modifiers.damage_disabled = false
	await boundary_checks()

func boundary_checks() -> void:
	enemy(Vector3(2.6, 0, 0))
	var wall := box(Vector3(1.0, 0.6, 0), Vector3(0.05, 1.2, 4.0))
	await settle()
	var route := await predict(Vector3.RIGHT, 1, 8.0)
	check(route.crowd_contacts.is_empty() and not route.contacts.is_empty(), "单怪捕获仍遵守先到达的真实墙面")
	wall.queue_free()
	await clear()
	for index in 4: enemy(Vector3(2.6, 0, 0))
	route = await predict(Vector3.RIGHT, 8, 30.0)
	check(not route.segments.any(func(piece): return piece.orbiting), "完全重叠多怪仍回退短弧")
	await clear()
	player.ricochet_rules = load("res://data/combat/scenes/city/player/body_ricochet.tres").duplicate()
	player.ricochet_rules.flight_deceleration = 4.0
	enemy(Vector3(2.6, 0, 0))
	route = await predict(Vector3.RIGHT, 8, 30.0)
	check(not route.segments.any(func(piece): return piece.orbiting), "City 保留原有单怪短弧配置")
	await clear()
	player.ricochet_rules = load("res://data/combat/scenes/world/player/body_ricochet.tres").duplicate()
	player.ricochet_rules.flight_deceleration = 4.0
	var lone := enemy(Vector3(2.6, 0, 0))
	body.orbit_debug_enabled = true
	route = await predict(Vector3.RIGHT, 8, 30.0)
	player.ricochet_rules.eccentric_minimum_members = 3
	var locked := AimPathData.new()
	body.predict_path(query, locked, 30.0, 8)
	check(locked.segments.back().end.is_equal_approx(route.segments.back().end), "首次成员门槛与其它弹射参数一样固定本次蓄力快照")
	check(body.release_charge(), "单怪调试发射")
	for frame in 120:
		if body.orbiting or not body.flying: break
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
	var snapshot := body._crowd.debug_snapshot()
	check(body.orbiting and snapshot.members.size() == 1 and "相连 1 只" in snapshot.capture_reason, "既有调试读取真实单怪轮廓和接入原因")
	var before := player.global_position
	var speed := body.flight_speed
	session.set_combat_frozen(true)
	body.advance(0.2, Vector3.ZERO, false)
	check(player.global_position == before and body.flight_speed == speed and body.orbiting, "单怪绕行服从战斗冻结")
	session.set_combat_frozen(false)
	lone.dead = true
	body.advance(0.01, Vector3.ZERO, false)
	check(not body.orbiting and body.flying, "唯一目标死亡后沿余速离开，不围绕空点转圈")
	body.orbit_debug_enabled = false
	await clear()
	player.ricochet_rules = load("res://data/combat/scenes/world/player/body_ricochet.tres").duplicate()
	enemy(Vector3(2.6, 0, 0))
	await reset()
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "正式耗速下短按也可发射")
	for frame in 120:
		if body.orbiting or not body.flying: break
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
	check(body.orbiting, "短蓄力弹射也可接入单怪绕行")
	speed = body.flight_speed
	check(body.detach_from_crowd() and not body.orbiting and body.flight_speed == speed, "单怪绕行可右键沿切线脱离，保留余速")
	body.advance(0.2, Vector3.ZERO, false)
	check(body.flying and not body.orbiting and body.crowd_deflection_count == 1, "主动脱离后本次不再捕获单怪")

func target_checks() -> void:
	pass
