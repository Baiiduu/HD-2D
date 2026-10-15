extends SceneTree

var checks := 0
var failures: Array[String] = []
var world: Node3D
var terrain: Terrain
var path := TerrainPath.new()

func _initialize() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ", message)

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func id(x: int, z: int) -> int:
	return path._id(Vector2i(x, z))

func length_of(route: PackedVector3Array) -> float:
	var result := 0.0
	for index in range(1, route.size()): result += route[index - 1].distance_to(route[index])
	return result

func rebuild() -> void:
	path.build(terrain, 0.14, [])

func wall(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = point + Vector3.UP * 0.5
	return body

func open_ground_checks() -> void:
	rebuild()
	check(path.graph.get_point_connections(id(4, 4)).size() == 8, "空地导航具有八方向连接")
	var from := path.grid_position(Vector2i(1, 1))
	var goal := path.grid_position(Vector2i(7, 7))
	var route := path.shared_pursuit_route(from, goal)
	check(is_equal_approx(length_of(route), from.distance_to(goal)), "斜对角追击沿斜线前进，不绕水平竖直阶梯")
	var builds := path.shared_field_builds
	for start in path.graph.get_point_ids():
		var point := path.graph.get_point_position(start)
		var actual := path.shared_pursuit_route(point, goal)
		var expected := path.graph.get_point_path(start, id(7, 7))
		check(absf(length_of(actual) - length_of(expected)) < 0.0001, "共享追击使用与原生 A* 一致的真实路程：%d" % start)
	check(path.shared_field_builds == builds, "所有怪物复用同一目标的追击距离场")
	# 更少节点不一定路程更短；验证共享追击不能继续使用等权广度树。
	var positions := {}
	for grid in [Vector2i(1, 1), Vector2i(1, 7), Vector2i(3, 3), Vector2i(5, 5), Vector2i(7, 7)]:
		positions[path._id(grid)] = path.grid_position(grid)
	rebuild()
	path.graph.clear()
	for point_id in positions: path.graph.add_point(point_id, positions[point_id])
	for edge in [[id(1, 1), id(1, 7)], [id(1, 7), id(7, 7)], [id(1, 1), id(3, 3)], [id(3, 3), id(5, 5)], [id(5, 5), id(7, 7)]]:
		path.graph.connect_points(edge[0], edge[1])
	check(is_equal_approx(length_of(path.shared_pursuit_route(from, goal)), from.distance_to(goal)), "混合边长按实际距离选择较短路线，不选节点更少的远路")

func corner_checks() -> void:
	terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, true)
	terrain.data.set_overlay(Vector2i(0, 1), TerrainData.OVERLAY_WATER, true)
	await settle()
	rebuild()
	check(not path.graph.are_points_connected(id(1, 1), id(2, 2)), "两侧水格不能从对角缝隙抄近路")
	check(not path.shared_reachable(path.grid_position(Vector2i(1, 1)), path.grid_position(Vector2i(2, 2))), "角接地面不伪造刷怪或残怪连通性")
	for cell in [Vector2i(1, 0), Vector2i(0, 1)]:
		terrain.data.set_level(cell, -1)
		terrain.data.set_overlay(cell, TerrainData.OVERLAY_BRIDGE, true)
	await settle()
	rebuild()
	check(path.graph.are_points_connected(id(1, 1), id(2, 2)), "同高桥面接通两侧后恢复安全斜向连接")
	for cell in [Vector2i(1, 0), Vector2i(0, 1)]:
		terrain.data.set_overlay(cell, TerrainData.OVERLAY_BRIDGE, false)
		terrain.data.set_overlay(cell, TerrainData.OVERLAY_WATER, false)
		terrain.data.set_level(cell, 1)
	await settle()
	rebuild()
	check(not path.graph.are_points_connected(id(1, 1), id(2, 2)), "断层两侧不支持对角跨越")
	for cell in [Vector2i(1, 0), Vector2i(0, 1)]: terrain.data.set_level(cell, 0)
	await settle()
	var first := wall(path.grid_position(Vector2i(2, 1)), Vector3(0.3, 1.0, 0.3))
	var second := wall(path.grid_position(Vector2i(1, 2)), Vector3(0.3, 1.0, 0.3))
	await settle()
	rebuild()
	check(path.graph.has_point(id(1, 1)) and path.graph.has_point(id(2, 2)), "夹角测试的两个端点本身可站立")
	check(not path.graph.are_points_connected(id(1, 1), id(2, 2)), "障碍夹角两侧被挡时不得斜穿")
	first.free()
	second.free()
	var thin := wall((path.grid_position(Vector2i(1, 1)) + path.grid_position(Vector2i(2, 2))) * 0.5, Vector3(0.1, 1.0, 0.1))
	await settle()
	rebuild()
	check(path.graph.are_points_connected(id(1, 1), id(2, 1)) and path.graph.are_points_connected(id(1, 2), id(2, 2)), "对角中段薄墙不阻挡外围水平通路")
	check(not path.graph.are_points_connected(id(1, 1), id(2, 2)), "斜线中段仍按身体半径检查薄墙")
	thin.free()
	await settle()
	rebuild()
	check(path.graph.are_points_connected(id(1, 1), id(2, 2)), "障碍移除重建后恢复对角通路")

func actual_movement_checks() -> void:
	var player := Player.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.position = path.grid_position(Vector2i(7, 7)) + Vector3.UP * 0.03
	for resource in ["wave_slime", "pot_brood"]:
		var definition: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % resource).duplicate()
		var actor := definition.scene.instantiate() as SlimeEnemy
		actor.configure_wave({"player":player,"terrain":terrain,"camera":null,"navigation":path,"attack_root":world,
			"damage_player":Callable(),"request_spawn":Callable()}, definition, 0.0)
		actor.position = path.grid_position(Vector2i(1, 1)) + Vector3.UP * 0.03
		actor.separation_radius = 0.0 # 单独验证路径，不让同伴避让影响方向与速度。
		world.add_child(actor)
		var diagonal_frames := 0
		var over_speed := false
		var before := actor.position
		for frame in 75:
			await physics_frame
			if absf(actor.velocity.x) > actor.move_speed * 0.25 and absf(actor.velocity.z) > actor.move_speed * 0.25: diagonal_frames += 1
			over_speed = over_speed or Vector2(actor.velocity.x, actor.velocity.z).length() > actor.effective_move_speed() + 0.001
		check(diagonal_frames > 60 and actor.position.x - before.x > 0.8 and actor.position.z - before.z > 0.8, "真实怪物持续斜向追击：" + resource)
		check(not over_speed, "斜走不产生根号二加速：" + resource)
		actor.free()

func run() -> void:
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i.ZERO, Vector2i(5, 5))
	world.add_child(terrain)
	root.add_child(world)
	current_scene = world
	await settle()
	open_ground_checks()
	await corner_checks()
	await actual_movement_checks()
	world.queue_free()
	await settle()
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
