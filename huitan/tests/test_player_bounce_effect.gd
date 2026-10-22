extends "res://tests/test_crowd_deflection.gd"

func path_checks() -> void:
	player.action_visuals = load("res://data/player/action_visuals.tres").duplicate()
	player.ricochet_rules.minimum_launch_speed = 8.0
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.ricochet_rules.flight_deceleration = 2.5
	player.ricochet_rules.crowd_deflection_enabled = false
	player.sword.rules.enabled = false
	var effect := player.bounce_effect
	var settings := player.action_visuals
	settings.bounce = load("res://data/combat/scenes/world/player/character_bounce.tres")
	player.action_animator.visuals = settings
	check(effect != null and not effect.is_processing() and effect.get_child_count() == 0, "闲置组件不绘制或预建无用节点")
	check(settings.bounce_frames.get_frame_count(&"bounce") == 6 and not settings.bounce_frames.get_animation_loop(&"bounce"), "正式接入六帧单次 Meowa 动画")
	check(settings.bounce_frames.get_frame_texture(&"bounce", 0).get_size() == Vector2(56, 48), "保留母版与右侧透明运动空间的原生尺寸")
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(7, 7, 7)
	camera.look_at(Vector3(2, 0, 0))
	camera.make_current()
	var wall := box(Vector3(2, 0.6, 0), Vector3(0.02, 1.2, 8))
	wall.add_to_group(&"occlusion_buildings")
	await settle()
	await predict()
	check(body.release_charge(), "携带反弹视觉正常发射")
	for frame in 100:
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		if body.bounce_count > 0: break
	check(body.bounce_count == 1 and effect._active.size() == 1, "真实墙面反弹一次只触发一份特效")
	check(player.action_animator._attack == &"bounce", "真实建筑碰撞播放九帧人物反弹动作")
	player.action_animator.cancel_attack()
	body.crowd_deflected.emit(Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD)
	check(player.action_animator._attack.is_empty(), "怪物碰撞与绕行转向不触发人物反弹动作")
	var item := effect._active[0]
	check(item.point.x < 2.0 and item.direction.x < 0.0, "碰点在真实墙外，火花朝离墙侧散开")
	check(is_equal_approx(item.pixel, player.sprite.pixel_size * player.sprite.global_basis.x.length()), "尺寸跟随人物实际原生像素密度")
	var fixed: Vector3 = item.point
	for yaw in [0.0, 0.8, -1.3]:
		camera.rotate_y(yaw)
		effect._update(item, camera)
		var size: Vector2 = item.frames[item.frame].size
		var local_anchor := Vector3(item.anchor.x / size.x - 0.5, 0.5 - item.anchor.y / size.y, 0)
		check((item.mesh.global_transform * local_anchor).distance_to(fixed) < 0.00001, "镜头旋转后核心仍锚定同一世界碰点")
	player.position += Vector3.FORWARD
	effect._update(item, camera)
	check(item.point == fixed, "人物离开后火花不追随人物")
	var motion_speed := body.flight_speed
	var direction := body.direction
	check(effect.play(Vector3(1, 0, 1), Vector3.RIGHT, Vector3.RIGHT) and effect.play(Vector3(1, 0, -1), Vector3.LEFT, Vector3.LEFT), "同帧多个碰点各自保留，互不覆盖")
	check(effect._active.size() == 3 and body.flight_speed == motion_speed and body.direction == direction, "表现不修改飞行速度或方向")
	check(effect._active[0].mesh.material_override == effect._active[1].mesh.material_override, "同一图集共用材质")
	effect._process(0.3)
	check(effect._active.size() == 3 and effect._active[0].frame == 0, "低帧率也至少呈现一次接触首帧")
	effect._process(0.06)
	var age: float = item.age
	session.set_combat_frozen(true)
	effect._process(0.5)
	check(item.age == age and effect._active.size() == 3, "升级冻结暂停动画与淡出")
	session.set_combat_frozen(false)
	effect._process(0.2)
	check(effect._active.is_empty() and not effect.is_processing() and effect._pool.size() == 3, "完整播完后回收并停止空闲工作")
	check(effect.play(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT) and effect.get_child_count() == 3, "后续反弹复用节点")
	settings.show_bounce_effect = false
	effect._process(0.01)
	check(effect._active.is_empty() and not effect.is_processing() and not effect.play(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT), "独立关闭立即清理并停止新特效")
	settings.show_bounce_effect = true
	effect.play(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT)
	session.phase_changed.emit(WavePrototype.Phase.REST)
	check(effect._active.is_empty() and not effect.is_processing(), "离开战斗清理世界碰点，节点保留复用")
	wall.queue_free()
	await clear()

func target_checks() -> void:
	pass
