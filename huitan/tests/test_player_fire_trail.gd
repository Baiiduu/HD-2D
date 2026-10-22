extends "res://tests/test_aim_path_preview.gd"

func path_checks() -> void:
	var effect := player.fire_trail
	var settings := player.action_visuals
	check(effect != null and effect._mesh == null and not effect.is_processing(), "关闭时不预建绘制节点或逐帧工作")
	check(not settings.show_fire_trail and load("res://data/player/action_visuals.tres").show_fire_trail, "普通资源默认关闭，正式人物启用视觉试玩")
	settings.show_fire_trail = true
	player.ricochet_rules.crowd_deflection_enabled = false
	player.ricochet_rules.minimum_launch_speed = 8.0
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.sword.rules.enabled = false
	var health := player.current_health
	var wall := box(Vector3(2, 0.6, 0), Vector3(0.02, 1.2, 8))
	await predict()
	check(effect._count == 0, "蓄力预测不生成火带")
	check(body.release_charge(), "正式发射入口可用")
	for frame in 100:
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		if body.bounce_count > 0: break
	check(body.bounce_count == 1 and effect._count > 0, "实际位移在墙前留下火带，保留真实反弹")
	for index in effect._count:
		var matrix: Transform3D = effect._transforms[index]
		check(matrix.origin.x < 2.0 and absf(matrix.origin.z) < 0.001, "路段保持墙前实际位置，不连接穿墙端点")
		check(absf(matrix.origin.y - 0.014) < 0.005 and absf(matrix.basis.z.normalized().dot(Vector3.UP)) > 0.999, "火带贴实际支撑地面，承载面保持水平")
	var node := effect._mesh
	var material := effect._material
	var fixed := effect._transforms[0]
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(7, 7, 7)
	camera.look_at(Vector3.ZERO)
	player.position += Vector3.FORWARD * 2.0
	camera.rotate_y(PI * 0.5)
	check(effect._transforms[0] == fixed and effect.global_transform == Transform3D.IDENTITY, "人物移动与镜头旋转均不移动或旋转已留下的地面层")
	effect._process(0.25)
	var age := effect._clock
	var count := effect._count
	session.set_combat_frozen(true)
	effect._process(0.8)
	check(effect._clock == age and effect._count == count and float(material.get_shader_parameter("effect_clock")) == age, "升级冻结同时暂停三个阶段与着色器流动")
	session.set_combat_frozen(false)
	body.cancel()
	check(effect._count == count, "取消飞行后地面余火仍留在世界位置自然消散")
	effect._process(3.0)
	check(effect._count == 0 and not effect.is_processing() and not effect.visible, "余烬完整消散后停止空闲工作")
	for index in 270:
		body.flight_segment_travelled.emit(Vector3(index * 0.01, 0.02, 1), Vector3(index * 0.01 + 0.01, 0.02, 1), Vector3.RIGHT, 0.01)
	check(effect._count == 270 and node.multimesh.instance_count >= 270, "密集曲线路段按需扩容，不丢弃仍存活的火带")
	check(effect._mesh == node and effect._material == material and effect.get_child_count() == 1, "所有路段共用一个绘制节点、网格和材质")
	check(effect._transforms[0].origin.distance_to(Vector3(0.005, 0.014, 1)) < 0.00001, "扩容后首段世界位置保留")
	effect._process(0.3)
	var old_count := effect._count
	body.flight_segment_travelled.emit(Vector3(3, 0.02, 1), Vector3(3.1, 0.02, 1), Vector3.RIGHT, 0.01)
	effect._process(effect._duration - 0.1)
	check(effect._count == 1 and old_count == 270, "旧段独立过期，新段不随整条火带一起重置或消失")
	check(player.current_health == health and session.enemies.is_empty(), "视觉不增加伤害、怪物或人物生命变化")
	settings.show_fire_trail = false
	effect._process(0.01)
	body.flight_segment_travelled.emit(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT, 0.1)
	check(effect._count == 0 and not effect.is_processing(), "关闭开关立即清理，拒绝后续路段")
	settings.show_fire_trail = true
	body.flight_segment_travelled.emit(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT, 0.1)
	session.phase_changed.emit(WavePrototype.Phase.REST)
	check(effect._count == 0 and not effect.visible, "离开战斗清理地面残留")
	body.flight_segment_travelled.emit(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT, 0.1)
	session.run_started.emit()
	check(effect._count == 0, "快速重试清理上一局火带")
	body.flight_segment_travelled.emit(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT, 0.1)
	player.current_health = 0.0
	effect._process(0.01)
	check(effect._count == 0 and not effect.is_processing(), "人物死亡清理并停止显示")
	player.current_health = health
	wall.queue_free()
	await settle()
	print("Ground fire trail lifecycle and real path checked")

func target_checks() -> void:
	pass
