extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(15.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	var enemy := WaveEnemy.new()
	stage.add_child(enemy)
	enemy.position = Vector3(2, 0, -3)
	var effect: MirrorMarkEffect = load("res://scenes/combat/mirror_mark_effect.tscn").instantiate()
	stage.add_child(effect)
	print("Shared mirror quad size: ", effect._sprite.mesh.get_aabb().size)
	for yaw in [0.0, 0.7, 1.5]:
		camera.rotation = Vector3(-0.44355, yaw, 0)
		for normal in [Vector3.LEFT, Vector3(-0.7, 0, -0.7).normalized(), Vector3.FORWARD]:
			for density in [0.016, 0.02, 0.03]:
				effect.pixel_size = density
				effect.attach(enemy, normal)
				effect._process(0.04)
				var original := effect._sprite.global_transform
				var reveal: float = effect._material.get_shader_parameter("reveal")
				var glint: float = effect._material.get_shader_parameter("glint")
				effect.shatter(effect._sprite.global_position)
				var reconstructed := true
				for index in 4:
					var rect: Vector4 = effect._piece_materials[index].get_shader_parameter("frame_rect")
					var size := effect._sprite.mesh.get_aabb().size
					for uv in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE]:
						var part: Vector2 = Vector2(rect.x, rect.y) + uv * Vector2(rect.z, rect.w)
						var expected := original * Vector3((part.x - 0.5) * size.x, (0.5 - part.y) * size.y, 0)
						var actual := effect._pieces[index].global_transform * Vector3((uv.x - 0.5) * size.x, (0.5 - uv.y) * size.y, 0)
						reconstructed = reconstructed and actual.distance_to(expected) < 0.00001
				check(reconstructed, "碎裂首帧各切片严格拼回原尺寸、位置与旋转：yaw=%s normal=%s pixel=%s" % [yaw, normal, density])
				check(effect._piece_materials.all(func(material): return material.get_shader_parameter("reveal") == reveal and material.get_shader_parameter("glint") == glint), "碎片保留镜片的显现进度和闪光位置")
				effect._process(0.02)
				var age := effect._age
				effect.shatter(Vector3(99, 99, 99))
				check(is_equal_approx(effect._age, age), "重复死亡／到期通知不重启碎裂")
				effect.stop()
	# 池中接触火花没有原镜片，仍应从指定位置开始且不使用上次旋转。
	effect.shatter(Vector3(1, 2, 3))
	var center := Vector3.ZERO
	for piece in effect._pieces: center += piece.global_position * 0.25
	check(center.is_equal_approx(Vector3(1, 2, 3)), "独立墙面接触碎片使用本次接触位置")
	effect.stop()
	# 从完整贴印结束，也要继承当前屏幕位置，而非调用者的新接触点。
	effect.attach(enemy, Vector3.LEFT)
	effect._process(0.2)
	var original_position := effect._sprite.global_position
	effect.shatter(Vector3(99, 99, 99))
	center = Vector3.ZERO
	for piece in effect._pieces: center += piece.global_position * 0.25
	check(center.is_equal_approx(original_position), "已显示镜片在原位置碎开，不跳到新传入的位置")
	var piece_basis := effect._pieces[0].global_basis
	# 碎裂过程中只移动原尺寸切片。
	effect._process(effect.break_time * 0.5)
	check(effect._pieces[0].global_basis.is_equal_approx(piece_basis), "飘散过程不缩放碎片或改变像素尺度")
	var finished_count := [0]
	effect.finished.connect(func(): finished_count[0] += 1)
	effect._process(effect.break_time)
	check(finished_count[0] == 1 and not effect.is_processing() and effect._pieces.all(func(piece): return not piece.visible), "碎片淡出后只归还一次，闲置停止更新")
	# 致死首击从尚未贴印的敌人创建碎片，不能用到池中上一只怪物的坐标。
	enemy.dead = true
	enemy.position += Vector3(5, 0, 2)
	effect.attach(enemy, Vector3.LEFT)
	center = Vector3.ZERO
	for piece in effect._pieces: center += piece.global_position * 0.25
	check(center.is_equal_approx(enemy.global_position + Vector3.UP * effect.attachment_height), "致死首击使用本次怪物的位置与镜片姿态")
	effect.stop()
	stage.free()
	await process_frame
	print("Mirror fracture: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
