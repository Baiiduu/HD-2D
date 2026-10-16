extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
const A := GrowthBuffDefinition.Attribute
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(65.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func near(value: float, expected: float, message: String) -> void:
	check(is_equal_approx(value, expected), message)

func settle(count := 5) -> void:
	for frame in count: await physics_frame

func buff(attribute: A, gain := 0.2) -> GrowthBuffDefinition:
	var result := GrowthBuffDefinition.new()
	result.id = StringName("test:%d" % attribute)
	result.attribute = attribute
	result.bonus_per_level = gain
	return result

func model_checks() -> void:
	var mods := RunCombatModifiers.new()
	var speed: GrowthBuffDefinition = load("res://data/growth/ricochet/launch_speed.tres")
	var momentum: GrowthBuffDefinition = load("res://data/growth/ricochet/flight_duration.tres")
	var rhythm: GrowthBuffDefinition = load("res://data/growth/ricochet/charge_efficiency.tres")
	var utility: GrowthBuffDefinition = load("res://data/growth/move_speed.tres")
	check(momentum.is_ricochet() and momentum.attribute == A.MOMENTUM_EFFICIENCY, "合并动能拥有独立属性并归入弹射方向")
	mods.apply_buff(speed)
	near(mods.ricochet_value(A.RICOCHET_SPEED, 12.0), 13.2, "速度普通一级提高短蓄与满蓄共用倍率")
	mods.apply_buff(momentum)
	near(mods.ricochet_value(A.RICOCHET_DURATION, 4.0), 3.2, "动能一级降低飞行衰减")
	near(mods.ricochet_value(A.RICOCHET_BOUNCES, 0.25), 0.2, "动能一级降低固定碰撞耗速")
	var retained := mods.ricochet_value(A.RICOCHET_RETENTION, 0.92)
	near(retained, 0.936, "动能一级按比例减少保速损失")
	near(12.0 * (1.0 - retained) + mods.ricochet_value(A.RICOCHET_BOUNCES, 0.25), (12.0 * 0.08 + 0.25) / 1.25, "同一动能效率统一降低全部接触损失")
	mods.apply_buff(rhythm)
	near(mods.ricochet_value(A.CHARGE_EFFICIENCY, 0.5), 0.4, "蓄力节奏提高满蓄效率")
	near(mods.ricochet_value(A.RICOCHET_COOLDOWN_EFFICIENCY, 0.2), 0.16, "蓄力节奏同步提高发射冷却效率")
	mods.apply_buff(utility)
	near(mods.multiplier(A.MOVE_SPEED), 1.12, "游走收集兼容资源仍保留移动收益")
	near(mods.multiplier(A.PICKUP_RADIUS), 1.2, "游走收集兼容资源仍保留吸取收益")
	mods.reset()
	for rank in range(1, 101):
		var before := mods.ricochet_value(A.RICOCHET_DURATION, 4.0)
		check(mods.apply_buff(momentum), "动能第 %d 级持续可授予" % rank)
		var after := mods.ricochet_value(A.RICOCHET_DURATION, 4.0)
		check(is_finite(after) and after > 0.0 and after < before, "高等级仍有正值衰减与实际收益")
		check(mods.ricochet_value(A.RICOCHET_BOUNCES, 0.25) > 0.0 and mods.ricochet_value(A.RICOCHET_RETENTION, 0.92) < 1.0, "有限动能等级不制造零碰撞损失")
		if rank == 3: near((12.0 - 2.0) / after, 4.375, "三级动能将 2.5 秒参考续航提高至约 4.38 秒")
	mods.reset()
	near(mods.ricochet_value(A.RICOCHET_DURATION, 4.0), 4.0, "重置恢复自然衰减")
	near(mods.ricochet_value(A.RICOCHET_RETENTION, 0.92), 0.92, "重置恢复碰撞保速")

func motion_checks() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var terrain := Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-12, -12), Vector2i(24, 24))
	world.add_child(terrain)
	var session := SESSION.new()
	session.name = "WavePrototype"
	session.terrain = terrain
	session.phase = WavePrototype.Phase.BATTLE
	world.add_child(session)
	var player := Player.new()
	player.animations = load("res://assets/meowa/player/animations.tres")
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.minimum_launch_speed = 3.0
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.action_visuals = PlayerActionVisuals.new()
	player.action_visuals.show_aim_guide = false
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.06592
	collision.shape = capsule
	collision.position.y = capsule.height * 0.5
	player.add_child(collision)
	session.player = player
	world.add_child(player)
	player.position.y = 0.03
	await settle(10)
	player.set_physics_process(false)
	var body := player.body_ricochet
	var mods := session.combat_modifiers
	for attribute in GrowthBuffDefinition.RICOCHET_PROPERTIES:
		mods.reset()
		var property: StringName = GrowthBuffDefinition.RICOCHET_PROPERTIES[attribute]
		var base: float = player.ricochet_rules.get(property)
		var gain := 1.0 if attribute == A.RICOCHET_BOUNCES else 0.05 if attribute == A.RICOCHET_RETENTION else 0.2
		var definition := buff(attribute, gain)
		var preview := mods.preview_after(definition)
		near(body.get_stats()[property], base, "预览不授予奖励：%s" % property)
		check(mods.apply_buff(definition), "所有共用弹射属性可授予：%s" % property)
		var expected := base * (1.0 + gain)
		if attribute == A.RICOCHET_RETENTION: expected = base + gain
		elif attribute in [A.RICOCHET_DURATION, A.RICOCHET_BOUNCES, A.CHARGE_EFFICIENCY, A.RECOVERY_EFFICIENCY, A.RICOCHET_COOLDOWN_EFFICIENCY]: expected = base / (1.0 + gain)
		near(body.get_stats()[property], expected, "实际最终值：%s" % property)
		near(body.get_stats(preview)[property], expected, "卡片预览与实际相同：%s" % property)
		near(player.ricochet_rules.get(property), base, "不改写基础资源：%s" % property)
		check(body.begin_charge(Vector3.RIGHT), "开始蓄力取属性快照")
		near(body._settings.get(property), expected, "真实运动读取同一属性：%s" % property)
		body.cancel(true)
	mods.reset()
	check(mods.apply_buff(buff(A.RICOCHET_SPEED)), "提高发射速度")
	near(body.get_stats().minimum_launch_speed, 3.6, "起步速度同步提高")
	check(mods.apply_buff(buff(A.CHARGE_EFFICIENCY)), "提高蓄力效率")
	check(mods.apply_buff(buff(A.RICOCHET_DURATION)), "降低飞行耗速")
	check(body.begin_charge(Vector3.RIGHT), "带增益开始蓄力")
	body.advance(0.8 / 1.2, Vector3.ZERO, false)
	near(body.charge_fraction, 1.0, "缩短后的实际满蓄力时间")
	check(body.release_charge(), "带增益发射")
	near(body.flight_speed, 9.6, "真实发射速度")
	near(body._flight_remaining, 3.648, "按速度和减速度估算无碰撞余时")
	var start := player.position
	body.advance(0.1, Vector3.ZERO, false)
	near(player.position.x - start.x, 0.94958333333333, "真实胶囊位移同时计算增强速度和衰减")
	mods.reset()
	near(body.flight_speed, 9.39166666666667, "重置成长不改变已经衰减后的当前速度")
	near(body._settings.flight_deceleration, 2.5 / 1.2, "进行中保留飞行耗速快照")
	body.cancel(true)
	check(body.begin_charge(Vector3.RIGHT), "从基础值蓄力")
	mods.apply_buff(buff(A.RICOCHET_SPEED))
	mods.apply_buff(buff(A.CHARGE_EFFICIENCY))
	body.advance(0.4, Vector3.ZERO, false)
	near(body.charge_fraction, 0.5, "蓄力中升级不跳进度")
	body.release_charge()
	near(body.flight_speed, 5.5, "蓄力中升级不改变本次发射")
	body.cancel(true)
	check(body.begin_charge(Vector3.RIGHT), "下一次采用新成长")
	near(body._settings.maximum_launch_speed, 9.6, "下一次蓄力采用新速度")
	body.cancel(true)
	mods.reset()
	var many := buff(A.RICOCHET_BOUNCES, 2.0)
	many.max_level = 20
	many.breakthrough_every = 0
	for index in 10: mods.apply_buff(many)
	near(body.get_stats().bounce_speed_cost, 0.5 / 21.0, "持续成长降低碰撞耗速而不增加次数预算")
	var retention := buff(A.RICOCHET_RETENTION, 0.5)
	mods.apply_buff(retention)
	near(body.get_stats().bounce_speed_retention, 1.0, "保速不超过百分之百")
	check(buff(A.RICOCHET_BOUNCES, 0.2).available_gain(0.0) > 0.0, "百分比续弹效率产生真实耗速收益")
	var invalid := buff(A.RICOCHET_SPEED, NAN)
	check(not mods.can_apply(invalid), "无效调参不进入成长")
	# 窄走廊中速度足够就反弹；旧的次数／时间字段不能截断实际运动。
	for x in [-1.0, 1.0]:
		var wall := StaticBody3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.2, 2.0, 6.0)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		wall.add_child(collider)
		world.add_child(wall)
		wall.position = Vector3(x, 1.0, 0)
	player.global_position = Vector3(0, 0.03, 0)
	player.ricochet_rules.minimum_launch_speed = 16.0
	player.ricochet_rules.maximum_launch_speed = 16.0
	player.ricochet_rules.flight_seconds = 0.01
	player.ricochet_rules.wall_bounce_limit = 0
	player.set_physics_process(true)
	await settle(10)
	player.set_physics_process(false)
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "高速与低碰撞损耗可开始真实飞行")
	for frame in 240:
		if body.flying: body.advance(0.05, Vector3.ZERO, false)
	check(body.bounce_count > 12 and not body.flying, "真实反弹超过十二次，最终因速度耗尽结束")
	world.queue_free()
	await settle()

func choose(growth: RunGrowth, id: StringName) -> void:
	check(growth.choice_ui.select_option(id), "选择实际可见卡：%s" % id)
	growth.choice_ui.confirm_selection()

func integration_checks() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	var session: WavePrototype = world.get_node("WavePrototype")
	session.population_rules = session.population_rules.duplicate(true)
	session.population_rules.simulation_mode = false
	var growth: RunGrowth = session.get_node("RunGrowth")
	growth.enabled = true
	growth.cards_per_draw = 100
	growth.get_node("GrowthChoiceUI").open_duration = 0.0
	session.get_node("RunSkills").initial_cards_per_draw = 100
	session.get_node("RunSkills/InitialSkillChoice").open_duration = 0.0
	root.add_child(world)
	current_scene = world
	await settle(12)
	var player := session.player
	player.set_physics_process(false)
	player.sword.set_physics_process(false)
	session.set_physics_process(false)
	growth.set_physics_process(false)
	var body := player.body_ricochet
	var buffs: RunBuffs = session.get_node("RunBuffs")
	var skills: RunSkills = session.get_node("RunSkills")
	var mods := session.combat_modifiers
	var base := body.get_stats()
	var save_before := session.loadout.state.export_state().duplicate(true)
	check(buffs.definitions.size() == 6 and buffs.definitions.all(func(item): return item.required_levels.is_empty() and item.max_level == 0), "正式仅登记六种可持续成长，无专精前置")
	check(buffs.candidates().filter(func(option): return option.ricochet_growth).size() == 3, "三种弹射成长得到明确抽牌分组")
	check(session.start_run(), "实际开局仍先选择技能")
	check(skills.initial_choice._options.all(func(option): return not option.ricochet_growth), "开局不混入弹射或共有成长")
	check(skills.initial_choice.select_option(&"initial:light_pierce"), "初始技能学习沿用现有链路")
	skills.initial_choice.confirm_selection()
	growth._grant_experience(10)
	check(growth.choice_ui.is_open and session.combat_frozen and not paused, "升级只冻结战斗")
	var speed_index := -1
	for index in buffs.definitions.size():
		if buffs.definitions[index].id == &"R01": speed_index = index
	var original := buffs.definitions[speed_index]
	buffs.definitions[speed_index] = original.duplicate()
	buffs.definitions[speed_index].bonus_per_level = 0.5
	choose(growth, &"R01")
	near(body.get_stats().maximum_launch_speed, base.maximum_launch_speed * 1.1, "已展示的速度奖励保留配置快照")
	near(body.get_stats().minimum_launch_speed, base.minimum_launch_speed * 1.1, "短蓄初速同步成长")
	buffs.definitions[speed_index] = original
	growth._grant_experience(15)
	choose(growth, &"R02")
	near(body.get_stats().flight_deceleration, base.flight_deceleration / 1.25, "动能降低自然衰减")
	near(body.get_stats().bounce_speed_cost, base.bounce_speed_cost / 1.25, "同一张卡降低固定碰撞扣速")
	near(1.0 - body.get_stats().bounce_speed_retention, (1.0 - base.bounce_speed_retention) / 1.25, "同一张卡降低比例碰撞损失")
	growth._grant_experience(20)
	choose(growth, &"R05")
	near(body.get_stats().full_charge_seconds, base.full_charge_seconds / 1.25, "蓄力节奏缩短满蓄时间")
	near(body.get_stats().cooldown_seconds, base.cooldown_seconds / 1.25, "蓄力节奏同时改善再次发射等待")
	near(player.get_movement_speed(), player.speed, "正式成长不额外提高行走速度")
	near(growth.get_attraction_radius(), growth.attraction_radius, "正式成长沿用原有经验吸取范围")
	check(buffs.candidates().all(func(option): return option.id in [&"P01", &"P02", &"P03", &"R01", &"R02", &"R05"]), "游走收集、旧重复增益和专精不在正式池")
	check(body.begin_charge(Vector3.RIGHT), "合并成长固定在开始蓄力时")
	var locked := body._settings.flight_deceleration
	mods.apply_buff(load("res://data/growth/ricochet/flight_duration.tres"))
	near(body._settings.flight_deceleration, locked, "后续成长不改写进行中的弹射快照")
	body.cancel(true)
	player.ricochet_rules = player.ricochet_rules.duplicate()
	player.ricochet_rules.enabled = false
	check(not buffs.candidates().any(func(option): return option.ricochet_growth), "关闭弹射时三条成长都正确退出候选")
	player.ricochet_rules.enabled = true
	var retained := mods.levels.duplicate()
	session._set_phase(WavePrototype.Phase.REST)
	check(mods.levels == retained and session.loadout.state.export_state() == save_before, "波间保留六类成长且不写永久存档")
	session.retreat()
	check(mods.levels.is_empty() and growth._draw_pool._preferred_ricochet.is_empty(), "结束清空属性与方向跟进")
	session.retry()
	check(skills.initial_choice.is_open and growth.rerolls_left == 3, "重试恢复初始技能与共享重抽预算")
	near(body.get_stats().maximum_launch_speed, base.maximum_launch_speed, "重试恢复基础速度")
	world.queue_free()
	await settle()

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	model_checks()
	await motion_checks()
	await integration_checks()
	await create_timer(0.25).timeout
	print("Ricochet growth: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
