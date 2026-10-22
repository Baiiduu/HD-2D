extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	var effect: LightPierceEffect = load("res://scenes/combat/light_pierce_effect.tscn").instantiate()
	var other: LightPierceEffect = load("res://scenes/combat/light_pierce_effect.tscn").instantiate()
	scene.add_child(effect)
	scene.add_child(other)
	var mesh := effect._trail.mesh
	check(mesh == other._trail.mesh, "不同飞行组件共享固定拖尾网格")
	check(mesh.surface_get_array_len(0) == 42 and mesh.surface_get_array_index_len(0) == 120,
		"保留原拖尾的 42 顶点和 40 个三角形")
	var origin := Vector3(4, 0.3, 44.8)
	var direction := Vector3(1, 0.3, -0.5).normalized()
	var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# 验证共用组件的旧轨迹仍等价；A02 后缘残影由像素风格测试单独覆盖。
	effect.preserve_trail_pixel_scale = false
	for yaw in [0.0, 90.0, 180.0]:
		camera.rotation_degrees = Vector3(-32, yaw, 0)
		effect.transform = Transform3D(Basis.from_euler(Vector3(0, 0.7, 0)).scaled(Vector3(1.2, 0.9, 1.1)), Vector3(3, 0.1, -2))
		effect.launch(origin, direction, 7.5)
		effect.set_process(false)
		for distance in [0.25, 2.2, 6.0, 7.5]:
			effect.travelled = distance
			effect._update_trail(camera)
			var tail_length := minf(effect.trail_length, distance)
			var side := camera.global_basis.z.cross(direction).normalized()
			var start: Vector3 = origin + Vector3.UP * effect.flight_height + direction * (distance - tail_length)
			var end: Vector3 = origin + Vector3.UP * effect.flight_height + direction * distance
			check(effect._trail.to_global(points[0]).distance_to(start + side * effect.trail_width * 0.15) < 0.00005
				and effect._trail.to_global(points[-1]).distance_to(end - side * effect.trail_width * 0.5) < 0.00005,
				"旋转镜头、倾斜发射与父变换下保留真实轨迹和渐宽轮廓")
	check(effect._trail.mesh == mesh, "飞行和镜头旋转不创建新拖尾网格")
	effect.trail_width = 0.8
	effect._update_trail(camera)
	check(effect._trail.mesh == mesh and is_equal_approx(effect._trail.global_basis.y.length(), 0.8),
		"实时调宽度只改变实例变换")
	effect.preserve_trail_pixel_scale = true
	effect.stop()
	check(not effect.is_processing() and not effect._trail.visible and not effect._light.visible,
		"闲置组件停止更新并隐藏拖尾与映照")
	for index in 3: effect.show_hit(origin + Vector3.RIGHT * index)
	var ids: Array[int] = []
	var material_ids: Array[int] = []
	for impact in effect._impacts:
		ids.append(impact.mesh.get_instance_id())
		material_ids.append(impact.material.get_instance_id())
	effect.set_process(false)
	effect._process(effect.impact_duration * 0.45)
	var texture := effect.impact_frames.get_frame_texture(effect.impact_animation, 3) as AtlasTexture
	var expected_rect := Vector4(texture.region.position.x / texture.atlas.get_width(),
		texture.region.position.y / texture.atlas.get_height(), texture.region.size.x / texture.atlas.get_width(),
		texture.region.size.y / texture.atlas.get_height())
	check(effect._impacts.size() == 3 and effect._impacts[0].material.get_shader_parameter("frame_rect") == expected_rect,
		"三次并发命中各自完整播放当前图集帧")
	effect.impact_width = 3.4
	effect._process(0.0)
	check(is_equal_approx((effect._impacts[0].mesh.mesh as QuadMesh).size.x, 3.4), "命中宽度参数仍实时生效")
	var finished_count := [0]
	effect.finished.connect(func(): finished_count[0] += 1)
	effect._process(effect.impact_duration)
	check(effect._impacts.is_empty() and effect._impact_pool.size() == 3 and finished_count[0] == 1
		and not effect.is_processing(), "完成时归还全部星芒，发出结束事件并停止更新")
	for index in 3: effect.show_hit(origin - Vector3.RIGHT * index)
	var reused := true
	for impact in effect._impacts:
		reused = reused and impact.mesh.get_instance_id() in ids and impact.material.get_instance_id() in material_ids
	check(reused and effect._impact_pool.is_empty(), "再次命中复用原节点与材质，不减少并发数量")
	effect.set_process(false)
	effect._process(0.05)
	check(is_equal_approx(effect._impacts[0].age, 0.05) and effect._impacts[0].mesh.visible,
		"复用后重新计时并显示新命中")
	effect.stop()
	var children := effect.get_child_count()
	for index in 200:
		effect.show_hit(origin)
		effect.stop()
	check(effect.get_child_count() == children and effect._impact_pool.size() == 3,
		"反复命中与取消不增长节点或材质数量")
	effect.launch(origin, direction, 1.0)
	effect.set_process(false)
	effect._process(1.0)
	check(not effect._head.visible and not effect._trail.visible and not effect._light.visible
		and not effect.is_processing(), "飞行尾迹自然结束后完全停止")
	scene.free()
	for frame in 3: await process_frame
	print("Light pierce reuse: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
