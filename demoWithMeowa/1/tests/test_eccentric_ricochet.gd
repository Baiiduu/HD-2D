extends "res://tests/test_crowd_deflection.gd"

const ECCENTRIC_GEOMETRY = preload("res://scripts/player/player_eccentric_ricochet.gd")

func finish_flight(step := 1.0 / 60.0) -> void:
	for frame in ceili(6.0 / step):
		if not body.flying: return
		body.advance(step, Vector3.ZERO, false)
	check(false, "偏心回旋仍须按余速在有限时间内结束")

func enter_arc() -> void:
	await predict()
	check(body.release_charge(), "偏心试玩可发射")
	for frame in 200:
		if body.crowd_deflection_count > 0 or not body.flying: break
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
	check(body.flying and body.crowd_deflection_count == 1, "进入首段真实接触短弧")
	if body.flying: body.advance(0.025, Vector3.ZERO, false)

func path_checks() -> void:
	terrain.data.resize(Vector2i(-16, -16), Vector2i(32, 32))
	player.ricochet_rules = load("res://data/player/body_ricochet.tres").duplicate()
	player.sword.rules.enabled = false
	var settings := player.ricochet_rules
	check(settings.eccentric_enabled and settings.crowd_deflection_enabled and not settings.enemy_push_enabled, "正式配置开启偏心试作，仍关闭拨怪")
	check(settings.validation_error().is_empty(), "正式偏心参数有效")
	# 本组比较完整有限路线；正式耗速可继续调参，不改变夹具的明确速度预算。
	settings.flight_deceleration = 4.0
	for property in [&"eccentric_step_distance", &"eccentric_edge_clearance", &"eccentric_outward_sway", &"eccentric_search_radius", &"eccentric_capture_margin"]:
		var invalid: PlayerRicochetRules = settings.duplicate()
		invalid.set(property, NAN)
		check(not invalid.validation_error().is_empty(), "拒绝非有限偏心参数：" + String(property))
	geometry_checks()
	await live_outline_checks()
	await automatic_orbit_checks()
	group(Vector3(2.6, 0, 0), 8, 7)
	var initial := PackedVector3Array()
	for actor in session.enemies: initial.append(actor.global_position)
	var route := await predict(Vector3.RIGHT, 8, 30.0)
	check(route.crowd_contacts.size() == 1 and route.segments.any(func(piece): return piece.get("orbiting", false)), "接群一次就持续环绕，续段不重复计算碰撞")
	var core := Vector3(4.875, 0.03, 0)
	var minimum := INF
	var body_clearance := INF
	for piece in route.segments:
		var nearest := Geometry2D.get_closest_point_to_segment(Vector2(core.x, core.z), Vector2(piece.start.x, piece.start.z), Vector2(piece.end.x, piece.end.z))
		minimum = minf(minimum, nearest.distance_to(Vector2(core.x, core.z)))
		for actor in session.enemies:
			var point := Vector2(actor.position.x, actor.position.z)
			var closest := Geometry2D.get_closest_point_to_segment(point, Vector2(piece.start.x, piece.start.z), Vector2(piece.end.x, piece.end.z))
			body_clearance = minf(body_clearance, closest.distance_to(point) - actor.get_crowd_body_radius() - 0.24)
	var coast_budget := settings.coast_distance(settings.maximum_launch_speed, settings.coast_seconds(settings.maximum_launch_speed))
	check(minimum > 2.5 and route.total_distance < coast_budget, "路线始终绕外围，不能缩径钻入群心，仍受速度预算约束")
	check(body_clearance >= settings.eccentric_edge_clearance - 0.015, "逐段路线保留人物与怪物实际体型之外的外沿间隔")
	var locked := AimPathData.new()
	settings.eccentric_enabled = false
	body.predict_path(query, locked, 30.0, 8)
	check(locked.segments.back().end.is_equal_approx(route.segments.back().end), "已开始蓄力的偏心开关保持快照")
	settings.eccentric_enabled = true
	var expected: Vector3 = route.segments.back().end
	var count := route.crowd_contacts.size()
	for step in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0, 0.25]:
		await predict(Vector3.RIGHT, 8, 30.0)
		fly(step)
		check(body.crowd_deflection_count == count and TerrainPath.horizontal_distance(player.global_position, expected) < 0.04, "实际运动、预览和多步长一致：%s" % step)
	for index in initial.size():
		var actor := session.enemies[index]
		check(actor.global_position == initial[index] and actor.health == 1000.0 and actor.stun_remaining == 0.0, "偏心路线自身不移动、伤害或眩晕怪物")
	for formation in [Vector2i(5, 5), Vector2i(12, 9), Vector2i(14, 1)]:
		await clear()
		group(Vector3(2.6, 0, 0), formation.x, formation.y)
		var perimeter := await predict(Vector3.RIGHT, 8, 30.0)
		check(perimeter.crowd_contacts.size() == 1, "小群、宽群和长条群都自动沿外围接续：%s" % formation)
		for piece in perimeter.segments:
			for actor in session.enemies:
				var point := Vector2(actor.position.x, actor.position.z)
				var nearest := Geometry2D.get_closest_point_to_segment(point, Vector2(piece.start.x, piece.start.z), Vector2(piece.end.x, piece.end.z))
				check(point.distance_to(nearest) >= actor.get_crowd_body_radius() + 0.24 + settings.eccentric_edge_clearance - 0.015, "全段保持体型外侧的间隔")
		await predict(Vector3.RIGHT, 8, 30.0)
		fly(0.25)
		check(TerrainPath.horizontal_distance(player.global_position, perimeter.segments.back().end) < 0.04, "大步长跨过续段边界仍保持路线：%s" % formation)
	await clear()
	group(Vector3(2.6, 0, 0), 8, 7)
	await enter_arc()
	var before := player.global_position
	var speed := body.flight_speed
	session.set_combat_frozen(true)
	check(not body.detach_from_crowd(), "升级冻结不接收主动脱离")
	body.advance(0.5, Vector3.ZERO, false)
	check(player.global_position == before and body.flight_speed == speed, "冻结保留偏心短弧和余速")
	session.set_combat_frozen(false)
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	check(not body.detach_from_crowd(), "管理界面占用输入时不接收脱离")
	blocker.free()
	var heading := body._crowd.departure_heading(player.global_position, body.direction)
	var event := InputEventAction.new()
	event.action = &"body_charge"
	event.pressed = true
	body._unhandled_input(event)
	body.advance(0.01, Vector3.ZERO, false)
	check(body.flying and body.direction.dot(heading) > 0.999 and is_equal_approx(body.flight_speed, speed - settings.flight_deceleration * 0.01), "右键二次按下沿外侧切线脱离，保留余速与正常衰减")
	check(body._crowd._eccentric.detached and not body.detach_from_crowd(), "同次飞行主动脱离只执行一次")
	var contacts := body.crowd_deflection_count
	event.pressed = false
	body._unhandled_input(event)
	finish_flight()
	check(body.crowd_deflection_count == contacts and not body.charging, "脱离后不重新接回怪群，松开右键不额外发射")
	await predict(Vector3.RIGHT, 8, 30.0)
	fly(1.0 / 60.0)
	check(body.crowd_deflection_count == count, "下一次发射重新启用偏心状态")
	var wall := box(Vector3(3, 0.6, -0.9), Vector3(3, 1.2, 0.02))
	await settle()
	route = await predict(Vector3.RIGHT, 16, 30.0)
	fly(1.0 / 60.0)
	check(not route.contacts.is_empty() and body.bounce_count > 0, "偏心短弧仍被真实薄墙截住并反射")
	check(TerrainPath.horizontal_distance(player.global_position, route.segments.back().end) < 0.06, "中途撞墙后预览与实际路线一致")
	wall.queue_free()
	await settle()
	player.sword.rules.enabled = true
	var original_angle := player.sword.rules.flight_angle
	player.sword.rules.flight_angle = 80.0
	var sword_hits := [0]
	var inward_strikes := [0]
	player.sword.strike_started.connect(func(direction, flying, _reverse):
		if flying and body.orbiting and absf(direction.dot(body.direction)) < 0.85: inward_strikes[0] += 1)
	player.sword.hit_landed.connect(func(_actor, _damage, flying):
		if flying: sword_hits[0] += 1)
	var storm: RicochetStorm = load("res://scenes/combat/ricochet_storm.tscn").instantiate()
	storm.session = session
	storm.audio_enabled = false
	world.add_child(storm)
	storm.apply_skill_level(4)
	storm.set_physics_process(false)
	session._path_ready = true
	session._path = navigation
	session.combat_modifiers.damage_disabled = true
	for actor in session.enemies: actor.health_loss_disabled = true
	var lightning := {}
	var rounds := [0]
	storm.discharge_started.connect(func(_point): rounds[0] += 1)
	storm.hit_landed.connect(func(actor, _damage): lightning[actor.get_instance_id()] = int(lightning.get(actor.get_instance_id(), 0)) + 1)
	await predict(Vector3.RIGHT, 8, 30.0)
	storm.set_physics_process(false)
	check(body.release_charge(), "携带剑术与奔雷的偏心弹射可以发射")
	for frame in 180:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		player.sword._physics_process(1.0 / 60.0)
		storm._physics_process(1.0 / 60.0)
	check(sword_hits[0] > 0, "自动挥剑消费真实偏心路线")
	check(inward_strikes[0] > 0, "沿外沿切向运动时仍自动转向附近怪物出剑")
	player.sword.rules.flight_angle = original_angle
	check(not lightning.is_empty() and lightning.values().all(func(value): return value <= rounds[0]), "同群持续环绕按技能间隔施放，每轮每怪最多一次")
	check(session.enemies.all(func(actor): return actor.stun_remaining == 0.0 and actor._push_remaining == 0.0), "偏心与攻击回调仍不拨怪或眩晕")
	storm.queue_free()
	player.sword.rules.enabled = false
	await clear()
	enemy(Vector3(2.6, 0, 0))
	route = await predict(Vector3.RIGHT, 8, 30.0)
	fly(1.0 / 60.0)
	check(route.crowd_contacts.size() == 1 and body.crowd_deflection_count == 1, "单怪沿原小弧线脱离，不形成向心自转")
	await clear()
	for index in 8: enemy(Vector3(2.6, 0, 0))
	route = await predict(Vector3.RIGHT, 8, 30.0)
	fly(1.0 / 60.0)
	check(route.crowd_contacts.size() == 1 and body.crowd_deflection_count == 1, "完全重叠的怪物不会靠不同 ID 在同点连跳")
	body.cancel(true)
	check(body._crowd == null and body.state == PlayerRicochet.State.IDLE, "取消释放本次偏心状态")

func live_outline_checks() -> void:
	group(Vector3(2.6, 0, 0), 6, 1)
	var steering := PlayerCrowdDeflection.new(player.ricochet_rules, session)
	var point := Vector3(1.55, 0.03, 0)
	var initial := steering._eccentric_outline(session.enemies[0], point)
	check(not initial.is_empty() and initial.positions.size() == 6 and is_equal_approx(initial.player_radius, 0.24), "外沿读取实时怪物位置、体型和人物实际胶囊")
	for index in range(3, 6):
		session.enemies[index].position.x += 2.2
		session._spatial_index.update(session.enemies[index])
	var split := steering._eccentric_outline(session.enemies[0], point)
	check(not split.is_empty() and split.positions.size() == 3, "怪群拆开后外沿不包含断开的旧成员")
	session.enemies[1].spawn_delay = 1.0
	session._spatial_index.update(session.enemies[1])
	check(steering._eccentric_outline(session.enemies[0], point).is_empty(), "预告对象不提供有效群体外沿")
	session.enemies[1].spawn_delay = 0.0
	session._spatial_index.update(session.enemies[1])
	var wall := box(Vector3(3.6, 0.6, 0), Vector3(0.02, 1.2, 4))
	await settle()
	check(steering._eccentric_outline(session.enemies[0], point).is_empty(), "真实挡墙隔开外沿样本，不能隔墙接群")
	wall.queue_free()
	await clear()

func geometry_checks() -> void:
	var settings := player.ricochet_rules
	var geometry := ECCENTRIC_GEOMETRY.new(settings)
	var surface := {"positions": PackedVector3Array([Vector3(1.05, 0, 0), Vector3(1.7, 0, 0.65), Vector3(1.7, 0, -0.65)]), "body_radius": 0.28, "player_radius": 0.24}
	var points := geometry.build(Vector3.ZERO, Vector3.RIGHT, surface)
	check(not points.is_empty() and points[0].x > 0.0, "曲线从真实接触点向前接入，不吸附到别处")
	for index in 20:
		points = geometry.build(points[-1], geometry.outgoing, surface)
		check(not points.is_empty() and geometry.turning, "不需要新接触，外围曲线可以持续续接")
	geometry.detach()
	check(geometry.build(points[-1], geometry.outgoing, surface).is_empty(), "主动脱离后拒绝本次所有新贴边段")
	geometry = ECCENTRIC_GEOMETRY.new(settings)
	check(geometry.build(Vector3(1.5, 0, 0), Vector3.RIGHT, surface).is_empty() and not geometry.detached, "起点已在群内时拒绝强行吸附，但保留后续接群资格")
	geometry = ECCENTRIC_GEOMETRY.new(settings)
	geometry.build(Vector3.ZERO, Vector3.RIGHT, surface)
	var departure := geometry.departure_heading(Vector3.ZERO, Vector3.RIGHT)
	check(departure.x <= 0.0 and is_equal_approx(departure.length(), 1.0), "主动脱离去除向怪群内部的速度方向分量")

func automatic_orbit_checks() -> void:
	group(Vector3(2.6, 0, 0), 5, 5)
	var sword := player.sword
	var stats := sword.get_stats(true)
	stats.angle = 50.0
	var origin := Vector3(1.55, 0.03, 0)
	var straight := sword._first_target(origin, origin, Vector3.FORWARD, stats)
	var inward := sword._first_target(origin, origin, Vector3.FORWARD, stats, true)
	check(float(straight.entry) < 0.0 and is_zero_approx(inward.entry) and inward.heading.dot(Vector3.RIGHT) > 0.95, "环绕出剑独立于切线，只向真实可触及的近处目标转向")
	var settings := player.ricochet_rules
	var previous_drag := settings.flight_deceleration
	var previous_speed := settings.maximum_launch_speed
	# 明确提供足够绕完一圈的速度预算，避免正式起步调参改变本项验证前提。
	settings.maximum_launch_speed = maxf(previous_speed, 16.0)
	settings.flight_deceleration = 5.0
	await predict()
	check(body.release_charge(), "足够速度预算的连续环绕可以发射")
	var center := Vector3(3.9, 0, 0)
	var winding := 0.0
	for frame in 400:
		if not body.flying: break
		var before := player.global_position - center
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		var after := player.global_position - center
		winding += Vector2(before.x, before.z).angle_to(Vector2(after.x, after.z))
	check(absf(winding) > TAU and body.crowd_deflection_count == 1, "余速足够可自动绕完一整圈，途中不需要第二次碰群")
	settings.flight_deceleration = previous_drag
	settings.maximum_launch_speed = previous_speed
	await enter_arc()
	check(body.orbiting, "进入持续环绕状态")
	var seed := body._crowd._orbit_seed
	seed.dead = true
	body.advance(0.01, Vector3.ZERO, false)
	check(body.orbiting and body._crowd._orbit_seed != seed, "支点死亡后使用同群存活成员继续环绕")
	for actor in session.enemies: actor.dead = true
	body.advance(0.01, Vector3.ZERO, false)
	check(not body.orbiting and body.flying, "怪群清空后停止自动环绕并沿余速离开")
	await clear()
	group(Vector3(2.6, 0, 0), 5, 5)
	await enter_arc()
	var before := player.global_position
	check(not body.advance(0.01, Vector3.FORWARD, false) and not body.flying and body._crowd == null and player.global_position == before, "怪群自动环绕期间也可用移动输入立即停止并交回行走")
	await clear()
