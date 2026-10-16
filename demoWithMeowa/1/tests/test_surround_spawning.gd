extends "res://tests/test_wave_hordes.gd"

var positions := PackedVector3Array()
var settings: WavePopulationRules

func configure(limit := 64, endless := true) -> void:
	var enemy := probe()
	enemy.enemy_id = &"surround_probe"
	reset([mixed(16, 0.0, 16, PackedStringArray(["WestNorth"]))], 64)
	wave.enemy_catalog = catalog([enemy])
	wave.endless_mode = endless
	settings = WavePopulationRules.new()
	settings.first_active_limit = limit
	settings.max_active = limit
	settings.active_growth_per_wave = 0
	settings.enemies_per_wave_increment = 0
	settings.max_wave_enemies = 64
	settings.max_queued_per_wave = 128
	settings.role_limits = PackedInt32Array([64, 12, 4, 1])
	settings.surround_start_wave = 2
	settings.spawns_per_tick = 2
	settings.checks_per_tick = 8
	wave.population_rules = settings
	positions.clear()
	check(start(), "多向刷新配置可实际开局")

func second_wave(point: Vector3) -> void:
	for step in 100:
		if wave._pending == 0: break
		tick(0.1)
	for enemy in wave.enemies.duplicate(): defeat(enemy)
	tick()
	await settle()
	check(wave.phase == WavePrototype.Phase.REST, "首波真实清完后仍安全休整")
	wave.player.global_position = wave._path.ground_position(point) + Vector3.UP * 0.03
	positions.clear()
	check(wave.start_next_wave() and wave.wave == 2, "主动继续后第二波启用多向刷新")

func finish_batch() -> void:
	for step in 150:
		if wave._pending == 0 or wave.phase != WavePrototype.Phase.BATTLE: break
		tick(0.1)

func safe_positions(origin: Vector3) -> bool:
	for point in positions:
		if not wave._inside_area(point) or TerrainPath.horizontal_distance(point, origin) < wave.spawn_safe_distance - 0.001: return false
	for first in positions.size():
		for second in first:
			if TerrainPath.horizontal_distance(positions[first], positions[second]) < settings.spawn_spacing - 0.01: return false
	return true

func angular_gap(origin: Vector3) -> float:
	var angles: Array[float] = []
	for point in positions: angles.append(fposmod(Vector2(point.x - origin.x, point.z - origin.z).angle(), TAU))
	if angles.is_empty(): return TAU
	angles.sort()
	var result := angles[0] + TAU - angles[-1]
	for index in range(1, angles.size()): result = maxf(result, angles[index] - angles[index - 1])
	return result

func run() -> void:
	var terrain_hash := FileAccess.get_sha256("res://data/world/world_terrain.tres")
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await settle(16)
	wave = world.get_node("WavePrototype")
	wave.set_physics_process(false)
	wave.player.set_physics_process(false)
	wave.enemy_spawned.connect(func(enemy: WaveEnemy): positions.append(enemy.global_position))
	check(wave.population_rules.surround_start_wave == 2, "正式地图配置从第二波开始多向进场")
	var parameters: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(world)
	for field in ["surround_start_wave", "surround_max_fronts"]:
		check(parameters.any(func(item): return item.property == field and item.category == "战斗与成长" and item.common), "参数总览可调多向进场：" + field)
	var center := wave.battle_area.get_center()
	var origin := Vector3(center.x, 0, center.y)
	configure()
	check(not wave._surround_spawns(), "第一波继续使用原有入口")
	finish_batch()
	var zone: WaveSpawnZone = wave._spawn_zones.filter(func(item): return item.get_zone_id() == &"WestNorth")[0]
	check(positions.size() == 16 and positions_all_near(zone.global_position, 6.0), "首波限定入口仍集中成批出场")
	await second_wave(origin)
	var source_ids := wave._run_waves[0].entries[0].spawn_zone_ids.duplicate()
	tick()
	check(positions.size() == 2 and wave._reserved_batch.remaining == 14, "多向批次继续共用整批预留和每帧两只预算")
	var clock := wave._wave_clock
	wave.set_combat_frozen(true)
	tick(10)
	check(positions.size() == 2 and wave._wave_clock == clock, "冻结不推进方向轮换、出怪或排期")
	wave.set_combat_frozen(false)
	finish_batch()
	check(positions.size() == 16 and wave._pending == 0 and wave._reserved_batch.is_empty(), "第二波整批完整出场并释放预留")
	check(safe_positions(origin) and angular_gap(origin) < PI * 0.9, "实际生成覆盖人物周围且保留安全距离、间距和战区边界")
	check(source_ids == PackedStringArray(["WestNorth"]) and wave._run_waves[0].entries[0].spawn_zone_ids == source_ids, "多向进场不改写开场模板的入口限制")
	var expected := positions.duplicate()
	settings.surround_start_wave = 0
	check(wave._surround_spawns(), "编辑资源不改变已开始的一局快照")
	configure()
	await second_wave(origin)
	var camera := wave.player.movement_camera
	camera.rotation.y += PI * 0.5
	finish_batch()
	check(positions == expected, "旋转相机不改变同一随机种子的世界进场位置")
	positions.clear()
	check(wave.queue_spawn(wave.enemies[0].definition, 3, 0.0, Vector3.INF, PackedStringArray(["EastNorth"]), 0.0, 0.0, 3), "多向模式仍接受外部明确指定入口的任务")
	finish_batch()
	var east: WaveSpawnZone = wave._spawn_zones.filter(func(item): return item.get_zone_id() == &"EastNorth")[0]
	check(positions.size() == 3 and positions_all_near(east.global_position, 3.3), "明确指定区域的外部任务不被多向规则覆盖")
	positions.clear()
	var local_point := origin + Vector3(4.8, 0, 0)
	check(wave.queue_spawn(wave.enemies[0].definition, 1, 0.0, local_point), "多向模式仍接受原地召唤")
	finish_batch()
	check(positions.size() == 1 and positions_all_near(local_point, 3.3), "原地召唤保留局部范围，不跳到其它方向")
	configure()
	await second_wave(origin)
	tick()
	var batch: Dictionary = wave._reserved_batch
	var points: PackedVector3Array = batch.front_points[int(batch.next_front)]
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in points:
		low = low.min(Vector2(point.x, point.z))
		high = high.max(Vector2(point.x, point.z))
	var blocked := Rect2(low - Vector2.ONE, high - low + Vector2.ONE * 2.0)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(blocked.size.x, 3, blocked.size.y)
	collision.shape = box
	wall.add_child(collision)
	world.add_child(wall)
	wall.global_position = Vector3(blocked.get_center().x, 1.5, blocked.get_center().y)
	await settle()
	positions.clear()
	finish_batch()
	check(wave._pending == 0 and positions.size() == 14, "一个方向被新墙阻挡时，其余合法方向仍能完成剩余成员")
	check(not Array(positions).any(func(point): return blocked.has_point(Vector2(point.x, point.z))), "多向进场仍实时检查新障碍，不生成在墙内")
	wall.queue_free()
	await settle()
	configure()
	var corner := wave.battle_area.position + Vector2.ONE
	var edge_origin := Vector3(corner.x, 0, corner.y)
	await second_wave(edge_origin)
	finish_batch()
	check(positions.size() == 16 and safe_positions(edge_origin), "人物靠近角落时退回可用方位，不为凑四向越界或贴脸")
	configure()
	await second_wave(origin)
	wave.spawn_safe_distance = 100.0
	tick()
	check(positions.is_empty() and wave._pending == 16 and wave.phase == WavePrototype.Phase.BATTLE, "所有方位暂时不安全时保留任务等待")
	wave.spawn_safe_distance = 5.0
	finish_batch()
	check(positions.size() == 16 and wave._pending == 0, "安全方位恢复后重新选择入口，不被空扇区缓存卡死")
	configure(24)
	await second_wave(origin)
	tick()
	check(wave._reserved_batch.front_points.size() == 2, "第二波小容量先双向夹入，保持每向的局部密度")
	finish_batch()
	check(positions.size() == 16 and angular_gap(origin) < PI * 1.1 and safe_positions(origin), "双向怪潮真实分布在人物两侧并完整入场")
	wave.retreat()
	check(wave.enemies.is_empty() and wave._spawn_queue.is_empty() and wave._reserved_batch.is_empty(), "撤退清理多向批次、缓存和预留")
	configure(64, false)
	wave.wave = 2
	check(not wave._surround_spawns(), "同一数量资源在有限模式中不启用无尽多向规则")
	check(FileAccess.get_sha256("res://data/world/world_terrain.tres") == terrain_hash, "多向刷新保留手绘地表存档")
	var invalid := WavePopulationRules.new()
	invalid.surround_max_fronts = 5
	check(not invalid.validation_error().is_empty(), "拒绝非法方向上限")
	invalid.surround_max_fronts = 4
	invalid.surround_start_wave = -1
	check(not invalid.validation_error().is_empty(), "拒绝负起始波")
	print(JSON.stringify({"checks":checks, "failures":failures}))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func positions_all_near(center: Vector3, radius: float) -> bool:
	for point in positions:
		if TerrainPath.horizontal_distance(point, center) > radius: return false
	return true
