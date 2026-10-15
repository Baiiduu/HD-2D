extends SceneTree

const PROBE := preload("res://tests/fixtures/wave_probe_enemy.gd")
var checks := 0
var failures := 0
var world: Node3D
var wave: WavePrototype
var player: Player

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func probe(id: StringName) -> WaveEnemyDefinition:
	var node := PROBE.new()
	var scene := PackedScene.new()
	assert(scene.pack(node) == OK)
	node.free()
	var definition := WaveEnemyDefinition.new()
	definition.enemy_id = id
	definition.scene = scene
	definition.attack_damage = 0.0
	definition.experience_reward = 0
	return definition

func entry(id: StringName, count: int) -> WaveSpawnEntry:
	var result := WaveSpawnEntry.new()
	result.enemy_id = id
	result.count = count
	result.start_delay = 0.0
	result.interval = 0.001
	result.warning_seconds = 0.0
	return result

func begin() -> bool:
	player.global_position = wave.global_position + Vector3.UP * 0.03
	if not wave.start_run(): return false
	var choice: GrowthChoiceUI = wave.get_node("RunSkills/InitialSkillChoice")
	if choice.is_open:
		choice.reveal_now()
		if not choice.select_option(&"initial:fan_slash"):
			choice.select_option(choice._options[0].id)
		choice.confirm_selection()
	for component: Node in (wave.get_node("RunSkills") as RunSkills)._components.values():
		component.process_mode = Node.PROCESS_MODE_DISABLED
	return wave.phase == WavePrototype.Phase.BATTLE

func reset() -> void:
	wave._finish("test reset")
	wave.return_home()
	wave.population_rules = null
	wave.health_growth_rules = null
	wave.endless_mode = false
	wave.enemy_catalog = null
	wave.waves.clear()
	wave.max_active_enemies = 24
	wave.max_spawns_per_wave = 512
	wave.spawn_warning = 0.0
	wave.default_enemy = load("res://data/enemies/wave_slime.tres")

func spatial_checks() -> void:
	var index := WaveEnemySpatialIndex.new()
	var enemies: Array[WaveEnemy] = []
	for number in 768:
		var enemy := WaveEnemy.new()
		root.add_child(enemy)
		enemy.position = Vector3((number % 32) * 0.9 - 14.4, 0.0, (number / 32) * 0.9 - 10.8)
		enemies.append(enemy)
		index.update(enemy)
	for point in [Vector3(-2, 0, -2), Vector3.ZERO, Vector3(2, 0, 2), Vector3(-14.4, 0, -10.8)]:
		var actual := index.nearby(point, 0.75)
		var expected: Array[WaveEnemy] = []
		for enemy in enemies:
			if TerrainPath.horizontal_distance(enemy.global_position, point) <= 0.75: expected.append(enemy)
		check(actual.size() == expected.size() and expected.all(func(enemy: WaveEnemy): return enemy in actual), "哈希查询与完整精确查询一致，包括负坐标和格边界")
	index.candidate_checks = 0
	for enemy in enemies: index.nearby(enemy.global_position, 0.75)
	check(index.candidate_checks < 768 * 768 / 10, "768 只邻域检查低于全体两两遍历的十分之一")
	for number in [0, 35, 200, 400, 767]:
		var source := enemies[number]
		var expected := Vector3.ZERO
		for other in enemies:
			if other == source: continue
			var offset := source.global_position - other.global_position
			offset.y = 0.0
			var distance := offset.length()
			if distance > 0.01 and distance < 0.75: expected += offset / distance * (0.75 - distance)
		check(index.separation(source, 0.75).is_equal_approx(expected), "局部直接避让与原逐帧完整避让结果一致")
	var moved := enemies[0]
	moved.position = Vector3(80, 0, 80)
	index.update(moved)
	check(moved in index.nearby(moved.position, 0.1), "移动后立即更新格子")
	check(moved not in index.nearby(Vector3(-14.4, 0, -10.8), 0.1), "移动后旧格子移除")
	index.remove(moved)
	check(index.nearby(moved.position, 0.1).is_empty(), "移除后没有悬空成员")
	for enemy in enemies: enemy.free()
	index.clear()

func run() -> void:
	spatial_checks()
	var horde: WavePopulationRules = load("res://data/waves/population/horde_512.tres")
	var stress: WavePopulationRules = load("res://data/waves/population/stress_768.tres")
	check(horde.validation_error().is_empty() and stress.validation_error().is_empty(), "两个大规模预设合法")
	for pair in [[1, 24], [3, 24], [4, 40], [10, 136], [20, 296], [34, 512], [1000000000, 512]]:
		check(horde.active_limit(pair[0]) == pair[1], "同场容量递增与终值准确")
	check(stress.active_limit(1) == 768, "压力档直接提供 768 容量")
	var melee: WaveMeleeEnemyDefinition = load("res://data/enemies/wave_slime.tres").duplicate()
	check(melee.validation_error().is_empty(), "现有史莱姆专属参数保持合法")
	melee.body_radius = 1.0
	check(not melee.validation_error().is_empty(), "扩大身体但未同步通行与刷新半径会明确拒绝")
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await settle(16)
	wave = world.get_node("WavePrototype")
	# 本测试验证普通波次；不受编辑器当前选中的巨量模拟档位影响。
	wave.population_rules = wave.population_rules.duplicate(true)
	wave.population_rules.simulation_mode = false
	player = world.get_node("Player")
	wave.set_physics_process(false)
	player.set_physics_process(false)
	var parameter_catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var parameters: Array[Dictionary] = parameter_catalog.collect(world)
	for property in ["enemy_catalog", "population_rules", "health_growth_rules", "health_growth_enabled", "start_wave", "bonus_per_wave", "minimum_multiplier", "maximum_multiplier", "enemy_id", "health", "body_radius", "navigation_radius", "max_active", "role_limits"]:
		check(parameters.any(func(item: Dictionary): return item.property == property and item.category == "战斗与成长"), "参数总览可查找怪物和容量参数：" + property)
	check(begin(), "实际开局选技能后正常进入战斗")
	check(wave.get_active_enemy_limit() == 24 and wave._pending == 18, "正式首波保持原数量和同场上限")
	wave._physics_process(1.0)
	var slime := wave.enemies[0] as SlimeEnemy
	check(slime.definition is WaveMeleeEnemyDefinition and slime.body_radius == 0.28 and slime.contact_distance == 0.85, "史莱姆实际应用统一专属数据")
	slime.set_physics_process(false)
	var path := wave._path
	var goal := wave._ground_target()
	var builds := path.shared_field_builds
	for point in wave._spawn_points:
		check(path.shared_reachable(point, goal) == not path.pursuit_route(point, goal).is_empty(), "正式地图共享连通性与原严格寻路一致")
	check(path.shared_field_builds - builds <= 1, "同一个目标只建立一次共享追击树")
	var route := path.shared_pursuit_route(slime.global_position, goal)
	check(not route.is_empty(), "实际追击得到可用共享路线")
	# 新动态障碍仍检查首段，不因共享拓扑穿过新墙。
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 2.0, 1.0)
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	wall.global_position = slime.global_position + Vector3.UP * 0.5
	await settle()
	check(not path.shared_reachable(slime.global_position, goal), "新动态挡墙实时使刷怪连通资格失败")
	wall.free()
	await settle()
	check(path.shared_reachable(slime.global_position, goal), "撤掉动态挡墙后资格恢复")
	# 目录未用于开场的召唤体也做快照；分种上限和成本共享预算。
	reset()
	var elite := probe(&"elite_probe")
	elite.role = WaveEnemyDefinition.Role.ELITE
	elite.population_cost = 4
	elite.max_alive = 1
	var common := probe(&"common_probe")
	var catalog := WaveEnemyCatalog.new()
	catalog.enemies.assign([elite, common])
	wave.enemy_catalog = catalog
	var rules := WavePopulationRules.new()
	rules.first_active_limit = 4
	rules.max_active = 4
	rules.max_population_cost = 5
	rules.role_limits = PackedInt32Array([4, 4, 1, 1])
	rules.max_wave_enemies = 16
	rules.max_queued_per_wave = 32
	rules.spawns_per_tick = 4
	rules.position_attempts = 40
	var plan := WaveDefinition.new()
	plan.entries.assign([entry(&"elite_probe", 2), entry(&"common_probe", 2)])
	wave.waves.assign([plan])
	wave.population_rules = rules
	check(begin(), "仅用怪物标识编排混合波次")
	common.health = 999.0
	rules.max_population_cost = 100
	wave._physics_process(0.1)
	for enemy in wave.enemies: enemy.set_physics_process(false)
	check(wave.enemies.size() == 2 and wave._population_cost == 5 and wave._pending == 2, "同种／精英／成本预算生效且不饿死普通怪组")
	check(wave.enemies[1].health == 20.0 and wave._run_population.max_population_cost == 5, "怪物和容量修改不污染当前局快照")
	wave._physics_process(15.0)
	check(wave.phase == WavePrototype.Phase.BATTLE and wave._pending == 2, "容量等待超过堵点超时也保留队列")
	var clock := wave._wave_clock
	wave.set_combat_frozen(true)
	wave._physics_process(3.0)
	check(wave._wave_clock == clock and wave._pending == 2, "成长冻结停止出怪和战斗时间")
	wave.set_combat_frozen(false)
	wave.enemies[0].take_damage(1000.0)
	wave._physics_process(0.1)
	for enemy in wave.enemies: enemy.set_physics_process(false)
	check(wave.enemies.size() == 2 and wave._pending == 1 and wave._population_cost == 5, "死亡立即释放预算并恢复排队精英")
	for enemy in wave.enemies.duplicate(): enemy.take_damage(1000.0)
	wave._physics_process(0.1)
	check(wave.enemies.size() == 1 and wave._pending == 0, "最后普通怪仍然出场，不丢任务")
	var stale := wave.enemies[0].request_spawn_by_id
	check(wave.queue_spawn_by_id(&"common_probe", 1, 0.5), "按目录标识登记延迟召唤")
	wave.enemies[0].take_damage(1000.0)
	wave._physics_process(0.1)
	check(wave.phase == WavePrototype.Phase.BATTLE and wave._pending == 1, "延迟召唤阻止提前清波")
	wave._physics_process(0.5)
	check(wave.enemies.size() == 1 and wave.enemies[0].health == 20.0, "召唤体使用开局目录快照")
	wave.enemies[0].take_damage(1000.0)
	wave._physics_process(0.1)
	check(wave.outcome == WavePrototype.Outcome.VICTORY and wave.kills == 5 and wave._population_cost == 0, "五只全部击败才结束，预算清空")
	check(not stale.call(&"common_probe", 1, 0.0, Vector3.INF), "旧局召唤回调失效")
	reset()
	wave.population_rules = horde
	wave.enemy_catalog = load("res://data/enemies/enemy_catalog.tres")
	wave.waves.assign([load("res://data/waves/wave_01.tres"), load("res://data/waves/wave_02.tres"), load("res://data/waves/wave_03.tres")])
	wave.endless_mode = true
	check(begin(), "512 档兼容正式三个开场模板")
	var late := wave._definition_for_wave(1000000000)
	check(wave._wave_total(late) == 1536 and wave._run_waves.size() == 3, "极大波号总量受限且不累计历史模板")
	check(late.entries.all(func(group: WaveSpawnEntry): return group.interval >= 0.025), "大规模刷新间隔仍有明确下限")
	wave.wave = 34
	check(wave.get_active_enemy_limit() == 512, "第 34 波达到 512 同场容量")
	reset()
	var large: WaveMeleeEnemyDefinition = load("res://data/enemies/wave_slime.tres").duplicate()
	large.body_radius = 0.4
	large.body_height = 0.9
	large.spawn_clearance = 0.45
	large.navigation_radius = 0.45
	large.move_speed = 0.0
	wave.default_enemy = large
	wave.first_wave_enemies = 1
	check(begin(), "较大实体按尺寸预热导航")
	check(wave._paths_by_radius.size() == 1, "不同通行半径只建立一份共享图")
	check(wave._spawn_enemy(), "较大实体通过自身碰撞与通行半径刷新")
	var large_enemy := wave.enemies[0] as SlimeEnemy
	large_enemy.set_physics_process(false)
	check(large_enemy.body_radius == 0.4 and large_enemy.navigation == wave._paths_by_radius[0.45], "实际身体尺寸和共享导航一致")
	var large_path := large_enemy.navigation
	wave.terrain.data.emit_changed()
	await settle(8)
	check(large_enemy.navigation == large_path and large_path.graph.get_point_count() > 0 and wave._path_ready, "地形重建原地更新各尺寸导航，不留下旧图")
	reset()
	catalog.enemies.append(elite)
	wave.enemy_catalog = catalog
	check(not begin() and wave.result_reason.contains("重复"), "重复标识在开局前被拒绝")
	reset()
	common.health = 20.0
	common.experience_reward = -1
	wave.default_enemy = common
	check(not begin() and wave.result_reason.contains("经验"), "负经验数值在开局前被拒绝")
	reset()
	plan.entries.assign([entry(&"missing", 1)])
	wave.waves.assign([plan])
	check(not begin() and wave.result_reason.contains("未登记"), "未登记 ID 不留下死等队列")
	reset()
	await settle()
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	await create_timer(0.1).timeout
	world.queue_free()
	await settle()
	await create_timer(0.1).timeout
	print("Enemy framework: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
