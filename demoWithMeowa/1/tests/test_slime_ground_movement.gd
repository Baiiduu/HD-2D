extends "res://tests/test_natural_pursuit.gd"

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func reset_actor(actor: SlimeEnemy, point: Vector3, enabled: bool) -> void:
	actor.global_position = point
	actor.velocity = Vector3.ZERO
	actor.ground_movement_enabled = enabled
	actor._route.clear()
	actor._route_clock = 0.0
	actor._waypoint = 0
	actor._yield_side = 1.0
	actor._push_remaining = 0.0
	actor._ground_moved = false
	spatial.update(actor)

func motion(actor: SlimeEnemy, heading: Vector3, speed := 1.7) -> void:
	actor.velocity = heading * speed
	actor._move_combat_body(1.0 / 60.0)
	spatial.update(actor)

func movement_checks() -> void:
	var actor := mob(Vector3(-3,0,0))
	reset_actor(actor, Vector3(-3,0.001,0), true)
	motion(actor, Vector3.RIGHT)
	check(actor._ground_moved and absf(actor.position.x + 3.0 - 1.7 / 60.0) < 0.0001, "平地使用专用移动，保留实际速度")
	check(absf(actor._ground_real_velocity.x - 1.7) < 0.0001, "朝向读取本次真实移动速度")
	actor.ground_movement_enabled = false
	motion(actor, Vector3.RIGHT)
	check(not actor._ground_moved, "开关关闭立即恢复旧移动")
	actor.ground_movement_enabled = true
	reset_actor(actor, Vector3(-3,0.02,0), true)
	actor.velocity = Vector3(1.7,-actor.gravity/60.0,0)
	actor._move_combat_body(1.0/60.0)
	check(not actor._ground_moved and actor.position.y < 0.02, "出生／拨动偏移先自然落地，专用移动不保留悬空高度")
	var obstacle := wall(Vector3.ZERO, Vector3(0.04,2,5))
	await settle()
	reset_actor(actor, Vector3(-2,0.001,0), true)
	motion(actor, Vector3.RIGHT, 300.0)
	check(actor.position.x < -0.29 and actor.position.x > -0.32, "高速扫掠不穿过薄墙，使用原胶囊半径")
	var start := actor.position
	for step in 60:
		await physics_frame
		motion(actor, Vector3(1,0,1).normalized())
	check(actor.position.z > start.z + 1.1 and actor.position.x < -0.29, "贴墙斜向运动保留切向滑动，不粘墙")
	for step in 30:
		await physics_frame
		motion(actor, Vector3.LEFT)
	check(actor.position.x < start.x - 0.8, "墙边反向后立即脱离")
	obstacle.position.x = -2.0
	await settle()
	reset_actor(actor, Vector3(-3,0.001,0), true)
	motion(actor, Vector3.RIGHT, 120.0)
	check(actor.position.x < -2.29, "已经建立导航后移动的墙体实时阻挡")
	var capsule: CapsuleShape3D = actor.get_node("Collision").shape
	capsule.radius = 0.4
	capsule.height = 0.8
	actor.get_node("Collision").position.y = 0.4
	actor.body_radius = 0.4
	reset_actor(actor, Vector3(-3,0.001,0), true)
	motion(actor, Vector3.RIGHT, 120.0)
	check(actor.position.x < -2.41 and actor.position.x > -2.44, "更大史莱姆沿用真实胶囊，不缩小碰撞来提速")
	capsule.radius = 0.28
	capsule.height = 0.7
	actor.get_node("Collision").position.y = 0.35
	actor.body_radius = 0.28
	reset_actor(actor, Vector3(-2,0.001,0), true)
	motion(actor, Vector3.ZERO)
	check(absf(actor.position.x + 2.0) > 0.1, "动态墙覆盖静止怪物时仍执行原生脱离重叠")
	obstacle.free()
	await settle()
	var first := wall(Vector3(0,0,0), Vector3(0.1,2,4))
	var second := wall(Vector3(-1,0,2), Vector3(2,2,0.1))
	await settle()
	reset_actor(actor, Vector3(-0.5,0.001,1.5), true)
	for step in 40:
		await physics_frame
		motion(actor, Vector3(1,0,1).normalized())
	check(actor.position.x < -0.32 and actor.position.z < 1.68, "内墙角多次滑动不切角或穿墙")
	var corner := actor.position
	for step in 30:
		await physics_frame
		motion(actor, Vector3(-1,0,-1).normalized())
	check(actor.position.distance_to(corner) > 0.8, "内墙角改向可以脱离")
	first.free()
	second.free()
	await settle()
	reset_actor(actor, Vector3(0,1.5,0), true)
	motion(actor, Vector3.RIGHT)
	check(not actor._ground_moved, "屋顶或悬空不吸附地面，保留旧求解器")
	reset_actor(actor, Vector3(0,0.001,0), true)
	actor.velocity = Vector3(1,4,0)
	actor._move_combat_body(1.0 / 60.0)
	check(not actor._ground_moved and actor.position.y > 0.001, "向上运动使用原重力流程")
	reset_actor(actor, Vector3(0,0.001,0), true)
	actor._push_remaining = 0.3
	motion(actor, Vector3.RIGHT)
	check(not actor._ground_moved, "外力拨动不进入地面专用移动")
	actor._push_remaining = 0.0
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, true)
	await settle()
	reset_actor(actor, Vector3(0,0.001,0), true)
	motion(actor, Vector3.RIGHT)
	check(not actor._ground_moved, "地表编辑立即使平地资格失效")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, false)
	await settle()
	reset_actor(actor, Vector3(0,0.001,0), true)
	motion(actor, Vector3.RIGHT)
	check(actor._ground_moved, "恢复平地后重新取得资格")
	terrain.data.set_level(Vector2i.ZERO, 1)
	check(is_nan(path.flat_ground_height(Vector3.ZERO, Vector3.RIGHT)), "同帧高度编辑立即撤销平地证明，不等导航重建")
	terrain.data.set_level(Vector2i.ZERO, 0)
	await settle()
	reset_actor(actor, Vector3(0,0.001,0), true)
	actor.combat_active = func(): return false
	var frozen := actor.position
	actor._physics_process(1.0 / 60.0)
	check(actor.position == frozen, "升级冻结时不绕过原战斗资格检查")
	actor.combat_active = Callable()
	actor.apply_stun(0.3)
	actor._physics_process(1.0 / 60.0)
	check(not actor._ground_moved and actor.velocity.x == 0.0 and actor.velocity.z == 0.0, "眩晕沿用旧物理和停步规则")
	var special := CreatureEnemy.new()
	check(special._supports_ground_movement(), "其他怪物的普通追击可复用平地移动，特殊招式另走原流程")
	special.free()
	clear_actors()
	var barrier := wall(Vector3.ZERO, Vector3(0.1,2,4))
	await settle()
	rebuild()
	player.position = Vector3(3,0,0)
	actor = mob(Vector3(-3,0,0))
	actor.ground_movement_enabled = true
	for step in 420:
		await physics_frame
		actor._physics_process(1.0 / 60.0)
	check(actor.position.x > 2.0 and TerrainPath.horizontal_distance(actor.position, player.position) < 0.9, "真实追击绕过整面墙并到达目标，不在墙角反复停滞")
	clear_actors()
	barrier.free()
	await settle()
	rebuild()
	player.position = Vector3.ZERO

func crowd_sample(count: int, enabled: bool, steps := 360) -> Dictionary:
	if actors.is_empty():
		for index in count: mob(Vector3.ZERO)
	player.position = Vector3.ZERO
	for index in count:
		var actor := actors[index]
		reset_actor(actor, Vector3((index % 16 - 7.5) * 0.7, 0.001, 3.0 + (index / 16) * 0.7), enabled)
		actor._yield_side = 1.0
	var times: Array[float] = []
	var movers := 0
	for step in steps:
		await physics_frame
		player.position = Vector3(sin(step / 90.0) * 1.5, 0, 0) if step >= steps / 2 else Vector3.ZERO
		var stamp := Time.get_ticks_usec()
		for actor in actors:
			actor._physics_process(1.0 / 60.0)
			if actor._ground_moved: movers += 1
		times.append((Time.get_ticks_usec() - stamp) / 1000.0)
	var distance := 0.0
	var nearest: Array[float] = []
	var finite := true
	for actor in actors:
		finite = finite and actor.position.is_finite() and actor.velocity.is_finite()
		distance += TerrainPath.horizontal_distance(actor.position, player.position)
		var closest := INF
		for other in actors:
			if actor != other: closest = minf(closest, TerrainPath.horizontal_distance(actor.position, other.position))
		nearest.append(closest)
	times.sort()
	nearest.sort()
	var sum := 0.0
	for value in times: sum += value
	var report := {"count":count,"ground":enabled,"step_mean_ms":sum/times.size(),"step_p95_ms":times[int(times.size()*0.95)],"median_spacing":nearest[nearest.size()/2],"mean_distance":distance/count,"ground_steps":movers,"total_steps":count*steps}
	check(finite, "%d 只怪物运动数值稳定" % count)
	check(report.median_spacing > 0.55 and report.median_spacing < 0.95, "%d 只保留密集肩宽和个体层次" % count)
	print("CROWD ", JSON.stringify(report))
	return report

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
	await movement_checks()
	if not "--quick" in OS.get_cmdline_user_args():
		for count in [128,160]:
			var baseline: Dictionary
			for enabled in [false,true,true,false]:
				var result := await crowd_sample(count, enabled)
				if baseline.is_empty(): baseline = result
				check(absf(baseline.median_spacing - result.median_spacing) < 0.035 and absf(baseline.mean_distance - result.mean_distance) < 0.12, "新旧 %d 只怪群密度和到达距离相当" % count)
			clear_actors()
	world.queue_free()
	await settle()
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
