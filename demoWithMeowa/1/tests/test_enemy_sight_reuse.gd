extends "res://tests/test_player_crowd_clearance.gd"

## Independent pre-optimization query: no cached ray or target exclusions.
func old_sight(actor: SlimeEnemy) -> bool:
	if not is_instance_valid(actor.target): return false
	if absf(actor.target.global_position.y - actor.global_position.y) > 1.6: return false
	var excluded: Array[RID] = [actor.get_rid()]
	if actor.target is CollisionObject3D: excluded.append(actor.target.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 0.5, actor.target.global_position + Vector3.UP * 0.7, 1, excluded)
	return actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func compare(actor: SlimeEnemy, expected: bool, label: String) -> void:
	check(old_sight(actor) == expected, "旧查询验证夹具条件：" + label)
	check(actor._can_see_target() == expected, "复用查询保留实时视线：" + label)

func settle() -> void:
	for frame in 3:
		await physics_frame
		await process_frame

func blocker(point: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.025, 2, 4)
	collision.shape = shape
	body.position = point
	body.add_child(collision)
	world.add_child(body)
	return body

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	player = Player.new()
	var visual := Sprite3D.new()
	visual.name = "Sprite"
	player.add_child(visual)
	capsule(player, 0.24, 1.06592)
	player.position = Vector3(2, 0, 0)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	# Deliberately put target and actor on the wall layer to check RID exclusions.
	player.collision_layer = 1
	target = player
	var plain := Node3D.new()
	plain.position = Vector3(4, 0, 0)
	world.add_child(plain)
	var wall := blocker(Vector3(20, 1, 0))
	for id in ["wave_slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog"]:
		var actor := resource_mob(id, Vector3.ZERO)
		actor.collision_layer = 1
		await settle()
		compare(actor, true, id + " 自身和当前身体目标均排除")
		wall.position.x = 1
		await settle()
		compare(actor, false, id + " 新移入的两厘米薄墙立即挡视线")
		wall.collision_layer = 2
		await settle()
		compare(actor, true, id + " 非墙碰撞层不挡视线")
		wall.collision_layer = 1
		wall.position.x = 20
		await settle()
		compare(actor, true, id + " 移走墙体立即恢复")
		actor.target = plain
		compare(actor, false, id + " 换成非身体目标后旧目标不再被排除")
		player.collision_layer = 2
		await settle()
		compare(actor, true, id + " 非身体目标不保留上次排除列表")
		plain.position.y = 2
		compare(actor, false, id + " 高差仍先排除")
		plain.position.y = 0
		actor.position = Vector3(0, 0, 0.4)
		compare(actor, true, id + " 下一次查询读取人物与怪物的新位置")
		actor.target = null
		compare(actor, false, id + " 目标清空后不查询旧目标")
		actor.target = player
		player.collision_layer = 1
		await settle()
		compare(actor, true, id + " 目标重新绑定后恢复正常")
		clear_mobs()
	var first := resource_mob("wave_slime", Vector3.ZERO)
	var second := resource_mob("pot_brood", Vector3(0, 0, 4))
	wall.position = Vector3(1, 1, 0)
	wall.get_child(0).shape.size = Vector3(0.025, 2, 0.3)
	await settle()
	compare(first, false, "第一只怪物被墙遮挡")
	compare(second, true, "第二只怪物独立射线不沿用第一只的起点")
	compare(first, false, "交替查询不串用其它怪物的参数")
	clear_mobs()
	world.queue_free()
	await settle()
	print("Enemy sight reuse: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
