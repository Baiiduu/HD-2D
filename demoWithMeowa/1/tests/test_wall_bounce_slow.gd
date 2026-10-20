extends "res://tests/test_sword_hit_impact.gd"

var presentation: ChargePresentation
var ricochet: PlayerRicochet

func advance_slow(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var real_step := minf(remaining, 0.005)
		var step := real_step * Engine.time_scale
		ricochet.advance(step, Vector3.ZERO, false)
		player.action_animator.render(step)
		presentation.advance(step, real_step)
		remaining -= real_step

func start_flight() -> void:
	ricochet.cancel(true)
	player.position = Vector3(0, 0.02, 0)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await settle(8)
	player.set_physics_process(false)
	check(ricochet.begin_charge(Vector3.RIGHT) and ricochet.release_charge(), "真实人物从地面发射")
	presentation.set_process(false)

func hit_wall() -> void:
	await start_flight()
	for frame in 120:
		ricochet.advance(1.0 / 240.0, Vector3.ZERO, false)
		if ricochet.bounce_count > 0: break
	presentation.set_process(false)
	check(ricochet.bounce_count == 1, "真实胶囊命中实体墙并完成一次反射")

func run() -> void:
	var defaults := ChargePresentation.new()
	check("bounce_slow_enabled" in defaults, "建筑蹬墙需要独立的短慢动作配置")
	if not "bounce_slow_enabled" in defaults:
		defaults.free()
		quit(1)
		return
	check(not defaults.get("bounce_slow_enabled"), "共享默认关闭，City 不自动获得慢动作")
	defaults.free()
	var state: SceneState = load("res://scenes/world/world.tscn").get_state()
	var enabled := false
	for index in state.get_node_count():
		if state.get_node_name(index) != &"ChargePresentation": continue
		for property in state.get_node_property_count(index):
			if state.get_node_property_name(index, property) == &"bounce_slow_enabled": enabled = state.get_node_property_value(index, property)
	check(enabled, "World 明确开启建筑蹬墙慢动作")
	await setup()
	player.set_process(false)
	var collision := player.get_node("Collision") as CollisionShape3D
	collision.shape = CapsuleShape3D.new()
	collision.shape.radius = 0.24
	collision.shape.height = 1.0
	collision.position.y = 0.5
	player.ricochet_rules.minimum_launch_speed = 8.0
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.ricochet_rules.flight_deceleration = 0.1
	player.ricochet_rules.crowd_deflection_enabled = false
	ricochet = player.body_ricochet
	var previous := player.movement_camera
	camera = FollowCamera.new()
	camera.target = player
	world.add_child(camera)
	player.movement_camera = camera
	previous.free()
	camera.set_process(false)
	var effects := Node.new()
	effects.name = "MapEffects"
	world.add_child(effects)
	effects.owner = world
	presentation = ChargePresentation.new()
	presentation.name = "ChargePresentation"
	presentation.player = player
	presentation.set("bounce_slow_enabled", true)
	effects.add_child(presentation)
	presentation.owner = world
	await settle(3)
	presentation.set_process(false)
	impact = load("res://scripts/world/hit_impact_presentation.gd").new()
	impact.session = session
	world.add_child(impact)
	impact.set_process(false)
	var parameters: Array[Dictionary] = load("res://addons/parameter_hub/catalog.gd").new().collect(world)
	for property in ["bounce_slow_enabled", "bounce_slow_scale", "bounce_slow_enter_seconds", "bounce_slow_hold_seconds", "bounce_slow_exit_seconds", "bounce_slow_interval"]:
		check(parameters.any(func(item): return item.property == property and item.common and item.category == "视觉" and item.label != property), "参数总览提供中文蹬墙慢动作入口：" + property)
	var obstacle := Node3D.new()
	obstacle.add_to_group(&"ricochet_obstacles")
	world.add_child(obstacle)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.1, 2, 2)
	wall.add_child(shape)
	obstacle.add_child(wall)
	wall.position = Vector3(2, 1, 0)
	await settle(2)
	await hit_wall()
	check(player.action_animator._attack == &"bounce" and presentation.get("bounce_slow_active"), "建筑父级标记同时触发蹬墙动画与短慢动作")
	advance_slow(0.02)
	check(is_equal_approx(Engine.time_scale, 0.5) and camera.charge_unscaled_time and not player.hit_stop_active, "迅速进入半速，相机保持响应且人物不定格")
	var speed := ricochet.flight_speed
	var before := player.position
	var age := player.action_animator._attack_age
	advance_slow(0.05)
	check(player.position.distance_to(before) > 0.1 and player.action_animator._attack_age > age, "半速期间真实离墙位移和蹬墙动画连续推进")
	check(is_equal_approx(ricochet.flight_speed, ricochet._settings.speed_after_coast(speed, 0.025)), "慢动作不改写动能，仍按真实战斗时间沿原规则衰减")
	var envelope_age: float = presentation.get("_bounce_age")
	player.action_animator.request_bounce(Vector3.LEFT)
	check(is_equal_approx(presentation.get("_bounce_age"), envelope_age), "连续接触不重启或延长当前慢动作")
	var victim := hit_target(&"flight_sword", false, 1000.0)
	check(victim.health <= 0.0 and not player.hit_stop_active and not camera.hit_stop_active and Engine.time_scale >= 0.5, "蹬墙期间击杀正常结算，以慢动作代替额外命中定格")
	advance_slow(0.10)
	check(Engine.time_scale > 0.5 and Engine.time_scale < 1.0, "离墙后平滑回升，恢复过程不突跳")
	advance_slow(0.14)
	check(is_equal_approx(Engine.time_scale, 1.0) and not presentation.get("bounce_slow_active") and not camera.charge_unscaled_time, "约三成秒内归还原速与相机时钟")
	player.action_animator.request_bounce(Vector3.LEFT)
	check(not presentation.get("bounce_slow_active"), "动作播完但真实间隔未到时不再次触发慢动作")
	advance_slow(0.12)
	player.action_animator.request_bounce(Vector3.LEFT)
	advance_slow(0.03)
	check(is_equal_approx(Engine.time_scale, 0.5), "间隔过去后同次飞行可再次强调新的蹬墙动作")
	impact.clear()
	await start_flight()
	# 物理碰撞同帧已有命中反馈时，蹬墙接管必须解除显式人物定格。
	hit_target()
	check(player.hit_stop_active, "交接前确实存在旧命中定格")
	player.action_animator.request_bounce(Vector3.LEFT)
	advance_slow(0.03)
	check(not player.hit_stop_active and not camera.hit_stop_active and is_equal_approx(Engine.time_scale, 0.5), "蹬墙接住旧命中反馈，不沿用近零时间基准")
	ricochet.crowd_deflected.emit(Vector3.ZERO, Vector3.LEFT, Vector3.FORWARD)
	presentation.advance(0.0, 0.0)
	check(Engine.time_scale == 1.0 and not presentation.get("bounce_slow_active"), "转入怪群绕行释放蹬墙慢动作")
	impact.clear()
	for scenario in ["cancel", "freeze", "wave", "blocker", "disable", "external"]:
		await hit_wall()
		advance_slow(0.03)
		check(Engine.time_scale < 1.0, "清理前确实存在蹬墙慢动作：" + scenario)
		var blocker: Node
		match scenario:
			"cancel": ricochet.cancel(true)
			"freeze": session.set_combat_frozen(true)
			"wave": presentation.set_wave_finish_override(true)
			"blocker":
				blocker = Node.new()
				world.add_child(blocker)
				blocker.add_to_group(&"gameplay_input_blockers")
			"disable": presentation.set("bounce_slow_enabled", false)
			"external": Engine.time_scale = 0.7
		presentation.advance(0.0, 0.0)
		check(is_equal_approx(Engine.time_scale, 0.7 if scenario == "external" else 1.0), "接管归还原速，外部比例不被覆盖：" + scenario)
		if scenario == "external":
			advance_slow(0.4)
			check(is_equal_approx(Engine.time_scale, 0.7), "同段蹬墙不会重新夺回外部时间所有权")
		if blocker: blocker.free()
		session.set_combat_frozen(false)
		presentation.set_wave_finish_override(false)
		presentation.set("bounce_slow_enabled", true)
		ricochet.cancel(true)
		Engine.time_scale = 1.0
	Engine.time_scale = 0.8
	await hit_wall()
	advance_slow(0.03)
	check(is_equal_approx(Engine.time_scale, 0.4), "外部已有比例作为基准，不覆盖外部世界速度")
	advance_slow(0.30)
	check(is_equal_approx(Engine.time_scale, 0.8), "蹬墙结束准确归还进入前的外部基准")
	ricochet.cancel(true)
	Engine.time_scale = 1.0
	presentation.enabled = true
	presentation.full_slow_enabled = true
	presentation.full_slow_seconds = 0.2
	await start_flight()
	presentation._slow_remaining = 0.2
	presentation._advance_time(0.0)
	check(is_equal_approx(Engine.time_scale, presentation.full_slow_scale), "重叠用例先由满蓄慢动作持有时间")
	player.action_animator.request_bounce(Vector3.LEFT)
	advance_slow(0.03)
	check(is_equal_approx(Engine.time_scale, 0.5), "蹬墙与满蓄取较慢者，两个自身倍率不叠乘")
	presentation.enabled = false
	presentation.full_slow_enabled = false
	ricochet.cancel(true)
	obstacle.remove_from_group(&"ricochet_obstacles")
	await hit_wall()
	advance_slow(0.03)
	check(Engine.time_scale == 1.0 and not presentation.get("bounce_slow_active"), "空气墙等未标记物体只反弹，不触发蹬墙慢动作")
	ricochet.impact_recorded.emit(RicochetImpact.new(Vector3.ZERO, Vector3.LEFT, Vector3.RIGHT * 8, Vector3.LEFT * 7, 999, ricochet.flight_serial, 0.0))
	ricochet.crowd_deflected.emit(Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD)
	presentation.advance(0.03, 0.03)
	check(Engine.time_scale == 1.0, "镜面通用快照与怪群接触不会绕过建筑入口触发慢动作")
	obstacle.add_to_group(&"ricochet_obstacles")
	await hit_wall()
	advance_slow(0.03)
	presentation.free()
	check(Engine.time_scale == 1.0 and not camera.charge_unscaled_time, "组件退出不残留慢动作或相机时间标志")
	world.queue_free()
	await settle(3)
	print("Wall bounce slow: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
