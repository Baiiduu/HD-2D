extends "res://tests/test_diagonal_navigation.gd"

var player: Player
var actors: Array[SlimeEnemy] = []
var spatial := WaveEnemySpatialIndex.new()

func rebuild() -> void:
	path.build(terrain, 0.32, [])

func mob(point: Vector3, legacy := false) -> SlimeEnemy:
	var definition: WaveMeleeEnemyDefinition = load("res://data/enemies/wave_slime.tres").duplicate()
	definition.attack_damage = 0
	var actor := definition.scene.instantiate() as SlimeEnemy
	actor.configure_wave({"player":player,"terrain":terrain,"camera":null,"navigation":path,"attack_root":world,
		"damage_player":func(_amount): return false,"can_damage_player":func(_amount): return false,
		"request_spawn":Callable(),"spatial_index":spatial}, definition, 0)
	actor.position = point + Vector3.UP * 0.02
	if legacy:
		actor.pursuit_lookahead = 0
		actor.pursuit_flank_strength = 0
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	actors.append(actor)
	spatial.update(actor)
	return actor

func clear_actors() -> void:
	for actor in actors: actor.free()
	actors.clear()
	spatial.clear()

func smoothing_checks() -> void:
	var goal := Vector3.ZERO
	var old_error := 0.0
	for from: Vector3 in [Vector3(-3.3, 0.02, 4.9),Vector3(-1.7, 0.02, 5.5),Vector3(0.2, 0.02, 5.4),Vector3(1.4, 0.02, 5.1),Vector3(3.1, 0.02, 4.8)]:
		var before := path.shared_pursuit_route(from, goal)
		var after := path.chase_route(from, goal)
		var straight := (goal - from).normalized()
		old_error += rad_to_deg((before[1] - from).normalized().angle_to(straight))
		check(after.size() == 2 and (after[1] - from).normalized().dot(straight) > 0.9999, "空地按每只怪物自身方位直追，不汇向同一格心")
		check(path.chase_route(from, goal, 0) == before, "前视为零保留原网格路线，供对照与调节")
	print("Open-ground baseline angle error: ", old_error / 5.0)
	var building := wall(Vector3(0,0,3.2), Vector3(3,2,1.6))
	await settle()
	rebuild()
	var from := Vector3(0, 0.02, 6)
	var route := path.chase_route(from, goal)
	check(not path.can_walk_direct(from, goal) and route.size() > 2, "建筑挡住时仍绕行，不直穿建筑")
	check(path.can_walk_direct(from, route[1]), "绕障前视选取的第一个拐角具有实际身体留空")
	for index in range(1, route.size()): check(path._segment_clear(route[index - 1], route[index]), "平滑后的各段不切墙")
	building.free()
	await settle()
	rebuild()
	var thin := wall(Vector3(0,0,2), Vector3(0.1,2,1))
	await settle()
	check(not path.can_walk_direct(Vector3(0,0.02,4), goal), "导航建立后出现的薄墙实时阻止直追捷径")
	thin.free()
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, true)
	await settle()
	rebuild()
	check(not path.can_walk_direct(Vector3(-4,0.02,-4), Vector3(4,0,4)), "中心与两侧地表检查不让捷径跨水")
	check(not path.can_walk_direct(Vector3(-4,0.02,1.05), Vector3(4,0,1.05)), "身体边缘擦过水格也不使用直追捷径")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, false)
	await settle()
	rebuild()

func yielding_checks() -> void:
	var back := mob(Vector3(0,0,4.8))
	mob(Vector3(0,0,4))
	var desired := Vector3.FORWARD
	var previous := back._crowd_direction(desired)
	var current := back._pursuit_crowd_direction(desired)
	check(absf(previous.x) < 0.0001 and absf(current.x) > 0.03, "同线受阻的后排会主动从侧边让行")
	check(current.length() <= 1.0 and current.dot(desired) >= previous.dot(desired) - 0.001, "侧移保留受阻减速，不额外加速或强行后撤")
	var sign := signf(current.x)
	var stable := true
	for frame in 60: stable = stable and signf(back._pursuit_crowd_direction(desired).x) == sign
	check(stable, "拥堵期间保持选定侧向，不逐帧随机摆动")
	back._yield_side = 1
	var obstacle := wall(Vector3(-0.48,0,4.8), Vector3(0.2,2,1.4))
	await settle()
	check(back._pursuit_crowd_direction(desired).x > 0.0, "一侧墙体受阻时选另一侧，而不是向墙内让行")
	obstacle.free()
	back.pursuit_flank_strength = 0
	check(back._pursuit_crowd_direction(desired) == back._crowd_direction(desired), "侧向强度为零恢复原有聚群避让")
	clear_actors()
	back = mob(Vector3(0,0,0.75))
	mob(Vector3(0,0,0.01))
	check(back._pursuit_crowd_direction(desired) == back._crowd_direction(desired), "近身逐渐取消侧移，不形成绕玩家旋转的空心圈")
	check(back._pursuit_crowd_direction(Vector3.ZERO) == back._crowd_direction(Vector3.ZERO), "停止追击时只保留原有间距整理")
	clear_actors()

func simulate(legacy: bool) -> Dictionary:
	for row in 12:
		for column in 8: mob(Vector3((column - 3.5) * 0.75, 0, 4 + row * 0.75), legacy)
	var entries := {}
	var buckets := {}
	var finite := true
	for frame in 480:
		await physics_frame
		for actor in actors:
			actor._combat_tick(1.0 / 60.0)
			spatial.update(actor)
			finite = finite and actor.global_position.is_finite() and actor.velocity.is_finite()
			if not entries.has(actor) and TerrainPath.horizontal_distance(actor.position, player.position) <= 4.0:
				var bucket := roundi(rad_to_deg(atan2(actor.position.x, actor.position.z)) / 10.0)
				entries[actor] = bucket
				buckets[bucket] = int(buckets.get(bucket, 0)) + 1
	var mean := 0.0
	var nearest: Array[float] = []
	for actor in actors:
		mean += TerrainPath.horizontal_distance(actor.position, player.position)
		var closest := INF
		for other in actors:
			if actor != other: closest = minf(closest, TerrainPath.horizontal_distance(actor.position, other.position))
		nearest.append(closest)
	nearest.sort()
	var peak := 0
	for count in buckets.values(): peak = maxi(peak, count)
	var result := {"mean_target":mean / actors.size(),"median_spacing":nearest[nearest.size() / 2],"arrival_sectors":buckets.size(),"largest_sector":peak,"arrived":entries.size()}
	check(finite, "96 只真实怪物追击保持有限位置和速度")
	print("Natural pursuit legacy=", legacy, " ", result)
	clear_actors()
	return result

func run() -> void:
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-10,-10), Vector2i(21,21))
	world.add_child(terrain)
	root.add_child(world)
	current_scene = world
	player = Player.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	await settle()
	rebuild()
	await smoothing_checks()
	await yielding_checks()
	var legacy := await simulate(true)
	var current := await simulate(false)
	# 新路线有更多怪物及时到达，比较占比而非不同到达总数下的绝对个数。
	check(current.arrival_sectors > legacy.arrival_sectors and float(current.largest_sector) / current.arrived < float(legacy.largest_sector) / legacy.arrived * 0.97, "前排从更多方位靠拢，减少同一方向的扎堆")
	check(current.mean_target < 4.0 and current.median_spacing > 0.55 and current.median_spacing < 1.05, "保持紧凑怪潮与身体层次，不把怪群推成宽松大圆")
	check(current.arrived >= legacy.arrived - 5, "侧向让行不拖慢整片怪潮推进")
	world.queue_free()
	await settle()
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
