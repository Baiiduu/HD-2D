extends "res://tests/test_ricochet_camera.gd"

var impacts: Array = []

func run() -> void:
	root.size = Vector2i(1280, 800)
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	box(Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))
	box(Vector3(2, 0.8, 0), Vector3(0.1, 1.6, 8))
	session = SESSION.new()
	session.name = "WavePrototype"
	session.phase = WavePrototype.Phase.BATTLE
	world.add_child(session)
	player = Player.new()
	player.name = "Player"
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.minimum_launch_speed = 12.0
	player.ricochet_rules.maximum_launch_speed = 12.0
	player.ricochet_rules.flight_deceleration = 0.05
	player.ricochet_rules.bounce_speed_retention = 0.9
	player.action_visuals = PlayerActionVisuals.new()
	player.action_visuals.show_aim_guide = false
	player.action_visuals.show_charge_effect = false
	# 此夹具验证运动与反弹，不建立正式地图的地形预览查询。
	player.action_visuals.show_aim_guide = false
	player.flight_trail_settings = PlayerFlightTrailSettings.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.set_script(load("res://scripts/rendering/character_lighting.gd"))
	var image := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.pixel_size = 0.04
	sprite.position.y = 0.48
	player.add_child(sprite)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.0
	collision.shape = capsule
	collision.position.y = 0.5
	player.add_child(collision)
	session.player = player
	world.add_child(player)
	camera = FollowCamera.new()
	camera.target = player
	camera.distance = 25.0
	camera.pitch_degrees = 30.627
	camera.fov = 28.0
	camera.horizontal_rotation_enabled = false
	camera.ricochet_camera_settings = settings
	world.add_child(camera)
	camera.set_process(false)
	camera.make_current()
	player.movement_camera = camera
	camera._bind_ricochet_camera()
	body = player.body_ricochet
	await settle(8)
	player.set_physics_process(false)
	check(body.has_signal("impact_recorded"), "真实反弹须提供物理时刻的入射与出射快照")
	if body.has_signal("impact_recorded"):
		body.connect("impact_recorded", func(impact): impacts.append(impact))
		await impact_checks()
		await presentation_checks()
		await path_and_trail_checks()
		await light_contact_checks()
		await particle_checks()
		profile_checks()
	world.queue_free()
	await settle()
	print("Ricochet impact feedback: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func impact_checks() -> void:
	await reset()
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "真实满速碰撞夹具可发射")
	for index in 30:
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		if not impacts.is_empty(): break
	check(impacts.size() == 1, "一次真实墙面反弹只记录一次碰撞")
	if impacts.is_empty(): return
	var impact: Variant = impacts.back()
	check(impact.incoming_velocity.x > 11.9 and impact.outgoing_velocity.x < 0.0, "快照保存同一碰撞前后的真实速度而非上一渲染帧方向")
	check(is_equal_approx(impact.outgoing_velocity.length(), impact.incoming_velocity.length() * 0.9 - player.ricochet_rules.bounce_speed_cost), "反馈快照保留真实碰撞耗速")
	check(impact.incoming_velocity.dot(impact.normal) < 0.0 and impact.outgoing_velocity.dot(impact.normal) > 0.0, "碰撞法线与入射出射关系正确")
	check(impact.flight_id == body.flight_serial and impact.seconds > 0.0, "碰撞归属当前发射并保存实际行进时间")
	var script: Script = load("res://scripts/player/ricochet_impact.gd")
	var grazing: Variant = script.new(Vector3.ZERO, Vector3.FORWARD, Vector3(12, 0, 0.3), Vector3(12, 0, -0.3))
	check(impact.strength() > 0.9 and grazing.strength() < 0.1, "绝对法向速度区分高速正撞与高速浅擦")
	check(impact.turn_side(1.0) == 1.0 and impact.turn_side(-1.0) == -1.0, "正撞折返使用稳定旋向而非随机翻边")
	var old_incoming: Vector3 = impact.incoming_velocity
	body.advance(0.1, Vector3.ZERO, false)
	check(impact.incoming_velocity == old_incoming, "后续移动不改写已有碰撞快照")

func presentation_checks() -> void:
	settings = load("res://data/combat/scenes/world/player/ricochet_camera.tres").duplicate() as RicochetCameraSettings
	camera.ricochet_camera_settings = settings
	settings.set("impact_shot_enabled", true)
	player.action_visuals.set("motion_feedback_enabled", true)
	player.action_visuals.set("departure_airflow_enabled", true)
	player.action_visuals.departure_airflow_texture = player.sprite.texture
	player.flight_trail_settings.set("bounce_rhythm_enabled", true)
	var motion: Variant = player.get("motion_feedback")
	check(motion != null, "人物创建可复用的运动表现组件")
	if motion == null: return
	motion.set_process(false)
	await reset()
	motion.set_process(false)
	impacts.clear()
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "表现组合正常发射")
	for index in 30:
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		motion.advance(1.0 / 120.0)
		camera._process(1.0 / 120.0)
		if not impacts.is_empty(): break
	check(not motion.lean.is_zero_approx(), "飞行姿态由真实速度驱动")
	check(not impacts.is_empty(), "表现组合须经过真实反弹")
	if impacts.is_empty(): return
	var impact: Variant = impacts.back()
	check(motion.lean.dot(Vector3.UP.cross(impact.incoming_velocity.normalized())) > 0.0, "撞击先保留入射惯性")
	var first := camera.global_transform
	var root_position := player.global_position
	var root_speed := body.flight_speed
	var has_arc := false
	for index in 14:
		motion.advance(0.01)
		camera._process(0.01)
		has_arc = has_arc or absf(camera._ricochet_camera.get("yaw_offset")) > 0.2
	check(has_arc and not camera.global_transform.is_equal_approx(first), "World 真实反弹接入曲线轻压与小幅观看角度反馈")
	check(motion.lean.dot(Vector3.UP.cross(body.direction)) > 0.0, "受力后转向真实出射倾向")
	check(player.global_position == root_position and body.flight_speed == root_speed, "镜头与人物显示不修改实际位置或速度")
	check(player.sprite.get_meta("motion_lean", Vector3.ZERO) == motion.lean, "显示姿态与主体遮罩共享同一份数据")
	check(camera.fov == 28.0 and camera.distance == 25.0 and camera.pitch_degrees == 30.627, "基础镜头参数不被反弹演出改写")
	body.advance(0.04, Vector3.ZERO, false)
	check(motion.active_airflow_count() > 0, "出射气流只由反弹后的真实路段生成")
	var ages: Array = motion.airflow_ages()
	var pose: Vector3 = motion.lean
	var camera_pose := camera.global_transform
	session.set_combat_frozen(true)
	motion.advance(0.2)
	camera._process(0.2)
	check(motion.lean == pose and motion.airflow_ages() == ages and camera.global_transform.is_equal_approx(camera_pose), "升级冻结同时暂停姿态气流与镜头")
	session.set_combat_frozen(false)
	body.cancel(true)
	for index in 40:
		motion.advance(0.01)
		camera._process(0.01)
	check(motion.lean.is_zero_approx() and motion.active_airflow_count() == 0, "移动接管后姿态回稳且气流自然收尾")
	check(is_zero_approx(camera._ricochet_camera.get("yaw_offset")) and is_zero_approx(camera._ricochet_camera.get("roll_offset")), "取消后临时镜头角度归零")
	check(Engine.time_scale == 1.0, "反馈保持真实时间与输入节奏")
	# 重播同一事件须去重；同帧新碰撞接住当前机位，避免跳回原点。
	var shot_script: Script = load("res://scripts/camera/ricochet_impact_shot.gd")
	var shot: Variant = shot_script.new()
	shot.start(impact, settings, 12.0)
	shot.advance(0.09, settings)
	var position: Vector3 = shot.offset
	var yaw: float = shot.yaw
	shot.start(impact, settings, 12.0)
	check(shot.offset == position and shot.yaw == yaw, "重复事件不重启镜头")
	var impact_script: Script = load("res://scripts/player/ricochet_impact.gd")
	var next: Variant = impact_script.new(impact.point, Vector3.BACK, Vector3.FORWARD * 10.0, Vector3.BACK * 9.0, impact.serial + 1, impact.flight_id, impact.seconds + 0.05)
	shot.start(next, settings, 12.0)
	shot.advance(0.0, settings)
	check(shot.offset.is_equal_approx(position) and is_equal_approx(shot.yaw, yaw), "连续碰撞从现有机位和角度接续")
	for index in 50: shot.advance(0.01, settings)
	check(not shot.active and shot.offset.is_zero_approx() and is_zero_approx(shot.yaw), "完整运镜段无残留")

func profile_checks() -> void:
	var formal := load("res://data/combat/scenes/world/configuration.tres") as SceneCombatConfiguration
	var city := load("res://data/combat/scenes/city/configuration.tres") as SceneCombatConfiguration
	check(formal.action_visuals.get("motion_feedback_enabled") == true and formal.ricochet_camera_settings.get("impact_shot_enabled") == true, "正式地图明确开启人物与镜头强碰撞反馈")
	check(formal.flight_trail_settings.get("bounce_rhythm_enabled") == true and formal.action_visuals.get("departure_airflow_enabled") == true, "正式地图开启残影节奏与出射气流")
	check(city.action_visuals.get("motion_feedback_enabled") == false and city.ricochet_camera_settings.get("impact_shot_enabled") == false, "City 保留原有独立表现")
	check(formal.action_visuals.departure_airflow_texture != null and formal.action_visuals.departure_airflow_texture.get_size() == Vector2(80, 24), "正式气流读取 Meowa 原生尺寸，不重采样素材")

func light_contact_checks() -> void:
	await reset()
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "浅擦反馈用例正常发射")
	body.advance(0.05, Vector3.ZERO, false)
	camera._process(0.05)
	var feedback := camera._ricochet_camera
	# 极浅擦会被曲线的法向速度门槛忽略，但仍收到共用反弹通知。
	feedback._on_bounced(Vector3.ZERO, Vector3.LEFT)
	camera._process(0.01)
	check(not feedback._impact_shot.active and feedback.shake.is_zero_approx(), "曲线模式忽略极浅擦时，不退回与法向速度无关的旧震动")
	body.cancel(true)

func sample_path(enabled: bool) -> Array[Vector4]:
	await reset()
	settings.impact_shot_enabled = enabled
	player.action_visuals.motion_feedback_enabled = enabled
	player.action_visuals.departure_airflow_enabled = enabled
	player.flight_trail_settings.bounce_rhythm_enabled = enabled
	player.action_visuals.bounce_particles_enabled = enabled
	var motion := player.motion_feedback
	var trail := player.flight_trail
	motion.set_process(false)
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "对照路线真实发射")
	trail.set_physics_process(false)
	trail.set_process(false)
	var path: Array[Vector4] = []
	for frame in 55:
		body.advance(0.01, Vector3.ZERO, false)
		motion.advance(0.01)
		trail._physics_process(0.01)
		trail._display_at(trail._clock)
		camera._process(0.01)
		path.append(Vector4(player.position.x, player.position.y, player.position.z, body.flight_speed))
		if enabled and frame == 22:
			check(not trail._rhythm_events.is_empty(), "真实反弹记录独立的残影节奏时间")
			var captured := trail._echoes.filter(func(echo): return echo.active)
			check(not captured.is_empty(), "反弹后残影沿真实路段重建")
			if not captured.is_empty():
				var echo: Dictionary = captured[0]
				var fixed: Vector3 = echo.sprite.global_position
				var lean_before: Variant = echo.material.get_shader_parameter("echo_lean")
				motion.advance(0.01)
				camera._yaw_offset_degrees += 10.0
				camera._process(0.01)
				check(echo.sprite.global_position == fixed and echo.material.get_shader_parameter("echo_lean") == lean_before, "旋转镜头或改变主体倾斜不拖走已有残影")
	return path

func particle_checks() -> void:
	if not "bounce_particles_enabled" in player.action_visuals:
		check(false, "反弹需要独立的少量像素粒子入口")
		return
	player.action_visuals.set("bounce_particles_enabled", true)
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(player)
	for property in ["bounce_particles_enabled", "bounce_particle_count", "bounce_particle_speed", "bounce_particle_seconds"]:
		check(entries.any(func(item): return item.property == property and item.common and item.label != property), "参数总览提供反弹粒子入口：" + property)
	var effect: Variant = player.bounce_effect
	await reset()
	effect.clear()
	impacts.clear()
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "粒子用例经过真实发射")
	for frame in 30:
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		if not impacts.is_empty(): break
	var particles: Variant = effect.sparks
	check(particles != null and particles.active and particles.emitted > 0, "真实墙面反弹触发单批像素碎屑")
	if particles == null: return
	var count: int = particles.emitted
	effect._impact_recorded(impacts.back())
	check(particles.emitted == count, "同次碰撞重复通知不追加粒子")
	var outside := true
	var native_pixel := true
	var impact: RicochetImpact = impacts.back()
	for index in particles._written:
		var velocity: Color = particles._launches[index]
		outside = outside and Vector3(velocity.r, 0.0, velocity.b).dot(impact.normal) > 0.0
		native_pixel = native_pixel and is_equal_approx(particles._transforms[index].basis.x.length(), player.sprite.pixel_size * player.sprite.global_basis.x.length() * 6.0)
	check(outside and native_pixel, "碎屑沿墙外半空间散开，保持原生六像素尺寸")
	check(particles.get_child_count() == 0 and particles.multimesh.instance_count <= 256, "少量反弹粒子复用小容量批次，不创建逐粒节点")
	var clock: float = particles.clock
	camera._process(0.02)
	var pose := camera.global_transform
	session.set_combat_frozen(true)
	effect._process(0.1)
	camera._process(0.1)
	check(particles.clock == clock and camera.global_transform.is_equal_approx(pose), "升级冻结同时暂停粒子与短冲击镜头")
	session.set_combat_frozen(false)
	effect._process(0.0)
	effect._process(0.6)
	check(not particles.active and not effect.is_processing(), "粒子到期回收并停止空闲处理")
	var children: int = effect.get_child_count()
	var previous_count: int = particles.emitted
	var show_effect := player.action_visuals.show_bounce_effect
	player.action_visuals.show_bounce_effect = false
	var next := RicochetImpact.new(impact.point, impact.normal, impact.incoming_velocity, impact.outgoing_velocity, impact.serial + 1, impact.flight_id, impact.seconds)
	seed(217)
	var expected := randi()
	seed(217)
	effect._impact_recorded(next)
	check(randi() == expected and particles.emitted > previous_count, "反弹粒子独立于碰点帧动画，不消耗战斗随机流")
	check(effect.get_child_count() == children, "后续反弹复用同一批次和材质")
	effect._phase_changed(WavePrototype.Phase.REST)
	check(not particles.active and not effect.is_processing(), "清波立刻回收粒子并停止处理")
	player.action_visuals.show_bounce_effect = show_effect
	player.action_visuals.set("bounce_particles_enabled", false)
	check(not load("res://data/combat/scenes/city/player/action_visuals.tres").get("bounce_particles_enabled"), "City 不自动加入反弹粒子")
	body.cancel(true)

func path_and_trail_checks() -> void:
	var baseline := await sample_path(false)
	var enhanced := await sample_path(true)
	check(baseline == enhanced, "人物倾斜残影气流与运镜组合不改真实路线及逐步耗速")
	var motion := player.motion_feedback
	var proxy := MeshInstance3D.new()
	world.add_child(proxy)
	player.sprite.apply_motion_to(proxy)
	check(proxy.get_instance_shader_parameter("motion_lean") == motion.lean, "倒影与轮廓代理读取同一世界倾斜")
	check(proxy.get_instance_shader_parameter("motion_pivot") == player.sprite.get_meta("motion_pivot"), "倒影与轮廓代理读取同一脚底枢轴")
	proxy.queue_free()
	body.cancel(true)
	motion.advance(0.2)
	motion.advance(0.2)
	var pooled := motion.get_child_count()
	check(motion.active_airflow_count() == 0 and not motion.is_processing(), "结束后气流回收并停止空闲处理")
	await reset()
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "复用夹具再次发射")
	for frame in 22:
		body.advance(0.01, Vector3.ZERO, false)
		motion.advance(0.01)
	check(motion.get_child_count() <= pooled, "后续反弹复用气流节点，不反复创建")
	session.phase_changed.emit(WavePrototype.Phase.REST)
	check(motion.lean.is_zero_approx() and motion.active_airflow_count() == 0, "清波同时清理人物附加姿态与气流")
	# 关闭倾斜仍可单独播放气流，关闭两者立即清理并停止空闲工作。
	await reset()
	player.action_visuals.motion_feedback_enabled = false
	player.action_visuals.departure_airflow_enabled = true
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "气流可独立于人物倾斜开启")
	for frame in 22:
		body.advance(0.01, Vector3.ZERO, false)
		motion.advance(0.01)
	check(motion.lean.is_zero_approx() and motion.active_airflow_count() > 0 and motion.is_processing(), "气流单独开启时正常发射和回收，不残留姿态")
	player.action_visuals.departure_airflow_enabled = false
	motion.advance(0.01)
	check(motion.active_airflow_count() == 0 and not motion.is_processing(), "关闭运动表现立即清理临时资源")
