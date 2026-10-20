extends "res://tests/test_aim_path_preview.gd"

## 隔离画面与天气初始化，直接验证正式地图使用的边界碰撞生成函数。
class BoundaryEffects extends MapEffects:
	func _enter_tree() -> void:
		pass
	func _ready() -> void:
		pass

var effects: BoundaryEffects

func path_checks() -> void:
	effects = BoundaryEffects.new()
	world.add_child(effects)
	player.bounds = Rect2(-2, -2, 4, 4)
	effects._update_boundary_collision(player.bounds, 0.0)
	await settle()
	var boundary := effects._boundary
	check(boundary.collision_layer == 1 and boundary.collision_mask == 0,
		"空气墙使用现有墙体碰撞层，不依赖额外弹射查询")
	check(boundary.is_in_group(&"map_boundaries"), "地图空气墙独立标记，供纯视觉死亡抛飞忽略")
	check(boundary.get_child_count() == 4 and not terrain.is_ancestor_of(boundary),
		"四面独立碰撞形状不被误认成水面或断层")
	var shapes: Array[Shape3D] = []
	for child in boundary.get_children(): shapes.append((child as CollisionShape3D).shape)
	effects._update_boundary_collision(player.bounds, 0.0)
	check(effects._boundary == boundary and boundary.get_child_count() == 4,
		"重复连接不创建新墙体或重复形状")
	for index in 4:
		check((boundary.get_child(index) as CollisionShape3D).shape == shapes[index], "重复更新复用原碰撞形状")
	var surfaces: Array[Object] = []
	body.surface_bounced.connect(func(hit): surfaces.append(hit.get_collider()))
	for heading in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK,
			Vector3(1, 0, 0.35).normalized(), Vector3(1, 0, 1).normalized()]:
		surfaces.clear()
		var route := await predict(heading, 16, 100.0)
		check(not route.contacts.is_empty() and route.segments.size() > 1,
			"四边、斜入和角落均显示真实反弹：%s" % heading)
		check(body.release_charge(), "边缘反弹测试发射")
		var inside := true
		for frame in 600:
			if not body.flying: break
			body.advance(1.0 / 60.0, Vector3.ZERO, false)
			var point := Vector2(player.global_position.x, player.global_position.z)
			inside = inside and player.bounds.grow(0.001).has_point(point)
		check(body.bounce_count > 0 and inside, "真实弹射在活动边缘反弹且不越界")
		check(not surfaces.is_empty() and surfaces.all(func(collider): return collider == boundary),
			"空气墙发出原有实体碰撞反馈，供声音与镜头复用")
		check(TerrainPath.horizontal_distance(player.global_position, route.segments.back().end) < 0.06,
			"边缘反弹后的实飞终点与预览一致")
	var settings := player.ricochet_rules
	settings.minimum_launch_speed = 40.0
	settings.maximum_launch_speed = 40.0
	settings.flight_deceleration = 0.25
	settings.bounce_speed_cost = 0.0
	await predict(Vector3.RIGHT, 32, 100.0)
	check(body.release_charge(), "大步长连续反弹发射")
	body.advance(0.8, Vector3.ZERO, false)
	check(body.flying and body.bounce_count >= 8 and absf(player.global_position.x) < 2.0,
		"高速大步长由真实胶囊连续扫掠，不穿过空气墙")
	body.cancel(true)
	settings.minimum_launch_speed = 8.0
	settings.maximum_launch_speed = 8.0
	settings.flight_deceleration = 2.5
	settings.bounce_speed_cost = 0.5
	player.bounds = Rect2(-3, -2, 6, 4)
	effects._update_boundary_collision(player.bounds, 0.0)
	await settle()
	check(effects._boundary == boundary and boundary.get_child_count() == 4,
		"活动范围变化时复用原墙体")
	for index in 4:
		check((boundary.get_child(index) as CollisionShape3D).shape == shapes[index], "范围变化复用原形状")
	var resized := await predict(Vector3.RIGHT, 16, 100.0)
	check(not resized.contacts.is_empty() and resized.contacts[0].x > 2.7,
		"修改活动范围后使用新的边界位置")
	# 地图边缘之外的水面、断层仍沿用终止规则。
	effects._update_boundary_collision(Rect2(-8, -8, 16, 16), 0.0)
	player.bounds = Rect2(-8, -8, 16, 16)
	for kind in ["water", "cliff"]:
		if kind == "water": terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, true)
		else: terrain.data.set_level(Vector2i(1, 0), 1)
		await settle()
		var route := await predict()
		check(route.contacts.is_empty() and route.end_reason == &"ground_edge",
			"水面／断层继续终止，不误当空气墙：" + kind)
		terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, false)
		terrain.data.set_level(Vector2i(1, 0), 0)
		await settle()
	body.cancel(true)
	effects._update_boundary_collision(Rect2(), 0.0)
	await settle()
	check(not is_instance_valid(boundary) and effects._boundary == null,
		"无有效活动范围时移除旧空气墙")

func target_checks() -> void:
	pass
