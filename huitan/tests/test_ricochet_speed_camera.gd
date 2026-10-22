extends "res://tests/test_charge_release.gd"

func settings_checks() -> void:
	await super.settings_checks()
	if not "flight_speed_camera_enabled" in settings:
		check(false, "滑行镜头需要持续读取实际余速，不能固定回到静止镜头")
		return
	await speed_camera_checks()
	await charge_focus_checks()

func charge_focus_checks() -> void:
	if not "flight_charge_focus_enabled" in settings:
		check(false, "高速弹射须延续满蓄聚焦与方向视觉，减速后再退出")
		return
	settings.flight_speed_camera_enabled = true
	settings.set("flight_charge_focus_enabled", true)
	settings.set("flight_charge_focus_ratio", 0.90)
	settings.charge_focus_enabled = true
	settings.charge_staging_enabled = true
	settings.charge_release_handoff_enabled = true
	settings.charge_zoom_ratio = 0.12
	var screen := ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/post/post_process.gdshader")
	screen.material = material
	world.add_child(screen)
	camera.post_process = screen
	var audio := GameAudio.new()
	audio.player = player
	audio.session = session
	audio.load_local_mix = false
	world.add_child(audio)
	var presentation = load("res://scripts/player/charge_presentation.gd").new()
	presentation.player = player
	presentation.audio = audio
	presentation.enabled = true
	presentation.direction_focus_enabled = true
	presentation.launch_release_enabled = true
	presentation.direction_focus_release_seconds = 0.10
	world.add_child(presentation)
	await settle(3)
	await ready_full()
	presentation.set_process(false)
	presentation.advance(0.2, 0.2)
	var held := camera.global_transform
	var held_level: float = presentation.direction_level
	check(body.release_charge(), "满蓄视觉延续由真实发射触发")
	presentation.set_process(false)
	body.flight_speed = 12.0
	camera._process(0.0)
	presentation.advance(0.0, 0.0)
	check(camera.global_transform.is_equal_approx(held) and is_equal_approx(presentation.direction_level, held_level), "松手当帧不切掉满蓄视觉")
	for frame in 90:
		camera._process(1.0 / 120.0)
		presentation.advance(1.0 / 120.0, 1.0 / 120.0)
	check(camera._ricochet_camera.distance_scale < 0.91 and camera._ricochet_camera.pitch_offset < -2.8, "高速延续满蓄的推近与低视角，不转成远景")
	check(float(screen.material.get_shader_parameter("charge_direction_amount")) > 0.80 and float(screen.material.get_shader_parameter("charge_focus_amount")) > 0.80, "高速持续保留方向清晰通道与轻柔化，不按固定零点一秒清除")
	check(is_zero_approx(float(audio.get("_charge_music_duck"))) and is_zero_approx(float(presentation.get("_airflow_level"))), "高速视觉保留时，背景声音与蓄力聚拢气流仍完成原发射收尾")
	body.direction = Vector3.FORWARD
	camera._process(0.02)
	presentation.advance(0.02, 0.02)
	var endpoint := camera.unproject_position(player.global_position + Vector3.UP * 0.05 + body.direction * presentation.direction_focus_length) / root.get_visible_rect().size
	check(Vector2(screen.material.get_shader_parameter("charge_route_end")).distance_to(endpoint) < 0.001, "高速方向通道跟随当前真实行进方向，不停留在原发射方向")
	var frozen := camera.global_transform
	var frozen_amount: float = presentation.direction_level
	session.set_combat_frozen(true)
	body.flight_speed = 6.0
	camera._process(0.3)
	presentation.advance(0.3, 0.3)
	check(camera.global_transform.is_equal_approx(frozen) and presentation.direction_level == frozen_amount, "升级冻结同时保持满蓄延续镜头与方向表现")
	session.set_combat_frozen(false)
	camera._process(0.0)
	presentation.advance(0.0, 0.0)
	check(camera.global_transform.is_equal_approx(frozen) and presentation.direction_level == frozen_amount, "扣速后先接住画面，再逐渐舒展")
	for frame in 120:
		camera._process(1.0 / 120.0)
		presentation.advance(1.0 / 120.0, 1.0 / 120.0)
	var mid_amount: float = presentation.direction_level
	check(camera._ricochet_camera.distance_scale > 0.94 and camera._ricochet_camera.distance_scale < 1.0 and mid_amount > 0.25 and mid_amount < 0.6, "中速时镜头与方向效果共同减弱，保持过渡层次")
	body.flight_speed = 3.0
	for frame in 120:
		camera._process(1.0 / 120.0)
		presentation.advance(1.0 / 120.0, 1.0 / 120.0)
	check(presentation.direction_level < mid_amount * 0.5 and camera._ricochet_camera.distance_scale > 0.97, "低速逐渐回到日常画面，不维持满强度")
	body.cancel(true)
	presentation.set_process(false)
	for frame in 90:
		camera._process(1.0 / 120.0)
		presentation.advance(1.0 / 120.0, 1.0 / 120.0)
	check(is_zero_approx(presentation.direction_level) and not presentation.is_processing() and is_equal_approx(camera._ricochet_camera.distance_scale, 1.0), "停止后恢复原画面并结束持续表现更新")
	presentation.free()
	audio.stop_all()
	audio.queue_free()
	screen.queue_free()
	settings.set("flight_charge_focus_enabled", false)
	settings.flight_speed_camera_enabled = false
	await settle(3)

func advance_camera(seconds: float) -> void:
	for frame in ceili(seconds * 120.0): camera._process(1.0 / 120.0)

func speed_camera_checks() -> void:
	settings.set("flight_speed_camera_enabled", true)
	settings.set("flight_reference_speed", 12.0)
	settings.set("flight_pullback_ratio", 0.08)
	settings.set("flight_pitch_drop", 2.0)
	settings.lookahead_ratio = 0.035
	settings.charge_focus_enabled = true
	settings.charge_staging_enabled = true
	settings.charge_release_handoff_enabled = true
	await ready_full()
	var held := camera.global_transform
	check(body.release_charge(), "速度镜头接收真实发射")
	body.flight_speed = 12.0
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(held), "满蓄到速度镜头的事件帧保留完整取景")
	advance_camera(0.6)
	var feedback := camera._ricochet_camera
	var fast_distance := feedback.distance_scale
	var fast_pitch := feedback.pitch_offset
	var fast_lead := feedback.framing.length()
	check(fast_distance > 1.06 and fast_pitch < -1.8, "高速滑行持续保持拉远与低视角，不在交接结束后回到静止配置")
	check(fast_lead > 0.025, "高速滑行保留更多前方观察空间")
	var frozen := camera.global_transform
	session.set_combat_frozen(true)
	body.flight_speed = 3.0
	camera._process(0.4)
	check(camera.global_transform.is_equal_approx(frozen), "升级冻结保持速度镜头的完整取景")
	session.set_combat_frozen(false)
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(frozen), "碰撞扣速或解冻后零时间不切换取景")
	advance_camera(0.7)
	check(feedback.distance_scale > 1.0 and feedback.distance_scale < fast_distance - 0.03, "低余速滑行平滑收近，仍保持飞行镜头")
	check(feedback.pitch_offset > fast_pitch + 0.8 and feedback.pitch_offset < 0.0, "低余速视角随之舒缓")
	check(feedback.framing.length() < fast_lead * 0.5, "前方留白按实际余速收敛")
	var low := camera.global_transform
	body.flight_speed = 120.0
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(low), "余速突变只改变目标，不立刻跳镜头")
	advance_camera(0.7)
	check(feedback.distance_scale <= 1.0801 and feedback.pitch_offset >= -2.001, "超出参考速度仍遵守拉远和俯角上限")
	check(camera.distance == 15.0 and camera.pitch_degrees == 25.414 and camera.fov == 28.0, "速度镜头不回写基础相机配置")
	var before_switch := camera.global_transform
	settings.flight_speed_camera_enabled = false
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(before_switch), "滑行中关闭速度镜头从当前取景退出")
	advance_camera(0.6)
	check(is_equal_approx(feedback.distance_scale, 1.0) and is_zero_approx(feedback.pitch_offset), "关闭局部开关可恢复原飞行镜头")
	before_switch = camera.global_transform
	settings.flight_speed_camera_enabled = true
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(before_switch), "滑行中重新开启速度镜头不跳切")
	advance_camera(0.6)
	check(feedback.distance_scale > 1.06, "重新开启后继续按当前余速建立飞行取景")
	var heading := body.direction
	camera._yaw_offset_degrees = 90.0
	camera._process(0.02)
	check(body.direction == heading, "Q/E 继续旋转镜头，不改变真实滑行方向")
	camera._yaw_offset_degrees = 0.0
	camera._process(0.0)
	var before_stop := camera.global_transform
	body.cancel(true)
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(before_stop), "主动停止从当前速度取景连续归位")
	camera._process(0.03)
	var returning := camera.global_transform
	check(body.begin_charge(Vector3.RIGHT), "速度镜头归位途中可再次蓄力")
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(returning), "再次蓄力继承未完成归位的镜头")
	body.cancel(true)
	advance_camera(0.6)
	check(not feedback.active and is_equal_approx(feedback.distance_scale, 1.0) and is_zero_approx(feedback.pitch_offset), "停止后完全回到日常镜头并结束反馈")
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "满蓄挤压中也可取消")
	body.advance(0.5, Vector3.ZERO, false)
	camera._process(0.01)
	camera._process(0.04)
	var pulse := camera.global_transform
	body.cancel(true)
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(pulse), "速度模式保留满蓄挤压中取消的真实距离")
	advance_camera(0.6)
	settings.impact_shot_enabled = true
	await reset()
	launch()
	for frame in 50:
		body.advance(0.01, Vector3.ZERO, false)
		player.reset_physics_interpolation()
		camera._process(0.01)
		if body.bounce_count > 0: break
	camera._process(0.04)
	var rebound := camera.global_transform
	body.cancel(true)
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(rebound), "真实反弹拉开仍在进行时停止，速度镜头不重复吸收碰撞偏移")
	advance_camera(0.6)
	settings.impact_shot_enabled = false
	settings.charge_focus_enabled = false
	settings.charge_staging_enabled = false
	settings.charge_release_handoff_enabled = false
	# 同一物理输入下对照真实轨迹，不能用镜头改善掩盖位移规则变化。
	settings.set("flight_speed_camera_enabled", false)
	var original := await motion_checks(true)
	settings.set("flight_speed_camera_enabled", true)
	var with_speed_camera := await motion_checks(true)
	check(original == with_speed_camera, "速度镜头开关不改变真实轨迹、耗速、碰撞和结束时刻")
	var formal := load("res://data/combat/scenes/world/player/ricochet_camera.tres")
	var city := load("res://data/combat/scenes/city/player/ricochet_camera.tres")
	check(formal.get("flight_speed_camera_enabled") and not city.get("flight_speed_camera_enabled"), "速度镜头仅由 World 独立启用")
