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
	# 当前正式地图可独立关闭成长；测试显式开启，不改写用户场景配置。
	growth.enabled = true
	growth.cards_per_draw = 100
	growth.draw_seed = 715
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
	check(not buffs.candidates().any(func(option): return option.id in [&"R08", &"R09", &"R10", &"R11"]), "正式关闭拨怪后不再提供无效拨怪成长")
	# 以下继续验证旧原型主动开启拨怪时的独立成长兼容。
	player.ricochet_rules = player.ricochet_rules.duplicate()
	player.ricochet_rules.enemy_push_enabled = true
	player.global_position = session._path.ground_position(session.global_position) + Vector3.UP * 0.03
	var base_speed := player.ricochet_rules.maximum_launch_speed
	var base_push := player.ricochet_rules.push_radius
	var save_before := session.loadout.state.export_state().duplicate(true)
	check(buffs.definitions.size() == 24, "十六种基础属性与八种专精均注册")
	check(session.start_run(), "实际开局选择")
	check(skills.initial_choice._options.all(func(option): return not String(option.id).begins_with("R")), "初始仍只选择技能")
	check(skills.initial_choice.select_option(&"initial:light_pierce"), "沿用实际 A02 开局链路")
	skills.initial_choice.confirm_selection()
	check(growth.active, "成长在开始战斗后激活")
	growth._grant_experience(10)
	check(growth.choice_ui.is_open and session.combat_frozen and not paused, "真实升级打开且只冻结战斗")
	check(growth.choice_options.any(func(option): return option.id == &"R01"), "速度卡进入同一个升级池")
	check(growth.choice_options.any(func(option): return option.id == &"P01"), "原有共用伤害继续提供")
	check(growth.choice_options.any(func(option): return option.id == &"R07"), "周转卡在冷却无收益时仍提供明确蓄力收益")
	var shown: GrowthChoiceOption
	for option in growth.choice_options:
		if option.id == &"R01": shown = option
	check(shown != null and shown.description.contains("%.2f → %.2f米/秒" % [base_speed, base_speed * 1.15]), "卡面读取实际资源速度而非脚本默认值")
	var speed_index := -1
	for index in buffs.definitions.size():
		if buffs.definitions[index].id == &"R01": speed_index = index
	var original := buffs.definitions[speed_index]
	buffs.definitions[speed_index] = original.duplicate()
	buffs.definitions[speed_index].bonus_per_level = 0.5
	choose(growth, &"R01")
	near(body.get_stats().maximum_launch_speed, base_speed * 1.15, "已经展示的奖励不受随后编辑配置影响")
	buffs.definitions[speed_index] = original
	check(not session.combat_frozen, "领取后恢复战斗")
	growth._grant_experience(15)
	choose(growth, &"R08")
	near(body.get_stats().push_radius, base_push * 1.15, "真实拨怪范围增长")
	near(player.sword.get_stats().range, player.sword.rules.normal_range, "拨怪范围不扩大剑术范围")
	growth._grant_experience(20)
	choose(growth, &"P03")
	near(player.sword.get_stats().range, player.sword.rules.normal_range * 1.15, "原有范围卡仍同步影响剑术")
	near(body.get_stats().push_radius, base_push * 1.15, "剑术范围不重复扩大拨怪")
	var retained := session.combat_modifiers.levels.duplicate()
	session._set_phase(WavePrototype.Phase.REST)
	check(session.combat_modifiers.levels == retained, "波间休整保留成长")
	check(session.loadout.state.export_state() == save_before, "局内弹射属性不写入永久存档")
	player.ricochet_rules = player.ricochet_rules.duplicate()
	player.ricochet_rules.bounce_speed_retention = 1.0
	check(buffs.candidates().any(func(option): return option.id == &"R04"), "满保速后的续势卡继续提供真实伤害成长")
	player.ricochet_rules.wall_bounce_limit = 12
	check(buffs.candidates().any(func(option): return option.id == &"R03"), "旧十二次预算不再阻断反弹成长")
	player.ricochet_rules.cooldown_seconds = 2.0
	check(buffs.candidates().any(func(option): return option.id == &"R07"), "冷却成为瓶颈时提供周转卡")
	player.ricochet_rules.push_initial_speed = 0.0
	check(not buffs.candidates().any(func(option): return option.id in [&"R08", &"R09", &"R10", &"R11"]), "推挤关闭时不提供无效推挤成长")
	player.ricochet_rules.enabled = false
	check(not buffs.candidates().any(func(option): return String(option.id).begins_with("R")), "弹射关闭时不提供弹射卡")
	player.ricochet_rules.enabled = true
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(world)
	check(entries.any(func(item): return item.object == original and item.property == "bonus_per_level" and item.common), "Godot 参数总览索引新增配置资源")
	session.retreat()
	check(session.combat_modifiers.levels.is_empty(), "结束清空全部局内属性")
	session.retry()
	check(skills.initial_choice.is_open and growth.rerolls_left == 3, "重试恢复初始选择与三次重抽")
	near(body.get_stats().maximum_launch_speed, base_speed, "重试恢复基础速度")
	check(original.bonus_per_level == 0.15, "共享增益资源不被运行时改写")
	world.queue_free()
	await settle()

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	await motion_checks()
	await integration_checks()
	await create_timer(0.25).timeout
	print("Ricochet growth: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
