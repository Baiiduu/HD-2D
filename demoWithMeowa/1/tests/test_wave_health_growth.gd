extends SceneTree

var checks := 0
var failures := 0
var world: Node3D
var wave: WavePrototype

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func start() -> bool:
	wave.player.global_position = wave.global_position + Vector3.UP * 0.03
	if not wave.start_run(): return false
	var choice: GrowthChoiceUI = wave.get_node("SkillDraft/InitialSkillChoice")
	if choice.is_open:
		choice.reveal_now()
		choice.select_option(choice._options[0].id)
		choice.confirm_selection()
	for component: Node in (wave.get_node("RunSkillManager") as RunSkillManager)._components.values():
		component.process_mode = Node.PROCESS_MODE_DISABLED
	return wave.phase == WavePrototype.Phase.BATTLE

func run() -> void:
	var rules := WaveHealthGrowthRules.new()
	check(rules.validation_error().is_empty(), "正式成长规则合法")
	for pair in [[1, 1.0], [3, 1.0], [4, 1.15], [10, 2.05], [20, 3.55], [62, 9.85], [63, 10.0], [1000000000, 10.0]]:
		check(is_equal_approx(rules.multiplier(pair[0]), pair[1]), "起始波、线性增幅和十倍封顶准确")
	rules.maximum_multiplier = 11.0
	check(not rules.validation_error().is_empty(), "不允许配置超过十倍")
	rules.maximum_multiplier = 0.9
	check(not rules.validation_error().is_empty(), "不允许上限低于下限")
	rules.maximum_multiplier = 10.0
	rules.bonus_per_wave = -0.1
	check(not rules.validation_error().is_empty(), "不允许负成长")
	rules.bonus_per_wave = 0.0
	check(rules.multiplier(1000000000) == 1.0, "零增幅保持基础生命")
	rules.minimum_multiplier = 2.0
	rules.maximum_multiplier = 5.0
	check(rules.multiplier(1) == 2.0 and rules.multiplier(1000000000) == 2.0, "自定义下限与零增幅正确")
	rules.bonus_per_wave = 0.15
	check(rules.multiplier(1) == 2.0 and rules.multiplier(1000000000) == 5.0, "自定义上下限都生效")
	rules.minimum_multiplier = 1.0
	rules.maximum_multiplier = 10.0
	rules.bonus_per_wave = 1e-300
	check(rules.multiplier(1000000000) == 1.0, "极小正增幅不溢出步数")
	rules.bonus_per_wave = 0.15
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	var profile := preload("res://tests/fixtures/combat_scene_fixture.gd").isolate_profile(world)
	# 固定历史曲线以验证计算规则，不让正式平衡调整改写测试的已知答案。
	profile.population_rules = profile.population_rules.duplicate()
	profile.population_rules.simulation_mode = false
	profile.population_rules.first_active_limit = 24
	profile.population_rules.growth_start_wave = 4
	profile.population_rules.active_growth_per_wave = 8
	profile.population_rules.max_active = 128
	profile.population_rules.enemies_per_wave_increment = 16
	profile.population_rules.max_wave_enemies = 384
	profile.default_enemy = profile.default_enemy.duplicate()
	profile.default_enemy.health = 20.0
	root.add_child(world)
	current_scene = world
	await settle(16)
	wave = world.get_node("WavePrototype")
	wave.set_physics_process(false)
	wave.player.set_physics_process(false)
	check(wave.population_rules == profile.population_rules, "地图读取自己的独立数量配置")
	check(wave.health_growth_rules == profile.health_growth_rules, "地图读取自己的独立生命成长配置")
	check(start(), "正式地图使用接入后的规则实际开局")
	check(wave.get_active_enemy_limit() == 24 and wave._pending == 18, "正式开场仍为 18 只、同场容量 24")
	for pair in [[4, 56, 32], [10, 152, 80], [16, 248, 128], [25, 384, 128], [1000000000, 384, 128]]:
		check(wave._wave_total(wave._definition_for_wave(pair[0])) == pair[1] and wave._run_population.active_limit(pair[0]) == pair[2], "正式数量曲线、单波总数和同场容量分别封顶")
	wave._spawn_queue.clear()
	wave.wave = 16
	var spawned := 0
	for number in 128:
		if not wave._spawn_enemy(): break
		spawned += 1
		wave.enemies[-1].set_physics_process(false)
	check(spawned == 128 and not wave._spawn_enemy(), "正式地图实际生成 128 只并阻止超过同场上限")
	check(is_equal_approx(wave.enemies[0].health, 59.0), "固定夹具中第十六波每只史莱姆应用 2.95 倍生命")
	wave._finish("test reset")
	wave.return_home()
	wave.population_rules = null
	wave.health_growth_rules = rules
	wave.endless_mode = true
	var ordinary_health := wave.default_enemy.health
	check(start(), "无尽模式实际开局")
	wave._spawn_queue.clear()
	check(wave.get_enemy_health_multiplier() == 1.0, "前三波保持基础生命")
	wave.wave = 4
	check(wave._spawn_enemy(), "成长后的实际怪物出场")
	var enemy := wave.enemies[0]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	check(is_equal_approx(enemy.health, ordinary_health * 1.15) and enemy.max_health == enemy.health and enemy.spawn_wave == 4, "兼容曲线第四波应用基础生命的 1.15 倍")
	check(enemy.definition.health == ordinary_health, "不修改怪物基础资源")
	enemy.take_damage(10.0)
	check(is_equal_approx(enemy.health, ordinary_health * 1.15 - 10.0) and is_equal_approx(enemy.max_health, ordinary_health * 1.15), "真实伤害扣成长后生命，最大生命保持")
	rules.bonus_per_wave = 1.0
	rules.maximum_multiplier = 2.0
	check(is_equal_approx(wave.get_enemy_health_multiplier(), 1.15), "运行中编辑规则不改变当前局")
	wave._finish("test reset")
	wave.return_home()
	rules.bonus_per_wave = 0.15
	rules.maximum_multiplier = 10.0
	check(start(), "重试／新挑战重新建立成长快照")
	wave._spawn_queue.clear()
	wave.wave = 1000000000
	check(wave._spawn_enemy(), "极大波号仍可正常出场")
	enemy = wave.enemies[0]
	enemy.set_physics_process(false)
	check(enemy.health == ordinary_health * 10.0 and enemy.health_multiplier == 10.0, "实际怪物生命最高基础值的十倍")
	var fixed: WaveEnemyDefinition = wave.default_enemy.duplicate()
	fixed.health_growth_enabled = false
	check(wave._spawn_enemy(fixed) and wave.enemies[-1].health == ordinary_health, "固定生命怪物可独立关闭成长")
	wave.enemies[-1].set_physics_process(false)
	var base_health := wave.default_enemy.health
	check(wave.queue_spawn_by_id(&"slime", 1, 0.5), "延迟召唤通过同一成长接口")
	wave._physics_process(0.6)
	check(wave.enemies[-1].health == wave.enemies[-1].definition.health * 10.0, "召唤怪物按自己的基础生命应用当前波成长")
	for mob in wave.enemies: mob.set_physics_process(false)
	check(wave.get_run_state().enemy_health_multiplier == 10.0, "运行状态暴露真实倍率")
	wave._finish("test reset")
	wave.return_home()
	wave.endless_mode = false
	check(start(), "有限模式兼容开局")
	wave._spawn_queue.clear()
	wave.wave = 63
	check(wave._spawn_enemy() and wave.enemies[-1].health == ordinary_health, "有限模式不意外应用无尽成长")
	wave._finish("test reset")
	wave.return_home()
	rules.maximum_multiplier = 11.0
	check(not start() and wave.outcome == WavePrototype.Outcome.ERROR and wave.enemies.is_empty() and wave._pending == 0, "无效规则在开局前明确失败并清理")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	await create_timer(0.1).timeout
	world.queue_free()
	await settle()
	await create_timer(0.1).timeout
	print("Wave health growth: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
