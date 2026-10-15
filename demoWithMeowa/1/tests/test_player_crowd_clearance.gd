extends "res://tests/test_enemy_crowd.gd"

class FlatCollision extends ProjectileCollision:
	# 夹具是无限平地，仍保留实际身体碰撞；此处无需 Terrain 网格。
	func ground_limit(_path: TerrainPath, _start: Vector3, _direction: Vector3, distance: float, _plane_height: float, _tolerance: float) -> float:
		return distance

var player: Player
var contact_hits := 0

func resource_mob(id: String, point: Vector3) -> SlimeEnemy:
	var data: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % id)
	var enemy := data.scene.instantiate() as SlimeEnemy
	enemy.configure_wave({"player": player, "terrain": null, "camera": null,
		"navigation": path, "attack_root": null, "spatial_index": index,
		"damage_player": func(amount):
			contact_hits += 1
			player.current_health -= amount,
		"can_damage_player": func(_amount): return contact_hits == 0,
		"request_spawn": Callable()}, data, 0.0)
	enemy.position = point
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemies.append(enemy)
	index.update(enemy)
	return enemy

func movement_checks() -> void:
	for id in ["wave_slime", "pot_brood", "mini_slime"]:
		contact_hits = 0
		player.current_health = player.max_health
		player.crowd_clearance_distance = 0.12
		var actor := resource_mob(id, Vector3(0, 0.02, 2))
		actor.separation_strength = 0.0
		await step(100)
		var distance := TerrainPath.horizontal_distance(actor.global_position, player.global_position)
		check(absf(distance - actor.combat_stop_distance - 0.12) < 0.015, id + " 实际停靠增加 0.12 米")
		check(contact_hits == 1 and player.current_health < player.max_health, id + " 留白边缘仍能接触伤害并遵守受击资格")
		player.crowd_clearance_distance = 1.0
		await step(60)
		distance = TerrainPath.horizontal_distance(actor.global_position, player.global_position)
		check(absf(distance - actor.contact_distance + 0.05) < 0.015, id + " 大数值限制在接触范围内，现有怪物实时让位")
		player.crowd_clearance_distance = 0.0
		await step(60)
		distance = TerrainPath.horizontal_distance(actor.global_position, player.global_position)
		var original_stop := maxf(actor.combat_stop_distance, actor.body_radius + 0.24)
		check(absf(distance - original_stop) < 0.035, id + " 关闭后恢复原停靠距离，保留实体碰撞")
		clear_mobs()

func pressure_checks() -> void:
	player.crowd_clearance_distance = 0.12
	var front := mob(Vector3(0, 0.02, 0.77))
	mob(Vector3(0, 0.02, 1.35))
	var pressure := front._crowd_direction(Vector3.ZERO)
	check(pressure.z < 0.0, "后排在前排身后产生真实向内挤压")
	var motion := front._personal_space_direction(pressure, front._personal_stop_distance(front.combat_stop_distance))
	check(motion.z >= -0.00001, "停靠边缘消除向内挤压，仍保留切向让位")
	front.position = Vector3.ZERO
	check(front._personal_space_direction(Vector3.ZERO, 0.77).is_finite(), "与人物同点时让位方向保持有限")
	player.crowd_clearance_distance = 0.0
	check(front._personal_space_direction(pressure, 0.65) == pressure and front._personal_stop_distance(0.65) == 0.65, "0 完整关闭额外留白和挤压限制")
	player.crowd_clearance_distance = 0.12
	check(is_equal_approx(front._personal_stop_distance(0.9), 1.02), "范围外停靠的冲锋和远程接近不被拉入接触范围")
	clear_mobs()

	for row in 8:
		for column in 16: mob(Vector3((column - 7.5) * 0.85, 0.02, 3 + row * 0.85))
	await step(480)
	var nearest := INF
	for actor in enemies:
		nearest = minf(nearest, TerrainPath.horizontal_distance(actor.global_position, player.global_position))
	check(nearest >= 0.755, "128 只实际围聚，后排持续挤压仍留住 0.77 米停靠边缘")
	check(density().median > 0.6 and density().mean_target < 5.0, "留白保留可辨认且紧凑的人海")
	print("Personal clearance crowd: nearest=", nearest, " density=", density())
	# 给绕行中的后排完成站位，再检查静止围聚时的朝向。
	await step(120)
	await facing_checks()
	player.position.z = -3.0
	var before: float = density().mean_target
	await step(180)
	check(density().mean_target < before - 0.5, "移动人物后怪群继续追击，留白随人物移动")
	check(enemies.all(func(actor): return TerrainPath.horizontal_distance(actor.global_position, player.global_position) >= 0.755), "人物移动后新的停靠边缘仍成立")
	clear_mobs()

func special_motion_checks() -> void:
	player.position = Vector3.ZERO
	player.crowd_clearance_distance = 1.0
	var actor := resource_mob("leaf_charger", Vector3(0, 0.02, 1)) as LeafChargerEnemy
	actor._surface_collision = FlatCollision.new()
	actor._charge_plane = 0.0
	actor._charge_direction = Vector3.FORWARD
	actor.attack_phase = LeafChargerEnemy.AttackPhase.CHARGE
	await physics_frame
	actor._advance_charge(1.0 / 60.0)
	check(actor.position.z < 1.0, "锁线冲锋可进入留白，不变成抵挡招式的屏障")
	clear_mobs()
	actor = resource_mob("leaf_charger", Vector3(0, 0.02, 0.7)) as LeafChargerEnemy
	await physics_frame
	actor._idle_motion(1.0 / 60.0)
	check(absf(actor.position.z - 0.7) < 0.0001, "招式预告和恢复仍原地停留，不受留白让位影响")
	check(actor.apply_push_impulse(Vector3.FORWARD, 2.0, 0.2), "留白范围内仍接受原有拨怪外力")
	actor._push_collision = FlatCollision.new()
	actor._advance_push(1.0 / 60.0)
	check(actor.position.z < 0.7, "拨怪可沿既定方向穿过留白范围")
	clear_mobs()

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
	await movement_checks()
	await pressure_checks()
	await special_motion_checks()
	world.queue_free()
	for frame in 3: await process_frame
	print("Player crowd clearance: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
