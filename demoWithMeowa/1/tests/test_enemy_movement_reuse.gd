extends "res://tests/test_player_crowd_clearance.gd"

## 保留旧方程作同一怪物、同一索引顺序的 oracle；夹具同时最多三只怪物。
class SpeedProbe extends CreatureEnemy:
	var speed_reads := 0
	func effective_move_speed() -> float:
		speed_reads += 1
		return super.effective_move_speed()

func old_space(actor: SlimeEnemy, direction: Vector3, stop: float) -> Vector3:
	if not actor.target is Player or (actor.target as Player).crowd_clearance_distance <= 0.0: return direction
	var away := actor.global_position - actor.target.global_position
	away.y = 0.0
	var distance := away.length()
	away = away / distance if distance > 0.00001 else -actor._look.normalized()
	var required := clampf((stop - distance) / (maxf(actor.effective_move_speed(), 0.01) * 0.12), -1.0, 1.0)
	var radial := direction.dot(away)
	if radial < required: direction += away * (required - radial)
	return direction.limit_length(1.0)

func old_pursuit(actor: SlimeEnemy, desired: Vector3) -> Vector3:
	var direction := actor._crowd_direction(desired)
	if desired.is_zero_approx() or actor.pursuit_flank_strength <= 0.0 or actor.separation_strength <= 0.0: return direction
	var pressure := clampf(1.0 - direction.dot(desired), 0.0, 1.0)
	if pressure < 0.35:
		actor._yield_side = 0.0
		return direction
	var spacing := maxf(actor.separation_radius, actor.body_radius * 2.1)
	var approach := smoothstep(actor.combat_stop_distance + spacing * 0.3, actor.combat_stop_distance + spacing * 1.5, TerrainPath.horizontal_distance(actor.global_position, actor.target.global_position))
	var amount := actor.pursuit_flank_strength * pressure * approach
	if amount < 0.02:
		actor._yield_side = 0.0
		return direction
	var side := Vector3.UP.cross(desired)
	if actor._yield_side == 0.0:
		var lateral := direction.dot(side)
		actor._yield_side = signf(lateral) if absf(lateral) > 0.08 else (1.0 if hash(actor.get_instance_id()) % 2 == 0 else -1.0)
	for choice in [actor._yield_side, -actor._yield_side]:
		var candidate: Vector3 = (direction + side * choice * amount).limit_length(1.0)
		var next := actor.global_position + candidate * maxf(0.35, actor.body_radius)
		if actor.navigation.data and not actor.navigation.can_walk_direct(actor.global_position, actor.navigation.ground_position(next)): continue
		actor._yield_side = choice
		return candidate
	return direction

func helper_checks() -> void:
	var actor := mob(Vector3.ZERO)
	var front := mob(Vector3(0, 0.02, -0.7))
	var side := mob(Vector3(0.4, 0.02, 0.5))
	var points := [Vector3.ZERO, Vector3(0.000001, 0.02, 0), Vector3(0, 0.02, 0.77), Vector3(0, 0.02, 4.8), Vector3(-3.1234567, 0.17, 4.765432), Vector3(0.235711, 0.02, -0.6180339)]
	var directions := [Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT, Vector3(0.3, 0, 0.4)]
	for clearance in [0.0, 0.12, 1.0]:
		player.crowd_clearance_distance = clearance
		for point: Vector3 in points:
			actor.position = point
			front.position = point + Vector3(0, 0, -0.7)
			side.position = point + Vector3(0.4, 0, 0.5)
			for other in enemies: index.update(other)
			var distance := TerrainPath.horizontal_distance(point, player.global_position)
			var away := point - player.global_position
			away.y = 0.0
			for direction: Vector3 in directions:
				var stop := actor._personal_stop_distance(actor.combat_stop_distance)
				var expected := old_space(actor, direction, stop)
				check(actor._personal_space_direction(direction, stop) == expected, "独立留白 helper 实时读取且与旧方程逐位一致")
				check(actor._personal_space_direction(direction, stop, away, distance, actor.effective_move_speed()) == expected, "复用 XZ 距离和移速仍与旧留白方程逐位一致")
				for initial_side in [-1.0, 0.0, 1.0]:
					actor._yield_side = initial_side
					var expected_pursuit := old_pursuit(actor, direction)
					var expected_side := actor._yield_side
					actor._yield_side = initial_side
					check(actor._pursuit_crowd_direction(direction) == expected_pursuit and actor._yield_side == expected_side, "独立侧让 helper 保留方向与选边状态")
					actor._yield_side = initial_side
					check(actor._pursuit_crowd_direction(direction, point, distance) == expected_pursuit and actor._yield_side == expected_side, "复用起点和距离仍保留全部邻居与选边状态")
	clear_mobs()
	# 旧一参 _crowd_direction override 仍由侧让正常调用。
	var legacy := mob(Vector3(0, 0.02, 3), true)
	check(legacy._pursuit_crowd_direction(Vector3.FORWARD).is_finite(), "LegacySlime 一参 override 兼容")
	clear_mobs()

func speed_probe() -> SpeedProbe:
	var actor := SpeedProbe.new()
	actor.wave_mode = true
	actor.target = player
	actor.navigation = path
	actor._path = path
	actor.spatial_index = index
	actor.spawn_delay = 0
	actor.separation_strength = 0.0
	actor.attack_damage = 0.0
	actor.position = Vector3(4, 0.02, 4)
	var visual := Sprite3D.new()
	visual.name = "Sprite"
	actor.add_child(visual)
	capsule(actor, 0.28, 0.7)
	actor._surface_collision = FlatCollision.new()
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	enemies.append(actor)
	index.update(actor)
	return actor

func live_input_checks() -> void:
	player.position = Vector3.ZERO
	player.crowd_clearance_distance = 0.12
	var actor := speed_probe()
	var source := WaveEnemy.new()
	actor.add_speed_boost(source, 1.5, 1.0)
	await physics_frame
	actor.speed_reads = 0
	actor._move_chase(1.0 / 60.0, 0.65)
	check(actor.speed_reads == 1, "一次追击的留白与实际移动只读取一次有效移速")
	check(is_equal_approx(Vector2(actor.velocity.x, actor.velocity.z).length(), actor.move_speed * 1.5), "追击使用当前鼓舞速度")
	source.dead = true
	player.position = Vector3(6, 0, 6)
	actor.position = Vector3(3, 0.02, 3)
	actor._route_clock = 0.0
	actor.speed_reads = 0
	actor._move_chase(1.0 / 60.0, 0.65)
	check(actor.speed_reads == 1 and actor.velocity.x > 0.0 and actor.velocity.z > 0.0, "下一次移动即时读取新位置、新目标和已死亡鼓舞来源")
	check(is_equal_approx(Vector2(actor.velocity.x, actor.velocity.z).length(), actor.move_speed), "来源死亡不延迟恢复基础移速")
	actor.move_speed = 2.125
	actor.speed_reads = 0
	actor._move_local(Vector3.RIGHT, 1.0 / 60.0)
	check(actor.speed_reads == 1 and is_equal_approx(actor.velocity.x, 2.125), "local 长度与实际移动复用同一次最新移速")
	player.crowd_clearance_distance = 0.0
	actor.speed_reads = 0
	actor._personal_space_direction(Vector3.RIGHT, 0.65)
	check(actor.speed_reads == 0, "关闭留白的独立 helper 不额外查询移速")
	actor.target = null
	actor.speed_reads = 0
	actor._move_local(Vector3.RIGHT, 1.0 / 60.0)
	check(actor.speed_reads == 1 and actor.position.is_finite(), "独立 local 保留无人物目标时的原有兼容行为")
	clear_mobs()
	source.free()

func contact_callback_checks() -> void:
	player.position = Vector3.ZERO
	player.crowd_clearance_distance = 0.12
	var actor := mob(Vector3(0, 0.02, 0.7))
	actor.separation_strength = 0.0
	actor.attack_damage = 1.0
	var high_target := Node3D.new()
	world.add_child(high_target)
	high_target.position = Vector3(0, 3, 0)
	var calls := [0, 0]
	actor.can_damage_player = func(_amount):
		calls[0] += 1
		actor.target = high_target
		return true
	actor.damage_player = func(_amount): calls[1] += 1
	await physics_frame
	actor._combat_tick(1.0 / 60.0)
	check(calls == [1, 0] and actor.target == high_target, "移动后的接触资格回调更换目标后，遮挡／高差继续读取最新目标")
	clear_mobs()
	high_target.free()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	collision.shape = box
	collision.position.y = -0.1
	floor_body.add_child(collision)
	world.add_child(floor_body)
	player = Player.new()
	var visual := Sprite3D.new()
	visual.name = "Sprite"
	player.add_child(visual)
	capsule(player, 0.24, 1.06592)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	target = player
	helper_checks()
	await live_input_checks()
	await contact_callback_checks()
	# 父夹具此分支每次仅一只：真实胶囊停靠、动态参数与接触伤害。
	await movement_checks()
	await special_motion_checks()
	world.queue_free()
	for frame in 3: await process_frame
	print("Enemy movement reuse: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
