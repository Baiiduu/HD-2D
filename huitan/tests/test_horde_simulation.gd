extends SceneTree

var checks := 0
var failures := 0
var world: Node3D
var wave: WavePrototype
var player: Player
var freeze_spawned := true
var sword_hits := 0
var storm_hits := 0

func _initialize() -> void:
	create_timer(110.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func confirm_initial() -> void:
	var choices: GrowthChoiceUI = wave.get_node("SkillDraft/InitialSkillChoice")
	if choices.is_open:
		choices.reveal_now()
		choices.select_option(&"initial:ricochet_storm")
		choices.confirm_selection()

func start() -> bool:
	player.global_position = wave.global_position + Vector3.UP * 0.03
	player.velocity = Vector3.ZERO
	if not wave.start_run(): return false
	confirm_initial()
	return wave.phase == WavePrototype.Phase.BATTLE

func damage_checks() -> void:
	var target := wave.enemies[0]
	player.global_position = wave.global_position + Vector3.UP * 0.03
	target.global_position = player.global_position + Vector3.RIGHT * 0.5
	target.spawn_delay = 0.0
	wave._spatial_index.update(target)
	var health := target.health
	var events: Array[CombatDamageEvent] = []
	target.damaged.connect(func(event): events.append(event))
	var numbers := wave.get_node("DamageNumbers") as DamageNumbers
	check(target.health_loss_disabled and player.sword.get_stats(false).damage > 0.0 and player.sword.get_stats(true).damage > 0.0, "模拟只锁定怪物生命，普攻与飞行剑术保留真实数值")
	for path in ["FanAutoAttack", "LightPierceAutoAttack", "PrismRicochetAutoAttack", "MirrorMarkAutoAttack", "RicochetStorm"]:
		var skill := wave.get_node(path)
		skill.apply_skill_level(1)
		skill.set_physics_process(false)
		check(skill.get_attack_stats(1).damage > 0.0, "模拟技能保留真实攻击数值：" + path)
	var damage_buff := load("res://data/growth/damage.tres") as GrowthBuffDefinition
	var preview := wave.combat_modifiers.preview_after(damage_buff)
	check(preview.damage_disabled and preview.damage_multiplier() > wave.combat_modifiers.damage_multiplier(), "成长预览保留锁血状态并正确提高攻击数值")
	var base_damage: float = player.sword.get_stats(false).damage
	check(wave.combat_modifiers.apply_buff(damage_buff) and player.sword.get_stats(false).damage > base_damage, "模拟仍实际应用正常伤害成长")
	player.sword.set_physics_process(false)
	player.sword.hit_landed.connect(func(_enemy, damage, _flying):
		sword_hits += 1
		check(damage == 0.0, "剑术命中保留零扣血语义"))
	check(player.sword.request_manual(Vector3.RIGHT), "模拟接受真实普攻")
	for frame in 20: player.sword._physics_process(1.0 / 60.0)
	check(sword_hits > 0 and target.health == health, "剑术仍结算命中且怪物生命不变")
	check(events.any(func(event): return event.source == &"basic_sword" and is_equal_approx(event.display_amount(), player.sword.get_stats(false).damage)), "普攻飘字匹配成长后的真实攻击数值")
	var storm := wave.get_node("RicochetStorm") as RicochetStorm
	storm.hit_landed.connect(func(_enemy, damage):
		storm_hits += 1
		check(damage == 0.0, "雷潮命中保留零扣血语义"))
	check(storm.discharge(player.global_position), "锁血模拟仍可实际引雷")
	storm._physics_process(1.0)
	check(storm_hits > 0 and target.health == health, "雷潮传播与命中特效继续运行，怪物生命不变")
	check(events.any(func(event): return event.source == &"ricochet_storm" and event.style == &"lightning" and is_equal_approx(event.display_amount(), storm.get_attack_stats(1).damage)), "奔雷飘字匹配技能真实数值并保持雷电样式")
	check(numbers._active.size() > 0 and numbers._active.all(func(number): return number.event.simulated and number._text != "0"), "正式场景共享显示层实际生成非零伤害数字")
	player.sword.cancel()
	var body := player.body_ricochet
	target.global_position = player.global_position + Vector3(1.6, 0.0, 0.35)
	wave._spatial_index.update(target)
	check(body.begin_charge(Vector3.RIGHT), "模拟模式仍可真实蓄力")
	body.advance(0.05, Vector3.ZERO, false)
	check(body.release_charge(), "模拟模式仍可发射人物")
	check(not body.push_after_sword_hit(target, player.global_position, Vector3.RIGHT), "模拟遵守正式关闭拨怪的规则")
	for frame in 24:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		player.sword._physics_process(1.0 / 60.0)
		storm._physics_process(1.0 / 60.0)
	check(events.any(func(event): return event.source == &"flight_sword" and event.display_amount() > 0.0), "真实本体弹射沿路线挥剑并显示伤害数字")
	check(target.stun_remaining == 0.0 and target.health == health and not target.dead, "模拟未重启旧拨怪眩晕，持续攻击不减少怪物生命")
	body.cancel(true)
	var player_health := player.current_health
	wave._hurt_clock = 0.0
	check(wave._can_damage_player(20.0, wave._generation), "免伤仍保留怪物正常命中资格与查询")
	check(target.damage_player.call(20.0) and player.current_health == player_health, "真实怪物命中接口不会扣人物生命")
	check(wave._hurt_clock > 0.0 and not target.damage_player.call(20.0), "免伤仍使用共享受击间隔")
	wave._hurt_clock = 0.0
	check(not wave._damage_player(NAN, wave._generation) and not wave._damage_player(20.0, wave._generation - 1), "无效伤害与旧波回调仍被拒绝")

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var source := load("res://data/waves/population/mass_horde_simulation.tres") as WavePopulationRules
	check(source != null and source.simulation_mode and source.simulation_enemy_count == 512 and source.validation_error().is_empty(), "可选巨量怪潮资源默认 512 且配置有效")
	var rules := source.duplicate(true) as WavePopulationRules
	var level_property: Dictionary = rules.simulation_skills[0].get_property_list().filter(func(property): return property.name == "skill_level")[0]
	check(level_property.hint_string == "0,%d,1" % rules.simulation_skills[0].skill_definition.levels.size(), "检查器等级范围随选中技能的真实上限更新")
	for count in [0, 4097]:
		rules.simulation_enemy_count = count
		check(not rules.validation_error().is_empty(), "非法模拟数量在开始前拒绝")
	rules.simulation_enemy_count = 4096
	check(rules.validation_error().is_empty(), "模拟数量上界可配置，不代表保证帧率或地图承载量")
	rules.simulation_enemy_count = 37
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WavePresentation").enabled = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await settle(16)
	wave = world.get_node("WavePrototype")
	# 数量与免死规则使用原刷新时序，剪影预告由独立逻辑测试覆盖。
	wave.spawn_shadow_settings = null
	player = world.get_node("Player")
	wave.set_physics_process(false)
	player.set_physics_process(false)
	wave.skill_draft.initial_cards_per_draw = 100
	check(wave.population_rules != null, "载入用户当前选取的数量规则，不改写其模拟设置")
	var ordinary := wave.population_rules.duplicate(true) as WavePopulationRules
	ordinary.simulation_mode = false
	var first_wave_total: int = wave.waves[0].entries.reduce(func(total, entry): return total + entry.count, 0)
	wave.population_rules = rules
	rules.simulation_skills[0].skill_level = mini(3, rules.simulation_skills[0].skill_definition.levels.size())
	rules.simulation_skills[1].skill_level = 0
	rules.simulation_skills[2].skill_level = 2
	rules.simulation_skills[3].skill_level = 3
	var fan_slot := SimulationSkillEntry.new()
	fan_slot.skill_definition = wave.get_node("FanAutoAttack").get_skill_definition()
	fan_slot.skill_level = 1
	rules.simulation_skills.append(fan_slot)
	wave.enemy_spawned.connect(func(enemy):
		if freeze_spawned: enemy.set_physics_process(false))
	check(start(), "选取 Population Rules 后直接进入模拟，不强制抽取初始技能")
	var skills := wave.get_node("RunSkillManager") as RunSkillManager
	check(not wave.skill_draft.initial_choice.is_open and skills.get_level(&"ricochet_storm") == 3 and skills.get_level(&"mirror_mark") == 2 and skills.get_level(&"prism_ricochet") == 0, "开局准确应用持有技能、不同等级和零级不携带")
	check(skills.get_slots().size() == 4 and wave.get_node("FanAutoAttack").enabled, "技能栏展示真实持有，显式选取原关闭技能也能运行")
	check(skills.get_level(rules.simulation_skills[0].skill_definition.id) == rules.simulation_skills[0].skill_level, "指定等级已应用到雷光贯穿的真实组件")
	check(not wave.is_endless() and wave.wave_count() == 1 and wave._run_waves.size() == 1, "模拟直接建立一波，不沿用开场模板与无尽递增")
	check(wave._pending == 37 and wave.get_active_enemy_limit() == 37 and wave._run_population.max_queued_per_wave == 37, "只改一个数量即同步配置总数、同场与登记预算")
	check(wave._spawn_queue.all(func(job): return job.batch.id == wave._spawn_queue[0].batch.id), "整场以一个真实集中怪潮登记，继续分帧创建")
	check(rules.first_active_limit == 24 and rules.max_active == 512 and rules.role_limits == source.role_limits, "仅调整本局副本，不改写源数量曲线和角色限制")
	check(wave._run_population.role_limits == PackedInt32Array([37, 37, 37, 37]), "模拟本局分类容量自动匹配目标")
	for frame in 100:
		wave._physics_process(0.04)
		if wave._pending == 0 or wave.phase != WavePrototype.Phase.BATTLE: break
		await settle(1)
	check(wave.enemies.size() == 37 and wave._pending == 0, "真实地形、安全位置与刷新预算下完整生成指定怪潮")
	var ids := {}
	for enemy in wave.enemies: ids[enemy.definition.enemy_id] = true
	check(ids.size() == 5 and not ids.has(&"mini_slime"), "模拟复用目录五种主怪，幼体不直接加入")
	check(wave.get_run_state().simulation and "37 / 37" in wave.wave_label(1), "状态与 HUD 显示真实当前数量和目标")
	rules.simulation_enemy_count = 11
	rules.simulation_mode = false
	rules.simulation_skills[3].skill_level = 1
	check(wave.get_active_enemy_limit() == 37 and wave.is_horde_simulation() and wave.combat_modifiers.damage_disabled and wave.combat_modifiers.damage_multiplier() > 0.0, "编辑原资源不改变正在运行的数量与锁血模拟")
	check(skills.get_level(&"ricochet_storm") == 3, "运行中修改技能等级保留本局快照")
	if not wave.enemies.is_empty(): damage_checks()
	wave.retreat()
	check(wave.enemies.is_empty() and wave._pending == 0 and not wave.combat_modifiers.damage_disabled and wave.combat_modifiers.damage_multiplier() == 1.0, "撤退完整清理怪潮并解除生命锁定与临时成长")
	check(not wave.get_node("FanAutoAttack").enabled and not skills.has_learned_skill(), "结束模拟恢复原技能组件开关并清空测试配置")
	rules.simulation_mode = true
	wave.retry()
	confirm_initial()
	check(wave.phase == WavePrototype.Phase.BATTLE and wave._pending == 11 and wave.get_active_enemy_limit() == 11, "T 重试读取新数量，即使低于普通开场容量也有效")
	check(skills.get_level(&"ricochet_storm") == 1, "重试读取新技能等级")
	wave.retreat()
	rules.simulation_skills.clear()
	wave.return_home()
	check(start() and not wave.skill_draft.initial_choice.is_open and not skills.has_learned_skill(), "空技能列表可直接开始，只保留基础剑术")
	wave.retreat()
	var invalid := source.duplicate(true) as WavePopulationRules
	invalid.simulation_skills[0].skill_level = 100
	check(not invalid.validation_error().is_empty(), "超出技能真实等级上限时明确拒绝")
	invalid = source.duplicate(true) as WavePopulationRules
	invalid.simulation_skills.append(invalid.simulation_skills[0].duplicate(true))
	check(not invalid.validation_error().is_empty(), "重复技能配置明确拒绝")
	invalid = source.duplicate(true) as WavePopulationRules
	invalid.simulation_skills[0].skill_definition = invalid.simulation_skills[0].skill_definition.duplicate(true)
	invalid.simulation_skills[0].skill_definition.id = &"missing_simulation_skill"
	wave.population_rules = invalid
	wave.return_home()
	check(not start() and wave.outcome == WavePrototype.Outcome.ERROR and wave._pending == 0, "未接入当前场景的技能在生成前拒绝")
	wave.population_rules = ordinary
	wave.return_home()
	check(start() and wave.is_endless() and wave._pending == first_wave_total and wave.get_active_enemy_limit() == 24, "切回普通规则恢复真实开场与容量")
	check(player.sword.get_stats(false).damage > 0.0, "普通模式恢复人物伤害")
	wave._hurt_clock = 0.0
	var health := player.current_health
	check(wave._damage_player(8.0, wave._generation) and player.current_health == health - 8.0, "普通模式恢复怪物伤害")
	wave.retreat()
	if "--large" in OS.get_cmdline_user_args():
		freeze_spawned = false
		wave.population_rules = source
		wave.return_home()
		check(start(), "默认 512 档实际开始")
		wave.set_physics_process(true)
		var deadline := Time.get_ticks_msec() + 45000
		while wave.phase == WavePrototype.Phase.BATTLE and wave._pending > 0 and Time.get_ticks_msec() < deadline:
			await create_timer(0.1).timeout
		check(wave.enemies.size() == 512 and wave._pending == 0, "完整创建 512 只真实怪物并保持 AI、碰撞和攻击")
		await create_timer(2.0).timeout
		check(wave.enemies.size() == 512 and player.current_health == player.max_health, "巨量怪潮持续运行，人物免伤且怪物不被攻击清空")
		print("Actual simulation: alive=%d pending=%d health=%.1f" % [wave.enemies.size(), wave._pending, player.current_health])
		wave.retreat()
	check(wave.waves[0].entries.reduce(func(total, entry): return total + entry.count, 0) == first_wave_total and source.simulation_enemy_count == 512, "源波次和默认模拟资源保持原值")
	await create_timer(0.8).timeout
	world.queue_free()
	await settle()
	await create_timer(0.15).timeout
	print("Horde simulation: %d checks, %d failures" % [checks, failures])
	quit.call_deferred(1 if failures else 0)
