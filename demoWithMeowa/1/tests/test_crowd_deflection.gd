extends "res://tests/test_aim_path_preview.gd"

func group(center: Vector3, columns := 3, rows := 3) -> void:
	for row in rows:
		for column in columns:
			var actor := enemy(center + Vector3(column * 0.65, 0, (row - (rows - 1) * 0.5) * 0.65))
			actor.health = 1000.0

func fly(step: float) -> PackedVector3Array:
	var points := PackedVector3Array([player.global_position])
	check(body.release_charge(), "真实蓄力发射成功")
	for frame in ceili(6.0 / step) + 4:
		if not body.flying: break
		body.advance(step, Vector3.ZERO, false)
		points.append(player.global_position)
	return points

func clear() -> void:
	clear_enemies()
	await reset()

func path_checks() -> void:
	player.ricochet_rules.crowd_deflection_enabled = true
	player.ricochet_rules.enemy_push_enabled = false
	player.ricochet_rules.minimum_launch_speed = 8.0
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.ricochet_rules.flight_deceleration = 2.5
	player.sword.rules.enabled = false
	group(Vector3(2.6, 0, 0))
	var initial: Array[Vector3] = []
	for actor in session.enemies: initial.append(actor.global_position)
	var route := await predict()
	player.ricochet_rules.crowd_arc_degrees = 60.0
	var locked := AimPathData.new()
	body.predict_path(query, locked, 12.0, 1)
	check(locked.segments.back().end.is_equal_approx(route.segments.back().end), "蓄力中的绕群参数保持快照")
	player.ricochet_rules.crowd_arc_degrees = 120.0
	check(route.crowd_contacts.size() == 1 and route.segments.size() > 20, "识别相连怪群并沿外沿划弧")
	var expected: Vector3 = route.segments.back().end
	check(route.segments.all(func(piece): return piece.heading.dot(Vector3.RIGHT) >= -0.001), "正撞入弧沿来向连续掠过，不先后退再贴回怪群")
	check(expected.x > 3.5 and expected.z < -1.0, "绕过怪群侧方后朝前脱离，不在接触点折返")
	check(route.segments.back().heading.x > 0.5, "划弧结束后沿侧外方脱离，不继续绕圈")
	var steering := PlayerCrowdDeflection.new(body._settings, session)
	var contact := steering.contact(Vector3(0, 0.02, 0), Vector3(4, 0.02, 0), Vector3.RIGHT)
	var contact_point := Vector3(0, 0.02, 0).lerp(Vector3(4, 0.02, 0), contact.entry)
	check(steering.begin_contact(contact, contact_point, Vector3.RIGHT), "脱离检查建立真实接触弧线")
	var departing: Vector3 = -steering.step(contact_point, Vector3.RIGHT, 0.2).heading
	var released := steering.step(contact_point, departing, 0.4)
	check(released.heading.is_equal_approx(departing) and is_equal_approx(released.distance, 0.4) and steering._points.is_empty(), "人物已经弹开时保留当前方向，放弃旧弧线")
	check(steering.contact(contact_point, contact_point + Vector3.RIGHT, Vector3.RIGHT).is_empty(), "放弃旧弧线后不会立即被同群重新吸回")
	for index in initial.size():
		check(session.enemies[index].global_position == initial[index] and session.enemies[index].stun_remaining == 0.0, "预览不移动或眩晕怪物")
	var baseline := fly(1.0 / 60.0)
	check(body.crowd_deflection_count == 1 and body.bounce_count == 0, "同群只接入一次，沿群移动不算撞墙")
	check(TerrainPath.horizontal_distance(player.global_position, expected) < 0.025, "预览与真实胶囊路线终点一致")
	var minimum := INF
	for point in baseline:
		for target in initial: minimum = minf(minimum, TerrainPath.horizontal_distance(point, target))
	check(minimum > 0.55, "划弧沿外沿运动，不穿过密集怪群中心")
	check(session.enemies.all(func(actor): return actor.health == 1000.0), "绕群运动本身不额外造成撞击伤害")
	for index in initial.size():
		var actor := session.enemies[index]
		check(actor.global_position == initial[index] and actor.stun_remaining == 0.0 and actor._push_remaining == 0.0, "关闭直接拨怪与链式眩晕，怪物位置保持原状")
	for step in [1.0 / 30.0, 1.0 / 120.0, 0.25]:
		route = await predict()
		fly(step)
		check(TerrainPath.horizontal_distance(player.global_position, expected) < 0.025 and body.crowd_deflection_count == 1, "不同步长沿同一弧线：%.4f" % step)
	for formation in [Vector2i(6, 4), Vector2i(9, 1), Vector2i(1, 9)]:
		await clear()
		group(Vector3(2.6, 0, 0), formation.x, formation.y)
		route = await predict()
		check(route.segments.all(func(piece): return piece.heading.x >= -0.001), "不同群形的入弧都不向后吸附：%s" % formation)
		minimum = INF
		for piece in route.segments:
			for actor in session.enemies:
				var closest := Geometry2D.get_closest_point_to_segment(Vector2(actor.position.x, actor.position.z), Vector2(piece.start.x, piece.start.z), Vector2(piece.end.x, piece.end.z))
				minimum = minf(minimum, closest.distance_to(Vector2(actor.position.x, actor.position.z)))
		check(minimum > 0.55, "以接触点起弧仍保留怪物身体间距：%s / %.3f" % [formation, minimum])
	await clear()
	group(Vector3(2.6, 0, 0.45))
	route = await predict()
	var left: float = route.crowd_contacts[0].z
	var first_side: float = route.segments[mini(12, route.segments.size() - 1)].end.z
	await clear()
	group(Vector3(2.6, 0, -0.45))
	route = await predict()
	check(first_side < left and route.segments[mini(12, route.segments.size() - 1)].end.z > 0.0, "斜撞按入射趋势选择绕行侧方")
	await clear()
	var single := enemy(Vector3(2.6, 0, 0))
	route = await predict()
	check(route.crowd_contacts.size() == 1 and route.segments.back().heading.x > 0.5, "单怪使用自身圆心的小弧线并正常脱离")
	player.ricochet_rules.clockwise = false
	var reversed := await predict()
	check(route.segments.back().end.z * reversed.segments.back().end.z < 0.0 and absf(route.segments.back().end.z + reversed.segments.back().end.z) < 0.01, "正撞可通过旋向参数镜像到另一侧绕行")
	player.ricochet_rules.clockwise = true
	player.ricochet_rules.crowd_arc_degrees = 60.0
	var shorter := await predict()
	check(shorter.segments.size() < route.segments.size() and shorter.segments.back().heading.x < route.segments.back().heading.x, "绕行角度实际改变弧长与脱离方向")
	player.ricochet_rules.crowd_arc_degrees = 120.0
	player.ricochet_rules.crowd_arc_distance = 0.7
	var capped := await predict()
	check(capped.segments.back().heading.dot(route.segments.back().heading) < 0.9, "贴边路程上限能让人物提前脱离长弧")
	player.ricochet_rules.crowd_arc_distance = 4.0
	await clear()
	group(Vector3(2.6, 0, 0))
	route = await predict()
	var leg: Dictionary = route.segments.back()
	group(leg.start + leg.heading * 1.2 - Vector3.UP * 0.03)
	route = await predict()
	check(route.crowd_contacts.size() >= 2, "脱离第一群后可继续接入第二群")
	fly(1.0 / 60.0)
	check(body.crowd_deflection_count >= 2 and TerrainPath.horizontal_distance(player.global_position, route.segments.back().end) < 0.035, "连续怪群的真实运动与预览一致")
	await clear()
	group(Vector3(2.6, 0, 0))
	var wall := box(Vector3(2.3, 0.6, -1.6), Vector3(3.0, 1.2, 0.02))
	await settle()
	route = await predict(Vector3.RIGHT, 8)
	check(not route.contacts.is_empty(), "绕行弧上的薄墙真实截住人物")
	fly(1.0 / 60.0)
	check(body.bounce_count > 0 and TerrainPath.horizontal_distance(player.global_position, route.segments.back().end) < 0.06, "撞墙立即结束旧绕行，沿真实法线反弹")
	wall.queue_free()
	await clear()
	var behind := enemy(Vector3(2.6, 0, 0))
	wall = box(Vector3(1.0, 0.6, 0), Vector3(0.02, 1.2, 4))
	await settle()
	route = await predict(Vector3.RIGHT, 0)
	check(route.crowd_contacts.is_empty(), "隔墙怪群不提前改变路线")
	wall.queue_free()
	behind.spawn_delay = 1.0
	await settle()
	route = await predict()
	check(route.crowd_contacts.is_empty(), "预告中的怪物不触发绕行")
	behind.spawn_delay = 0.0
	behind.position.y = 2.0
	session._spatial_index.update(behind)
	route = await predict()
	check(route.crowd_contacts.is_empty(), "异层怪物不触发绕行")
	await clear()
	group(Vector3(2.6, 0, 0))
	route = await predict()
	check(body.release_charge(), "冻结检查发射")
	while body.crowd_deflection_count == 0 and body.flying: body.advance(1.0 / 60.0, Vector3.ZERO, false)
	var before := player.global_position
	var speed := body.flight_speed
	session.set_combat_frozen(true)
	body.advance(0.4, Vector3.ZERO, false)
	check(player.global_position == before and body.flight_speed == speed, "升级冻结保留绕群路线和速度")
	session.set_combat_frozen(false)
	while body.flying: body.advance(1.0 / 60.0, Vector3.ZERO, false)
	check(TerrainPath.horizontal_distance(player.global_position, route.segments.back().end) < 0.025, "恢复续接同一弧线")
	await clear()
	group(Vector3(2.6, 0, 0))
	player.sword.rules.enabled = true
	var hits := [0]
	player.sword.hit_landed.connect(func(_actor, _damage, flying):
		if flying: hits[0] += 1)
	var storm: RicochetStorm = load("res://scenes/combat/ricochet_storm.tscn").instantiate()
	storm.session = session
	storm.audio_enabled = false
	world.add_child(storm)
	storm.apply_skill_level(4)
	storm.set_physics_process(false)
	session._path_ready = true
	session._path = navigation
	session.combat_modifiers.damage_disabled = true
	for actor in session.enemies: actor.simulate_zero_damage_hits = true
	var lightning := {}
	storm.hit_landed.connect(func(actor, _damage): lightning[actor.get_instance_id()] = int(lightning.get(actor.get_instance_id(), 0)) + 1)
	await settle()
	storm.set_physics_process(false)
	route = await predict()
	check(body.release_charge(), "携带剑术与奔雷发射")
	for frame in 200:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		player.sword._physics_process(1.0 / 60.0)
		storm._physics_process(1.0 / 60.0)
	check(hits[0] > 0, "弹射挥剑沿真实弧线继续命中")
	check(not lightning.is_empty() and lightning.values().all(func(count): return count == 1), "奔雷沿实际路线传播，整次发射每怪仍最多一次")
	check(session.enemies.all(func(actor): return actor.stun_remaining == 0.0 and actor._push_remaining == 0.0), "剑术和奔雷回调也不触发旧拨怪或眩晕")
	check(not body.push_after_sword_hit(session.enemies[0], session.enemies[0].global_position, Vector3.RIGHT), "延后剑伤拨怪入口同样被关闭")
	body.cancel(true)
	check(body._crowd == null and body._push_wave == null, "取消清理弧线与接触记录")
	var formal: PlayerRicochetRules = load("res://data/player/body_ricochet.tres")
	check(formal.crowd_deflection_enabled and not formal.enemy_push_enabled and formal.validation_error().is_empty(), "正式 world 开启人物绕群并关闭拨怪")
	var offers := RunBuffs.new()
	offers.session = session
	for attribute in [GrowthBuffDefinition.Attribute.PUSH_RADIUS, GrowthBuffDefinition.Attribute.PUSH_FORCE, GrowthBuffDefinition.Attribute.PUSH_DURATION, GrowthBuffDefinition.Attribute.PUSH_STUN]:
		var definition := GrowthBuffDefinition.new()
		definition.id = StringName("disabled-push-%s" % attribute)
		definition.attribute = attribute
		offers.definitions.append(definition)
	check(offers.candidates().is_empty(), "关闭拨怪后四类拨怪增益均不进入升级池")
	session.combat_modifiers.damage_disabled = false
	var combined := GrowthBuffDefinition.new()
	combined.id = &"paid-damage"
	combined.attribute = GrowthBuffDefinition.Attribute.DAMAGE
	check(offers._has_effect(combined), "共享伤害成长仍然有效")
	var cost := GrowthBuffEffect.new()
	cost.attribute = GrowthBuffDefinition.Attribute.PUSH_FORCE
	cost.bonus_per_level = -0.1
	combined.extra_effects = [cost]
	check(not offers._has_effect(combined), "无法支付已关闭的拨怪代价时不提供免费组合收益")
	offers.free()
	clear_enemies()

func target_checks() -> void:
	pass
