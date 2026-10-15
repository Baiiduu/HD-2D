extends "res://tests/test_aim_path_preview.gd"

## 统一速度的真实胶囊回归；空地足够容纳完整滑行，独立检查地形终止。
var reasons: Array[StringName] = []

func complete(step := 1.0 / 60.0) -> void:
	for frame in ceili(30.0 / step):
		if not body.flying: return
		body.advance(step, Vector3.ZERO, false)
	check(false, "正耗速必须在有限时间内结束")

func path_checks() -> void:
	terrain.data.resize(Vector2i(-16, -16), Vector2i(32, 32))
	await settle()
	var settings := player.ricochet_rules
	player.sword.rules.enabled = false
	settings.flight_seconds = 0.01
	settings.wall_bounce_limit = 0
	body.finished.connect(func(reason): reasons.append(reason))
	check(settings.validation_error().is_empty(), "旧时间与次数字段不影响新规则校验")
	check(is_equal_approx(settings.coast_seconds(8.0), 2.4), "初速 8、耗速 2.5、下限 2 的无碰撞余时为 2.4 秒")
	check(is_equal_approx(settings.coast_distance(8.0, 100.0), 12.0), "自然减速到下限只移动 12 米，不超时多滑")
	check(settings.can_rebound(2.6, 1.0) and not settings.can_rebound(2.5, 1.0), "碰撞消耗后仍须高于最低维持速度")
	check(is_equal_approx(settings.rebound_speed(8.0, 1.0), 7.5), "百分之百保速仍扣固定耗速")
	for property in [&"minimum_bounce_speed", &"flight_deceleration", &"bounce_speed_cost"]:
		var invalid: PlayerRicochetRules = settings.duplicate()
		invalid.set(property, NAN)
		check(not invalid.validation_error().is_empty(), "拒绝非有限速度配置：" + String(property))
	var phase := PlayerRicochetRules.segment_fraction(0.25, 0.5, 8.0, 2.5)
	check(phase > 0.5 and is_equal_approx(PlayerRicochetRules.segment_time(phase, 0.5, 8.0, 2.5), 0.25), "减速片段按真实运动时间采样，正反换算一致")
	for step in [1.0 / 30.0, 1.0 / 120.0, 0.4]:
		var route := await predict(Vector3.RIGHT, 32, 100.0)
		check(body.release_charge(), "速度模式可发射")
		complete(step)
		check(TerrainPath.horizontal_distance(player.global_position, route.segments.back().end) < 0.02, "不同步长的真实滑行与预览终点一致")
		check(absf(player.global_position.x - 12.0) < 0.001 and body.flight_speed == 0.0, "自然收势后速度归零，旧 0.01 秒不截断飞行：step=%s point=%s speed=%s reason=%s" % [step,player.global_position,body.flight_speed,reasons.back()])
	await predict()
	check(body.release_charge(), "冻结测试可发射")
	body.advance(0.9, Vector3.ZERO, false)
	check(body.flying and is_equal_approx(body.flight_speed, 5.75), "到旧版 0.9 秒仍有速度就继续飞行")
	var position := player.global_position
	var speed := body.flight_speed
	session.set_combat_frozen(true)
	body.advance(0.5, Vector3.ZERO, false)
	check(body.flight_speed == speed and player.global_position == position, "升级冻结不消耗速度")
	session.set_combat_frozen(false)
	complete()
	check(reasons.back() == &"speed_depleted", "由速度耗尽收势：%s / %s" % [reasons.back(),player.global_position])
	await reset()
	var wall := box(Vector3(3, 0.6, 0), Vector3(0.02, 1.2, 8))
	await settle()
	await predict(Vector3.RIGHT, 32, 100.0)
	body.release_charge()
	body.bounce_count = 1000
	body.advance(0.5, Vector3.ZERO, false)
	check(body.bounce_count == 1001 and body.direction.x < 0.0, "已有反弹统计不能限制下一次有效反弹")
	wall.queue_free()
	await settle()
	await reset()
	settings.minimum_bounce_speed = 7.0
	wall = box(Vector3(3, 0.6, 0), Vector3(0.02, 1.2, 8))
	await settle()
	var route := await predict(Vector3.RIGHT, 32, 100.0)
	check(route.end_reason == &"speed_depleted", "预览在碰撞后速度不足时终止")
	body.release_charge()
	complete()
	check(body.bounce_count == 0 and player.global_position.x < 2.8, "能碰到墙但不足以续弹时在接触处停止")
	settings.minimum_bounce_speed = 2.0
	wall.queue_free()
	await settle()
	await reset()
	for x in [-1.0, 1.0]: box(Vector3(x, 0.6, 0), Vector3(0.2, 1.2, 6))
	settings.minimum_launch_speed = 16.0
	settings.maximum_launch_speed = 16.0
	settings.flight_deceleration = 0.25
	settings.bounce_speed_cost = 0.15
	await settle()
	await predict(Vector3.RIGHT, 128, 100.0)
	body.release_charge()
	body.advance(2.0, Vector3.ZERO, false)
	check(body.bounce_count > 8 and body.flying, "同一物理步可多次有效反弹，不被原八次接触保护截断")
	body.advance(100.0, Vector3.ZERO, false)
	check(body.bounce_count > 20 and not body.flying and reasons.back() == &"speed_depleted", "超过旧反弹数仍可续弹，最终按耗速结束")
	for child in world.get_children():
		if child is StaticBody3D and child != terrain: child.queue_free()
	await settle()
	settings.minimum_launch_speed = 8.0
	settings.maximum_launch_speed = 8.0
	settings.flight_deceleration = 2.5
	settings.bounce_speed_cost = 0.5
	settings.crowd_deflection_enabled = true
	enemy(Vector3(2.6,0,0))
	enemy(Vector3(3.2,0,0.3))
	await predict(Vector3.RIGHT, 32, 100.0)
	body.release_charge()
	complete()
	check(body.crowd_deflection_count == 1 and body.flight_speed == 0.0, "怪群偏转同样受统一耗速控制，并保留同群锁")
	clear_enemies()
	settings.crowd_deflection_enabled = false
	var a := GrowthBuffDefinition.Attribute
	var modifiers := session.combat_modifiers
	var benefit := GrowthBuffDefinition.new()
	benefit.id = &"speed_test:drag"
	benefit.attribute = a.RICOCHET_DURATION
	benefit.bonus_per_level = 0.2
	modifiers.apply_buff(benefit)
	check(is_equal_approx(body.get_stats().flight_deceleration, 2.5 / 1.2), "旧时长成长改为降低飞行耗速")
	benefit = GrowthBuffDefinition.new()
	benefit.id = &"speed_test:impact"
	benefit.attribute = a.RICOCHET_BOUNCES
	benefit.bonus_per_level = 0.2
	modifiers.apply_buff(benefit)
	check(is_equal_approx(body.get_stats().bounce_speed_cost, 0.5 / 1.2), "旧次数成长改为降低碰撞耗速")
	modifiers.reset()
	player.owner = world
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(world)
	for property in ["minimum_bounce_speed", "flight_deceleration", "bounce_speed_cost"]:
		check(entries.any(func(item): return item.property == property and item.common), "关键速度参数在总览可调：" + property)

func target_checks() -> void:
	pass
