extends "res://tests/test_aim_path_preview.gd"

func target_checks() -> void:
	pass

func path_checks() -> void:
	var cam := FollowCamera.new()
	cam.target = player
	cam.distance = 30.0
	cam.pitch_degrees = 30.627
	cam.yaw_degrees = 135.0
	cam.fov = 28.0
	var screen := ColorRect.new()
	screen.material = ShaderMaterial.new()
	screen.material.shader = load("res://shaders/post/post_process.gdshader")
	world.add_child(screen)
	cam.post_process = screen
	player.movement_camera = cam
	world.add_child(cam)
	cam.set_process(false)
	check(cam.has_method("play_hurt_feedback"), "受伤具有独立的画面提示入口，不借用击杀短顿")
	if not cam.has_method("play_hurt_feedback"): return
	var visuals = load("res://data/combat/scenes/world/player/action_visuals.tres").duplicate()
	player.action_visuals = visuals
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(player)
	for property in ["hurt_screen_enabled", "hurt_screen_opacity", "hurt_screen_seconds", "hurt_screen_color", "hurt_camera_enabled", "hurt_shake_pixels", "hurt_shake_seconds", "hurt_orbit_shake_pixels", "hurt_orbit_shake_seconds", "hurt_shake_interval"]:
		check(entries.any(func(entry): return entry.property == property and entry.category == "人物"), "参数总览可调：" + property)
	check(visuals.get("hurt_screen_enabled") == true and visuals.get("hurt_camera_enabled") == true, "World 开启边缘红光与轻震")
	check(not PlayerActionVisuals.new().get("hurt_screen_enabled") and not load("res://data/combat/scenes/city/player/action_visuals.tres").get("hurt_camera_enabled"), "共享默认与 City 保持独立")
	var neutral := cam.global_transform
	var focus := cam.focus
	var anchor := cam.anchor
	var velocity := player.velocity
	var speed := body.flight_speed
	var direction := body.direction
	var state := body.state
	var sword_age := player.sword._age
	var time_scale := Engine.time_scale
	player.take_damage(2.0)
	var feedback = cam.get("_hurt_feedback")
	check(feedback != null and feedback.red_amount > 0.0, "真实扣血立即开始红光，无须等待粒子或下一次攻击")
	if not feedback: return
	check(is_equal_approx(float(screen.material.get_shader_parameter("hurt_amount")), feedback.red_amount), "真实屏幕后处理接收红光强度")
	cam.call("advance_hurt_feedback", 0.02)
	check(not cam.global_transform.origin.is_equal_approx(neutral.origin) and cam.global_basis.is_equal_approx(neutral.basis), "轻震只平移相机，不旋转、缩放或改变构图方向")
	check(cam.focus == focus and cam.anchor == anchor, "受伤偏移不写入跟随焦点或累积为追赶误差")
	check(player.velocity == velocity and body.flight_speed == speed and body.direction == direction and body.state == state and player.sword._age == sword_age and Engine.time_scale == time_scale and not player.hit_stop_active, "受伤不改变位移、余速、飞行状态、挥剑时钟或世界速度")
	var normal_pixels: float = feedback.shake.length()
	check(normal_pixels > 0.0 and normal_pixels <= 1.5, "普通受伤总平移受小范围像素上限约束")
	cam.call("clear_hurt_feedback")
	feedback.begin(visuals, true, false)
	feedback.advance(0.02, visuals, true, false)
	check(feedback.shake.length() > 0.0 and feedback.shake.length() < normal_pixels and feedback.shake.length() <= 0.65, "绕行受伤保留更轻且更短的震动")
	cam.call("clear_hurt_feedback")
	cam.hit_shot_active = true
	player.take_damage(2.0)
	cam.call("advance_hurt_feedback", 0.02)
	check(feedback.red_amount > 0.0 and feedback.shake.is_zero_approx(), "已有攻击／击杀反馈时仍显示红光并让出震动")
	cam.hit_shot_active = false
	cam.call("advance_hurt_feedback", 0.01)
	check(feedback.shake.is_zero_approx(), "高优先级反馈结束后不补播受伤震动")
	cam.call("clear_hurt_feedback")
	player.take_damage(2.0)
	cam.call("advance_hurt_feedback", 0.02)
	cam.hit_shot_active = true
	cam._apply_transform()
	cam.hit_shot_active = false
	cam._apply_transform()
	check(feedback.shake.is_zero_approx(), "同帧后到的击杀反馈立即撤掉轻震，之后也不恢复旧震动")
	cam.call("clear_hurt_feedback")
	cam.ricochet_camera_settings = RicochetCameraSettings.new()
	cam._bind_ricochet_camera()
	cam._ricochet_camera._impact_shot.active = true
	player.take_damage(2.0)
	cam.call("advance_hurt_feedback", 0.02)
	check(feedback.red_amount > 0.0 and feedback.shake.is_zero_approx(), "碰墙机位曲线刚启动、偏移仍为零时也优先于受伤轻震")
	cam._ricochet_camera._impact_shot.active = false
	cam.call("clear_hurt_feedback")
	player.take_damage(2.0)
	cam.call("advance_hurt_feedback", 0.1)
	player.take_damage(2.0)
	check(feedback.red_amount <= 0.08 and feedback.shake.is_zero_approx(), "连续受伤红光不叠加强度，间隔内不重启或排队震动")
	cam.call("advance_hurt_feedback", 0.11)
	check(feedback.shake.is_zero_approx(), "冷却期间不会延后补播")
	cam.call("clear_hurt_feedback")
	player.take_damage(2.0)
	player.hit_stop_active = true
	Engine.time_scale = 0.001
	cam.set("_hurt_last_tick", Time.get_ticks_usec() - 20000)
	cam._process(1.0 / 60.0)
	check(feedback.red_amount > 0.0 and feedback.red_amount < 0.08, "定格切入旧 delta 不会被时间倍率放大而直接跳过整段红光")
	cam.call("advance_hurt_feedback", 0.21)
	check(feedback.red_amount == 0.0 and feedback.shake.is_zero_approx() and Engine.time_scale == 0.001, "红光按真实时间结束，不改变既有慢放所有者")
	Engine.time_scale = time_scale
	player.hit_stop_active = false
	cam.call("clear_hurt_feedback")
	player.take_damage(2.0)
	cam.call("advance_hurt_feedback", 0.02)
	session.set_combat_frozen(true)
	var held: float = feedback.red_amount
	var pose := cam.global_transform
	cam.call("advance_hurt_feedback", 0.5)
	check(feedback.red_amount == held and cam.global_transform == pose, "升级冻结同停，恢复不累计冻结期间的时间")
	session.set_combat_frozen(false)
	cam.call("advance_hurt_feedback", 0.03)
	check(feedback.red_amount < held, "解除冻结继续原反馈")
	cam.call("clear_hurt_feedback")
	visuals.set("hurt_particles_enabled", false)
	player.take_damage(2.0)
	check(feedback.red_amount > 0.0, "红光和轻震独立于粒子开关")
	visuals.set("hurt_screen_enabled", false)
	visuals.set("hurt_camera_enabled", false)
	cam.call("advance_hurt_feedback", 0.01)
	check(feedback.red_amount == 0.0 and feedback.shake.is_zero_approx(), "关闭画面提示立即清理各自通路")
	visuals.set("hurt_screen_enabled", true)
	visuals.set("hurt_camera_enabled", true)
	cam.call("advance_hurt_feedback", 0.01)
	check(feedback.red_amount == 0.0, "重新开启也不恢复已关闭的旧红光")
	await orbit_hurt_checks(cam)
	cam.call("clear_hurt_feedback")
	player.take_damage(2.0)
	session.run_started.emit()
	check(feedback.red_amount == 0.0 and screen.material.get_shader_parameter("hurt_amount") == 0.0, "重试清理红光、震动与计时")
	player.take_damage(2.0)
	player.hurt_effect.free()
	player.hurt_effect = null
	check(feedback.red_amount == 0.0 and feedback.shake.is_zero_approx(), "组件移除不会遗留红屏或镜头偏移")

func orbit_hurt_checks(cam: FollowCamera) -> void:
	player.ricochet_rules = load("res://data/combat/scenes/world/player/body_ricochet.tres").duplicate()
	player.ricochet_rules.flight_deceleration = 4.0
	session._path_ready = true
	session._path = navigation
	enemy(Vector3(2.6, 0, 0))
	await predict(Vector3.RIGHT, 1, 8.0)
	cam.snap_to_target()
	var aim = cam.project_charge_aim(Vector2(640, 360), player.global_position.y)
	player.take_damage(1.0)
	cam.advance_hurt_feedback(0.02)
	var shifted_aim = cam.project_charge_aim(Vector2(640, 360), player.global_position.y)
	check(aim is Vector3 and shifted_aim is Vector3 and aim.distance_to(shifted_aim) < 0.00001, "受伤轻震不带偏固定鼠标的真实蓄力瞄准")
	cam.clear_hurt_feedback()
	check(body.release_charge(), "携带受伤反馈仍正常发射")
	for frame in 240:
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		if body.orbiting or not body.flying: break
	check(body.orbiting, "真实怪群接触进入持续绕行")
	var point := player.position
	var speed := body.flight_speed
	var direction := body.direction
	var elapsed := body.flight_elapsed
	var sword_age := player.sword._age
	var camera_lens := cam._orbit_offset()
	player.take_damage(1.0)
	cam.advance_hurt_feedback(0.02)
	var feedback = cam.get("_hurt_feedback")
	check(body.orbiting and player.position == point and body.flight_speed == speed and body.direction == direction and body.flight_elapsed == elapsed and player.sword._age == sword_age, "真实绕行中受伤不重置轨迹、余速、方向或挥剑进度")
	check(feedback.shake.length() > 0.0 and feedback.shake.length() <= 0.65 and cam._orbit_offset().is_equal_approx(camera_lens), "真实绕行自动使用极轻震动，并保持原有取景距离与角度")
	cam.clear_hurt_feedback()
	body.cancel(true)
	clear_enemies()
