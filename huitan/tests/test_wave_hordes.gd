extends SceneTree

const PROBE := preload("res://tests/fixtures/wave_probe_enemy.gd")
var world: Node3D
var wave: WavePrototype
var checks := 0
var failures: Array[String] = []
var source_waves: Array[WaveDefinition] = []
var source_rules: WavePopulationRules

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ", message)

func settle(count := 3) -> void:
	for frame in count: await physics_frame

func probe(health := 30.0) -> WaveEnemyDefinition:
	var node := PROBE.new()
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()
	var result := WaveEnemyDefinition.new()
	result.scene = scene
	result.health = health
	result.attack_damage = 0
	result.move_speed = 0
	result.experience_reward = 0
	return result

func group(enemy: WaveEnemyDefinition, count: int, delay := 0.0, batch := 1, zones := PackedStringArray()) -> WaveSpawnEntry:
	var result := WaveSpawnEntry.new()
	result.enemy = enemy
	result.count = count
	result.start_delay = delay
	result.batch_size = batch
	result.interval = 0.1 if batch == 1 else 2.0
	result.spawn_zone_ids = zones
	return result

func mixed(count: int, delay := 0.0, batch := 1, zones := PackedStringArray()) -> WaveSpawnEntry:
	var result := group(null, count, delay, batch, zones)
	result.mixed_horde = true
	return result

func catalog(definitions: Array[WaveEnemyDefinition]) -> WaveEnemyCatalog:
	var result := WaveEnemyCatalog.new()
	result.enemies.assign(definitions)
	return result

func mixed_checks() -> void:
	var common := probe(30)
	common.enemy_id = &"mixed_common"
	var special := probe(40)
	special.enemy_id = &"mixed_special"
	special.role = WaveEnemyDefinition.Role.SPECIAL
	special.population_cost = 3
	special.max_alive = 2
	var child := probe(8)
	child.enemy_id = &"mixed_child"
	child.horde_weight = 0.0
	var newcomer := probe(50)
	newcomer.enemy_id = &"mixed_newcomer"
	var roster := catalog([common, special, child])
	reset([mixed(8, 1.0, 8)], 12)
	wave.enemy_catalog = roster
	check(start(), "目录混合怪潮实际开局")
	var batch: Dictionary = wave._spawn_queue[0].batch
	check(batch.counts.size() == 2 and batch.counts.values().reduce(func(sum, value): return sum + value, 0) == 8, "多种怪共享同一个批次及整批容量账本")
	roster.enemies.append(newcomer)
	tick(1.01)
	check(wave.enemies.size() == 2 and wave.enemies[0].definition.enemy_id != wave.enemies[1].definition.enemy_id, "同批首帧即可混合两种怪，仍遵守创建预算")
	wave.set_combat_frozen(true)
	var remaining := int(batch.remaining)
	tick(10)
	check(batch.remaining == remaining, "冻结保留混合怪潮的未出场成员与类型账本")
	wave.set_combat_frozen(false)
	for step in 3: tick()
	check(wave.enemies.size() == 8 and wave.enemies.all(func(mob): return mob.definition.enemy_id in [&"mixed_common", &"mixed_special"]), "权重零幼体不独立刷新，本局目录快照不受追加资源影响")
	check(wave.enemies.filter(func(mob): return mob.definition.enemy_id == &"mixed_special").size() == 2, "混合怪潮不会突破同种上限")
	check(batch.remaining == 0 and batch.cost == 0 and batch.roles == [0, 0, 0, 0] and wave._reserved_batch.is_empty(), "完整出场逐个释放混合成本、角色与个体预留")
	var compact := true
	for first in wave.enemies:
		for second in wave.enemies: compact = compact and TerrainPath.horizontal_distance(first.global_position, second.global_position) <= 8.1
	check(compact, "不同类型沿用同一批入口与聚集范围")
	reset([mixed(10, 0, 10)], 16)
	wave.enemy_catalog = roster
	check(start(), "新挑战重新读取追加后的目录")
	var ids := {}
	for job in wave._spawn_queue: ids[job.enemy.enemy_id] = true
	check(ids.has(&"mixed_newcomer") and ids.size() == 3 and not ids.has(&"mixed_child"), "只登记新怪就自动进入原有怪潮，无需修改波次")
	reset([group(common, 2), mixed(4, 1.0, 4), group(special, 1, 1.1)], 8)
	wave.enemy_catalog = catalog([common, special, child])
	var rules := WavePopulationRules.new()
	rules.first_active_limit = 8
	rules.max_active = 8
	rules.max_population_cost = 10
	rules.role_limits = PackedInt32Array([8, 2, 0, 0])
	rules.spawns_per_tick = 2
	rules.checks_per_tick = 8
	wave.population_rules = rules
	check(start(), "混合成本与角色上限场景开局")
	tick(0.2)
	tick(1.0)
	check(wave.enemies.size() == 4 and wave._reserved_batch.remaining == 2 and wave._population_cost + int(wave._reserved_batch.cost) == 10, "整批预留所有类型成本，而非按当前一只怪估算")
	tick()
	check(wave.enemies.size() == 6 and wave._pending == 1 and wave._population_cost == 10, "后续散兵不能占走混合怪潮剩余的成本与分类额度")
	var victim: WaveEnemy = wave.enemies.filter(func(mob): return mob.definition.enemy_id == &"mixed_special")[0]
	defeat(victim)
	await settle()
	tick()
	check(wave.enemies.size() == 6 and wave._pending == 0 and wave._population_cost == 10, "怪潮完成并释放种类容量后继续放行散兵")
	reset([mixed(3, 0, 3)])
	wave.enemy_catalog = catalog([special])
	check(not start() and wave.outcome == WavePrototype.Outcome.ERROR, "无法容纳的混合批次在开局前拒绝，不永久等待")
	reset([mixed(4, 0, 4)])
	wave.enemy_catalog = catalog([child])
	check(not start() and wave.outcome == WavePrototype.Outcome.ERROR, "目录无可参与怪物时明确报错，不擅自刷幼体")
	common.horde_weight = 4.0
	newcomer.horde_weight = 1.0
	var usage := {}
	var planned := WaveHordePlanner.plan([common, newcomer], 20, 24, 100, PackedInt32Array([24, 24, 1, 1]), usage)
	check(planned.count(common) == 16 and planned.count(newcomer) == 4, "批次覆盖类型后按权重控制其余比例")
	var many: Array[WaveEnemyDefinition] = []
	for index in 6:
		var definition := probe()
		definition.enemy_id = StringName("future_%d" % index)
		many.append(definition)
	usage.clear()
	for index in 3: WaveHordePlanner.plan(many, 2, 24, 100, PackedInt32Array([24, 24, 1, 1]), usage)
	check(usage.size() == 6, "批次较小时轮换覆盖目录，新类型不会因目录位置永久饿死")
	common.horde_weight = NAN
	check(not common.validation_error().is_empty(), "怪潮权重拒绝非有限数值")

func reset(entries: Array[WaveSpawnEntry], limit := 24) -> void:
	wave._finish("fixture reset")
	wave.return_home()
	wave.population_rules = null
	wave.health_growth_rules = null
	wave.endless_mode = false
	wave.max_active_enemies = limit
	wave.max_spawns_per_tick = 2
	wave.max_spawn_checks_per_tick = 8
	wave.spawn_spacing = 0.7
	wave.enemy_catalog = null
	var definition := WaveDefinition.new()
	definition.entries.assign(entries)
	wave.waves.assign([definition])
	wave.player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	wave.player.velocity = Vector3.ZERO

func tick(delta := 0.02) -> void:
	wave._physics_process(delta)
	for enemy in wave.enemies: enemy.set_physics_process(false)

func start() -> bool:
	if not wave.start_run(): return false
	var choice: GrowthChoiceUI = wave.get_node("SkillDraft/InitialSkillChoice")
	if choice.is_open:
		choice.reveal_now()
		choice.select_option(choice._options[0].id)
		choice.confirm_selection()
	for component: Node in (wave.get_node("RunSkillManager") as RunSkillManager)._components.values():
		component.process_mode = Node.PROCESS_MODE_DISABLED
	return wave.phase == WavePrototype.Phase.BATTLE

func defeat(enemy: WaveEnemy) -> void:
	enemy.spawn_delay = 0
	enemy.take_damage(100000)

func run() -> void:
	var terrain_hash := FileAccess.get_sha256("res://data/world/world_terrain.tres")
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WavePresentation").enabled = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await settle(16)
	wave = world.get_node("WavePrototype")
	# 批次规则使用即时生成夹具；新预告的容量与时序有独立回归。
	wave.spawn_shadow_settings = null
	wave.set_physics_process(false)
	wave.player.set_physics_process(false)
	source_waves.assign(wave.waves)
	source_rules = wave.population_rules
	var parameters: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(world)
	check(parameters.any(func(item): return item.property == "batch_size" and item.category == "战斗与成长" and item.common and "怪潮每批数量" in item.label), "怪潮批量可在参数总览的常用战斗参数中调节")
	for property in ["mixed_horde", "horde_weight"]:
		check(parameters.any(func(item): return item.property == property and item.category == "战斗与成长" and item.common), "自动混合怪潮参数可从统一入口调节：" + property)
	var enemy := probe()
	var later := probe(40)
	var west := PackedStringArray(["WestNorth"])
	var east := PackedStringArray(["EastNorth"])
	# 完整一批占用多帧创建，但不再按单只间隔拉长，也不重叠或散到全地图。
	reset([group(enemy, 10, 1.0, 10)], 16)
	check(start(), "成批刷新实际开局")
	tick(0.99)
	check(wave.enemies.is_empty() and wave._pending == 10, "怪潮在约定时刻前不提前出场")
	tick(0.02)
	check(wave.enemies.size() == 2 and wave._pending == 8, "首帧仍遵守创建预算")
	var clock := wave._wave_clock
	wave.set_combat_frozen(true)
	tick(20)
	check(wave._wave_clock == clock and wave.enemies.size() == 2 and wave._pending == 8, "升级冻结完整保留半批怪潮")
	wave.set_combat_frozen(false)
	for step in 4: tick()
	check(wave.enemies.size() == 10 and wave._pending == 0 and wave._wave_clock - clock < 0.11, "十只怪在短窗口内完整出场")
	var compact := true
	var safe := true
	for first in wave.enemies:
		safe = safe and TerrainPath.horizontal_distance(first.global_position, wave.player.global_position) >= wave.spawn_safe_distance
		for second in wave.enemies:
			var distance := TerrainPath.horizontal_distance(first.global_position, second.global_position)
			compact = compact and distance <= 8.1
			if first != second: safe = safe and distance >= wave.spawn_spacing - 0.01
	check(compact and safe, "怪潮集中在同一片外围，保留人物安全距离与实体间距")
	check(wave._reserved_batch.is_empty(), "完整进场后归还预留容量")
	for mob in wave.enemies.duplicate(): defeat(mob)
	tick()
	check(wave.outcome == WavePrototype.Outcome.VICTORY and wave.kills == 10, "成批敌人全部真实击败后才清波")
	await settle()
	# 剩余容量不足时整批等位；晚到的散兵不能反复抢走刚释放的位置。
	reset([group(enemy, 5), group(enemy, 4, 1.0, 4, west), group(later, 2, 1.1, 1, east)], 8)
	check(start(), "容量预留场景开局")
	for step in 3: tick(0.2)
	check(wave.enemies.size() == 5, "先正常放行散兵")
	tick(0.6)
	check(wave.enemies.size() == 5 and wave._pending == 6, "不足整批容量时不逐只塞入怪潮或后续散兵")
	defeat(wave.enemies[0])
	await settle()
	tick()
	check(wave.enemies.size() == 6 and wave._pending == 4, "腾足整批空间后按帧预算启动怪潮")
	tick()
	check(wave.enemies.size() == 8 and wave._pending == 2 and wave.enemies.all(func(mob): return mob.max_health == 30), "分帧过程中的位置持续留给当前怪潮")
	defeat(wave.enemies[0])
	await settle()
	tick()
	check(wave.enemies.size() == 8 and wave.enemies[-1].max_health == 40, "怪潮完整入场后继续放行后续散兵")
	reset([group(enemy, 6), group(later, 4, 0.3, 4)], 8)
	check(start(), "散兵积压场景开局")
	for step in 4: tick(0.5 if step == 0 else 0.02)
	check(wave.enemies.size() == 8 and wave.enemies.filter(func(mob): return mob.max_health == 40).size() == 4 and wave._pending == 2, "到期怪潮不被更早的散兵积压反复抢满容量")
	# 区域缓存只缓存候选地表；动态墙体仍会阻挡后续成员。
	await settle()
	reset([group(enemy, 6, 0, 6, west)], 12)
	check(start(), "动态障碍场景开局")
	tick()
	var zone: WaveSpawnZone = wave._spawn_zones.filter(func(item): return item.get_zone_id() == &"WestNorth")[0]
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 4, 8)
	collision.shape = box
	wall.add_child(collision)
	world.add_child(wall)
	wall.global_position = zone.global_position + Vector3.UP
	await settle()
	wave.queue_spawn(later, 1, 0, Vector3.INF, east)
	tick(0.4)
	check(wave.enemies.size() == 3 and wave.enemies[-1].max_health == 40 and wave._pending == 4, "新墙阻挡已缓存怪潮入口，另一侧散兵仍可出场")
	wall.queue_free()
	await settle()
	for step in 3: tick(0.31)
	check(wave.enemies.size() == 7 and wave._pending == 0, "移走动态墙后整批剩余成员继续进场")
	# 末批不足原每批数量时如实生成，不补怪。
	reset([group(enemy, 7, 0, 3, east)], 12)
	check(start(), "非整批数量场景开局")
	for step in 2: tick()
	check(wave.enemies.size() == 3, "首批数量正确")
	for step in 2: tick(1.0)
	tick()
	check(wave.enemies.size() == 6 and wave._pending == 1, "第二批保持批次间隔")
	tick(2.0)
	check(wave.enemies.size() == 7 and wave._pending == 0, "末批不足时不补齐虚假数量")
	# 不可能容纳的批次在开局前报错，不会永久等位。
	reset([group(enemy, 9, 0, 9)], 8)
	check(not start() and wave.outcome == WavePrototype.Outcome.ERROR and wave.enemies.is_empty(), "超过同场容量的批次在开局前拒绝")
	var limited := probe()
	limited.max_alive = 2
	reset([group(limited, 3, 0, 3)])
	check(not start() and wave.outcome == WavePrototype.Outcome.ERROR, "超过同种容量的批次在开局前拒绝")
	reset([group(enemy, 6, 0, 6)])
	start()
	tick()
	wave.retreat()
	check(wave.enemies.is_empty() and wave._pending == 0 and wave._reserved_batch.is_empty(), "撤退清除半批怪潮、待生成成员和容量预留")
	await settle()
	await mixed_checks()
	# 正式配置保留前三波总数，四种主怪混编，辅助蛙独立少量穿插。
	reset([])
	wave.waves.assign(source_waves)
	wave.population_rules = source_rules
	wave.enemy_catalog = load("res://data/combat/scenes/world/enemies/enemy_catalog.tres")
	wave.endless_mode = true
	check(start(), "正式怪潮编排实际开局")
	for index in 3:
		var definition := wave._definition_for_wave(index + 1)
		var batches := definition.entries.filter(func(item): return item.batch_size > 1)
		check(wave._wave_total(definition) == [18, 28, 40][index] and batches.size() == 1 and batches[0].batch_size == 13 and batches[0].mixed_horde, "前三波总数不变，目录混合怪潮以完整比例批次出现")
	for number in [4, 10, 25, 1000000000]:
		var definition := wave._definition_for_wave(number)
		var batch: WaveSpawnEntry = definition.entries.filter(func(item): return item.batch_size > 1)[0]
		check(batch.batch_size >= 13 and batch.batch_size <= wave._run_population.active_limit(number), "无尽怪潮受当前波容量约束")
	var late := wave._definition_for_wave(25)
	var expected_late := mini(40 + (25 - source_waves.size()) * source_rules.enemies_per_wave_increment, source_rules.max_wave_enemies)
	check(wave._wave_total(late) == expected_late and late.entries[1].batch_size > 13 and late.entries[1].batch_size <= floori(wave._run_population.active_limit(25) * 0.5), "后期怪潮按当前独立配置扩大，并为其它敌人保留至少一半同场容量")
	check(source_waves[2].entries[1].batch_size == 13, "无尽规划不修改原始怪潮资源")
	var births: Array[Dictionary] = []
	var record := func(mob: WaveEnemy): births.append({"wave":wave.wave, "time":wave._wave_clock, "kind":mob.definition.enemy_id})
	wave.enemy_spawned.connect(record)
	for number in [1, 2, 3, 4, 16, 25]:
		if number != 1:
			wave.wave = number - 1
			check(wave.start_next_wave(), "实际续波与跳转压力波正常开始")
		var definition := wave._definition_for_wave(number)
		var expected := wave._wave_total(definition)
		for job in wave._spawn_queue:
			if job.enemy.enemy_id == &"pot_brood": expected += 2
		var steps := 0
		var within_capacity := true
		while wave.phase == WavePrototype.Phase.BATTLE and steps < 1200:
			tick(0.2)
			within_capacity = within_capacity and wave.enemies.size() <= wave.get_active_enemy_limit()
			if wave._pending == 0 or steps % 8 == 0:
				for mob in wave.enemies.duplicate().slice(0, 8): defeat(mob)
				await settle(1)
			steps += 1
		check(wave.phase == WavePrototype.Phase.REST and wave._spawned_this_wave == expected and within_capacity, "正式波 %d 怪潮、特殊怪与分裂幼体完整出场、封顶并清波" % number)
		if wave.phase != WavePrototype.Phase.REST:
			print("Production horde state: ", wave.get_run_state())
			break
	var first_horde := births.filter(func(item): return item.wave == 1 and item.kind != &"mini_slime" and item.time >= 6.0 and item.time < 10.0)
	var first_kinds := {}
	for birth in first_horde: first_kinds[birth.kind] = true
	check(first_horde.size() == 13 and first_horde[-1].time - first_horde[0].time <= 0.61 and first_kinds.size() == 4 and not first_kinds.has(&"bell_frog"), "正式首波十三只怪潮覆盖四种主怪并集中出现，辅助蛙留到后续波次")
	wave.enemy_spawned.disconnect(record)
	check(FileAccess.get_sha256("res://data/world/world_terrain.tres") == terrain_hash, "不修改地形与手绘地图")
	wave.retreat()
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	world.queue_free()
	await settle(6)
	await create_timer(0.15).timeout
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
