extends SceneTree

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

func definition(path: String) -> GrowthBuffDefinition:
	return load("res://data/growth/%s.tres" % path)

func model_checks() -> void:
	var mods := RunCombatModifiers.new()
	var damage := definition("damage")
	check(damage.max_level == 0, "基础伤害持续可选")
	for index in 4: check(mods.apply_buff(damage), "前四级可授予")
	near(mods.damage_multiplier(), 1.8, "前四级沿用基础叠加")
	var preview := mods.preview_after(damage)
	near(preview.damage_multiplier(), 2.1, "第五级突破获得更高本次收益")
	near(mods.damage_multiplier(), 1.8, "突破预览不授予或修改状态")
	check(mods.apply_buff(damage), "领取第五级突破")
	for level in range(6, 101):
		var before := mods.damage_multiplier()
		check(mods.can_apply(damage) and mods.apply_buff(damage) and mods.damage_multiplier() > before, "持续成长到 %d 级仍有收益" % level)
	check(mods.level_for(damage.id) == 100, "单属性达到一百级")
	var first := damage.available_gain(0.0, 0)
	var late := damage.available_gain(0.0, 10)
	check(late > 0.0 and late < first, "后期温和递减仍保留收益")
	var flat := damage.duplicate()
	flat.diminishing_after = 0
	flat.breakthrough_every = 0
	near(flat.available_gain(0.0, 90), 0.2, "Godot 可关闭递减与突破")
	var finite := flat.duplicate()
	finite.id = &"finite"
	finite.max_level = 2
	mods.reset()
	check(mods.apply_buff(finite) and mods.apply_buff(finite) and not mods.can_apply(finite), "显式有限等级仍受支持")
	var attack := definition("cooldown")
	mods.reset()
	for index in 100: check(mods.apply_buff(attack), "效率型攻速可持续升级")
	check(mods.interval_multiplier() > 0.0 and is_finite(mods.interval_multiplier()), "高攻速不会将间隔减到零或负数")
	var base: PackedScene = load("res://scenes/combat/wave_prototype.tscn")
	var wave := base.instantiate() as WavePrototype
	var definitions: Array[GrowthBuffDefinition] = []
	for legacy in ["heavy_blade", "short_journey", "corner_chain", "meteor_stride", "gathering_ring", "heavy_push", "quick_draw", "roaming_light"]:
		definitions.append(definition("specializations/" + legacy))
	check(wave.get_node("RunBuffs").definitions.size() == 6, "正式池仅保留六种基础成长")
	for item in definitions:
		if item.required_levels.is_empty(): continue
		mods.reset()
		check(not mods.can_apply(item), "专精 %s 不会提前出现" % item.id)
		for id in item.required_levels: mods.levels[id] = item.required_levels[id]
		check(mods.can_apply(item), "前置达标解锁 %s" % item.id)
		for rank in item.max_level: check(mods.apply_buff(item), "专精 %s 的等级 %d 可授予" % [item.id, rank + 1])
		check(not mods.can_apply(item), "专精 %s 自身满级后退出" % item.id)
		check(item.extra_effects.size() == 2 and item.extra_effects[1].bonus_per_level < 0.0, "专精 %s 明确有两项收益和一项代价" % item.id)
		var previous := mods.levels.duplicate()
		mods.preview_after(item)
		check(mods.levels == previous, "预览不改变专精等级")
	wave.free()
	mods.reset()
	var bounce := definition("ricochet/bounce_count")
	for rank in 20: check(mods.apply_buff(bounce), "高等级续弹效率继续降低碰撞耗速")
	check(mods.ricochet_value(A.RICOCHET_BOUNCES, 0.5) > 0.0 and mods.ricochet_value(A.RICOCHET_BOUNCES, 0.5) < 0.1, "续弹突破和递减仍提供正值耗速收益")
	mods.reset()
	var retention := definition("ricochet/bounce_retention")
	for rank in 20: mods.apply_buff(retention)
	near(mods.ricochet_value(A.RICOCHET_RETENTION, 0.9), 1.0, "保速保持物理边界")
	check(mods.damage_multiplier() > 1.0 and mods.can_apply(retention), "满保速仍可继续强化续势伤害")
	mods.reset()
	check(mods.levels.is_empty() and mods.damage_multiplier() == 1.0 and mods.interval_multiplier() == 1.0, "所有属性与专精统一重置")

func integration_checks() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	var wave: WavePrototype = world.get_node("WavePrototype")
	wave.population_rules = wave.population_rules.duplicate(true)
	wave.population_rules.simulation_mode = false
	var growth: RunGrowth = wave.get_node("RunGrowth")
	growth.enabled = true
	growth.cards_per_draw = 100
	growth.get_node("GrowthChoiceUI").open_duration = 0.0
	wave.get_node("RunSkills").initial_cards_per_draw = 100
	wave.get_node("RunSkills/InitialSkillChoice").open_duration = 0.0
	root.add_child(world)
	current_scene = world
	for frame in 12: await physics_frame
	var player := wave.player
	player.set_physics_process(false)
	player.sword.set_physics_process(false)
	wave.set_physics_process(false)
	growth.set_physics_process(false)
	player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	var buffs: RunBuffs = wave.get_node("RunBuffs")
	var skills: RunSkills = wave.get_node("RunSkills")
	var mods := wave.combat_modifiers
	check(wave.start_run(), "开始正式挑战")
	check(skills.initial_choice.select_option(&"initial:light_pierce"), "沿用初始技能选择")
	skills.initial_choice.confirm_selection()
	var cards := buffs.candidates()
	check(cards.all(func(option): return not String(option.id).begins_with("S")), "未投资前池子没有专精卡")
	var move := definition("move_speed").duplicate()
	move.extra_effects = []
	var pickup := definition("pickup_radius")
	mods.apply_buff(move)
	mods.apply_buff(pickup)
	near(player.get_movement_speed(), player.speed * 1.12, "实际行走读取局内移动属性")
	near(growth.get_attraction_radius(), growth.attraction_radius * 1.2, "实际经验吸取读取局内范围")
	player.global_position = Vector3(-20.0, 0.03, 44.8)
	var camera := player.movement_camera
	player.movement_camera = null
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	var origin := player.global_position
	player._physics_process(1.0 / 60.0)
	near(player.global_position.x - origin.x, player.get_movement_speed() / 60.0, "真实行走位移使用成长后的速度")
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	player.movement_camera = camera
	growth.drop_experience(player.global_position + Vector3.RIGHT * 2.2, 1)
	var drop := growth._drops[-1]
	growth._physics_process(0.01)
	check(drop.attracting, "实际宝石能在原吸取范围之外开始吸取")
	# 以下显式接入旧资源，只验证兼容原型；正式场景不登记旧专精。
	player.ricochet_rules = player.ricochet_rules.duplicate()
	player.ricochet_rules.enemy_push_enabled = true
	buffs.definitions.append(definition("specializations/meteor_stride"))
	var base_speed := player.ricochet_rules.maximum_launch_speed
	var base_force := player.ricochet_rules.push_initial_speed
	for rank in 4: mods.apply_buff(definition("ricochet/launch_speed"))
	growth._grant_experience(10)
	check(growth.choice_ui.is_open and wave.combat_frozen, "真实升级冻结战斗")
	check(growth.choice_options.any(func(option): return option.id == &"S04" and option.description.contains("代价")), "达标后专精进入真实池并显示代价")
	var index := -1
	for cursor in buffs.definitions.size():
		if buffs.definitions[cursor].id == &"S04": index = cursor
	var original := buffs.definitions[index]
	check(buffs._offered[&"S04"].icon == original.icon, "配置快照共用图标资源")
	# 修改嵌套效果，确认展示时的深快照隔离编辑器调参。
	buffs.definitions[index] = original.duplicate(true)
	buffs.definitions[index].extra_effects[0].bonus_per_level = 0.9
	buffs.definitions[index].extra_effects[1].bonus_per_level = -0.5
	check(growth.choice_ui.select_option(&"S04"), "选择实际专精卡")
	growth.choice_ui.confirm_selection()
	near(player.body_ricochet.get_stats().maximum_launch_speed, base_speed * 1.65, "专精的速度收益只授予一次")
	near(player.body_ricochet.get_stats().push_initial_speed, base_force * 0.9, "专精的真实推力代价")
	near(player.body_ricochet.get_stats().full_charge_seconds, player.ricochet_rules.full_charge_seconds / 1.15, "嵌套蓄力收益保持展示快照")
	buffs.definitions[index] = original
	check(not wave.combat_frozen, "原子应用收益和代价后解冻")
	var heavy := definition("specializations/heavy_blade")
	mods.levels[&"P01"] = 4
	player.sword.rules = player.sword.rules.duplicate()
	player.sword.rules.normal_interval = player.sword.rules.duration()
	player.sword.rules.flight_interval = player.sword.rules.duration()
	# 仅保留剑术，动作已成瓶颈时攻速代价不能被吞掉。
	for node in wave._combat_nodes:
		if node != player.sword and "enabled" in node: node.enabled = false
	var speed := definition("cooldown")
	for rank in 100: mods.apply_buff(speed)
	check(not buffs._has_effect(speed), "动作封底后不提供无效攻速")
	check(not buffs._has_effect(heavy), "动作封底吞掉攻速代价时不提供免费重锋")
	var short := definition("specializations/short_journey")
	mods.levels[&"P03"] = 4
	mods.levels[&"R02"] = 2
	check(buffs._has_effect(short), "有真实代价的短旅专精仍有效")
	var keep := mods.levels.duplicate()
	wave._set_phase(WavePrototype.Phase.REST)
	check(mods.levels == keep, "波间保留长成长与专精")
	wave.retreat()
	near(player.get_movement_speed(), player.speed, "结束恢复走路速度")
	near(growth.get_attraction_radius(), growth.attraction_radius, "结束恢复经验吸取范围")
	check(mods.levels.is_empty(), "结束清空所有前置与专精")
	world.queue_free()
	for frame in 5: await physics_frame

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	model_checks()
	await integration_checks()
	await create_timer(0.25).timeout
	print("Growth specializations: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
