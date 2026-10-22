extends "res://tests/test_charge_staging.gd"

func settings_checks() -> void:
	await super.settings_checks()
	if not "charge_release_handoff_enabled" in settings:
		check(false, "满蓄发射需要独立的连续交接配置")
		return
	await release_checks()
	await direction_checks()
	await accent_checks()

func accent_checks() -> void:
	if not settings.has_method("release_progress"):
		check(false, "发射需要前段展开、后段收稳的连续释放曲线")
		return
	settings.set("charge_release_burst", 1.0)
	var previous := 0.0
	var monotonic := true
	for sample in 101:
		var progress: float = settings.call("release_progress", sample * 0.0026, 0.26)
		monotonic = monotonic and progress >= previous and progress <= 1.0
		previous = progress
	check(monotonic and is_equal_approx(previous, 1.0), "释放曲线单向展开并准确收稳，不越界回拉")
	check(float(settings.call("release_progress", 0.10, 0.26)) > 0.60, "发射前一百毫秒完成主要展开")
	# 原有位姿、速度、走位与碰墙回归同时覆盖新的展开曲线。
	await release_checks()
	settings.charge_focus_enabled = true
	settings.charge_staging_enabled = true
	settings.charge_release_handoff_enabled = true
	settings.charge_direction_bias_ratio = 0.022
	await ready_full()
	var forward := Vector2(Vector3.RIGHT.dot(camera.global_basis.x), Vector3.RIGHT.dot(camera.global_basis.y)).normalized()
	check(camera._ricochet_camera.framing.dot(forward) > 0.02, "临近满蓄为真实出射方向留出前方空间")
	var before_turn := camera.global_transform
	body.aim(Vector3.FORWARD)
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(before_turn), "满蓄突然改变瞄准时构图不跳切")
	for frame in 20: camera._process(0.01)
	var turned := Vector2(Vector3.FORWARD.dot(camera.global_basis.x), Vector3.FORWARD.dot(camera.global_basis.y)).normalized()
	check(camera._ricochet_camera.framing.dot(turned) > 0.015, "前方留白平滑跟随新的瞄准方向")
	var audio := GameAudio.new()
	audio.player = player
	audio.session = session
	audio.load_local_mix = false
	world.add_child(audio)
	var feedback: CoreFeedbackAudio = load("res://scenes/audio/core_feedback_audio.tscn").instantiate()
	feedback.player = player
	feedback.session = session
	feedback.set("launch_release_audio_enabled", true)
	world.add_child(feedback)
	var screen := ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/post/post_process.gdshader")
	screen.material = material
	world.add_child(screen)
	camera.post_process = screen
	var presentation = load("res://scripts/player/charge_presentation.gd").new()
	presentation.player = player
	presentation.audio = audio
	presentation.enabled = true
	presentation.direction_focus_enabled = true
	presentation.set("launch_release_enabled", true)
	presentation.direction_focus_release_seconds = 0.10
	world.add_child(presentation)
	await settle(3)
	await ready_full()
	presentation.set_process(false)
	feedback.set_physics_process(false)
	presentation.advance(0.15, 0.15)
	feedback._physics_process(0.0)
	var held := camera.global_transform
	var amount: float = presentation.direction_level
	var duck: float = audio.get("_charge_music_duck")
	check(body.release_charge(), "释放编排使用真实发射事件，不延迟位移")
	presentation.set_process(false)
	feedback.set_physics_process(false)
	camera._process(0.0)
	presentation.advance(0.0, 0.0)
	check(camera.global_transform.is_equal_approx(held) and is_equal_approx(presentation.direction_level, amount), "释放事件帧保留当前镜头和柔化，随后连续展开")
	var launches := audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:launch")
	check(launches.size() == 1 and launches[0].priority >= 70, "发射当帧只播放一次主音，并使用公共池的重要声音预算")
	check(launches.size() == 1 and is_equal_approx(launches[0].gain_db, feedback.action_volume_db + feedback.get("launch_full_gain_db")), "满蓄发射增益叠加在动作音量上，仍沿用原音源和本机混音")
	check(not audio._voices.any(func(slot): return slot.active and slot.cue == &"core:charge_loop"), "发射事件立即停止蓄力循环")
	var initial_zoom := 1.0 - camera._ricochet_camera.distance_scale
	for frame in 5:
		body.advance(0.01, Vector3.ZERO, false)
		player.reset_physics_interpolation()
		camera._process(0.01)
		presentation.advance(0.01, 0.01)
		feedback._physics_process(0.01)
	check(presentation.direction_level <= amount * 0.55, "五十毫秒时柔化已经退去主要部分")
	check(is_equal_approx(float(audio.get("_charge_music_duck")), duck), "发射声起音期间保留背景退让")
	var winds := audio._voices.filter(func(slot): return slot.active and slot.cue == &"core:flight_loop")
	var natural_wind := feedback.action_volume_db + feedback.flight_gain_db + linear_to_db(maxf(feedback._flight_level, 0.00001))
	check(winds.size() == 1 and winds[0].gain_db < natural_wind - 5.0, "飞行气流前段主动退让，不盖住发射起音")
	var wind_age: float = feedback.get("_flight_entry_age")
	var frozen_zoom := camera._ricochet_camera.distance_scale
	var frozen_amount: float = presentation.direction_level
	session.set_combat_frozen(true)
	camera._process(0.3)
	presentation.advance(0.3, 0.3)
	feedback._physics_process(0.3)
	check(camera._ricochet_camera.distance_scale == frozen_zoom and presentation.direction_level == frozen_amount and feedback.get("_flight_entry_age") == wind_age, "冻结同时保持镜头、清晰恢复与气流入场时序")
	session.set_combat_frozen(false)
	for frame in 5:
		body.advance(0.01, Vector3.ZERO, false)
		player.reset_physics_interpolation()
		camera._process(0.01)
		presentation.advance(0.01, 0.01)
		feedback._physics_process(0.01)
	check(presentation.direction_level < amount * 0.01 and 1.0 - camera._ricochet_camera.distance_scale < initial_zoom * 0.40, "一百毫秒时恢复清晰且镜头完成主要展开")
	check(float(presentation.get("_duck_level")) > presentation.level, "画面先打开，背景音随后恢复，发射主音保留重心")
	feedback._physics_process(0.05)
	natural_wind = feedback.action_volume_db + feedback.flight_gain_db + linear_to_db(maxf(feedback._flight_level, 0.00001))
	check(winds.size() == 1 and is_equal_approx(winds[0].gain_db, natural_wind), "起音之后气流回到真实余速对应的正常音量")
	var before_cancel: float = presentation.level
	var duck_before_cancel: float = presentation.get("_duck_level")
	body.cancel(true)
	presentation.set_process(false)
	presentation.advance(0.0, 0.0)
	check(is_equal_approx(presentation.level, before_cancel) and is_equal_approx(float(presentation.get("_duck_level")), duck_before_cancel), "释放中取消从当前画面和混音退回")
	presentation.advance(0.6, 0.6)
	feedback._physics_process(0.6)
	check(not presentation.is_processing() and is_zero_approx(float(audio.get("_charge_music_duck"))), "取消收尾清除表现和背景退让，停止闲置处理")
	feedback.free()
	presentation.free()
	audio.stop_all()
	audio.queue_free()
	screen.queue_free()
	settings.set("charge_release_burst", 0.0)
	settings.charge_direction_bias_ratio = 0.0
	settings.charge_focus_enabled = false
	settings.charge_staging_enabled = false
	settings.charge_release_handoff_enabled = false
	settings.impact_shot_enabled = true
	await ready_full()
	body.release_charge()
	for frame in 30:
		body.advance(0.01, Vector3.ZERO, false)
		player.reset_physics_interpolation()
		camera._process(0.01)
		if body.bounce_count > 0: break
	check(body.bounce_count > 0, "释放组合回归经过真实墙面反弹")
	camera._process(0.04)
	var frozen_pose := camera.global_transform
	session.set_combat_frozen(true)
	camera._process(0.3)
	check(camera.global_transform.is_equal_approx(frozen_pose), "反弹偏航期间升级冻结保持完整取景，不重新投影局部构图")
	session.set_combat_frozen(false)
	settings.impact_shot_enabled = false
	await settle(3)

func ready_full(walking := false) -> void:
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "交接用例开始真实蓄力")
	for frame in 60:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		if walking: player.position.z += 2.0 / 60.0
		player.reset_physics_interpolation()
		camera._process(1.0 / 60.0)

func release_checks() -> void:
	# 手动推进实际物理规则时，直接采样位置以独立检验镜头导数；插值观感由人工验收。
	player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	settings.charge_focus_enabled = true
	settings.charge_staging_enabled = true
	settings.set("charge_release_handoff_enabled", true)
	settings.charge_release_seconds = 0.26
	await ready_full()
	var held := camera.global_transform
	var focus := camera.focus
	check(body.release_charge(), "满蓄立即发射，不等待镜头")
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(held), "满蓄到发射事件帧保留完整取景")
	body.advance(0.001, Vector3.ZERO, false)
	player.reset_physics_interpolation()
	camera._process(0.001)
	check(camera.focus.distance_to(focus) / 0.001 < 0.5, "静止满蓄发射时镜头起步速度连续")
	for frame in 6:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		player.reset_physics_interpolation()
		camera._process(1.0 / 60.0)
	check(camera._ricochet_camera.pitch_offset < -2.5, "发射前段保留压低视角，角度晚于距离舒展")
	var pitch := camera._ricochet_camera.pitch_offset
	session.set_combat_frozen(true)
	camera._process(0.5)
	check(camera._ricochet_camera.pitch_offset == pitch, "交接期间升级冻结保持进度")
	session.set_combat_frozen(false)
	for frame in 30:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		player.reset_physics_interpolation()
		camera._process(1.0 / 60.0)
	check(is_zero_approx(camera._ricochet_camera.pitch_offset) and is_equal_approx(camera._orbit_offset().length(), camera.distance), "交接完成恢复基础镜头")
	await ready_full(true)
	var previous_velocity: Vector3 = camera._ricochet_camera.get("focus_velocity")
	focus = camera.focus
	body.release_charge()
	body.advance(0.001, Vector3.ZERO, false)
	player.reset_physics_interpolation()
	camera._process(0.001)
	check(((camera.focus - focus) / 0.001).distance_to(previous_velocity) < 0.7, "边走边蓄力发射继承镜头的实际运动速度")
	body.cancel(true)
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "满蓄挤压中可以发射")
	body.advance(0.5, Vector3.ZERO, false)
	camera._process(0.01)
	camera._process(0.04)
	var pulse_pose := camera.global_transform
	var lens := Vector2(1.0 - camera._ricochet_camera.distance_scale, camera._ricochet_camera.pitch_offset)
	var lens_velocity: Vector2 = camera._ricochet_camera.get("_lens_velocity")
	body.release_charge()
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(pulse_pose), "挤压未结束时发射保留当前距离、角度和轻震")
	body.advance(0.001, Vector3.ZERO, false)
	player.reset_physics_interpolation()
	camera._process(0.001)
	var after := Vector2(1.0 - camera._ricochet_camera.distance_scale, camera._ricochet_camera.pitch_offset)
	check(absf((after.x - lens.x) / 0.001 - lens_velocity.x) < 0.05 and absf((after.y - lens.y) / 0.001 - lens_velocity.y) < 0.5, "挤压中的镜头距离与角度速度也连续交接")
	var cancelled_pose := camera.global_transform
	body.cancel(true)
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(cancelled_pose), "交接中取消不切换取景")
	check(body.begin_charge(Vector3.RIGHT), "交接中取消后可重新蓄力")
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(cancelled_pose), "交接中重按蓄力继承当前取景")
	body.cancel(true)
	await ready_full()
	body.release_charge()
	var within_bounds := true
	for frame in 35:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		player.reset_physics_interpolation()
		camera._process(1.0 / 60.0)
		var view := Basis.looking_at(-camera._orbit_offset(), Vector3.UP)
		var offset := camera.focus - camera._target_point()
		within_bounds = within_bounds and Vector2(offset.dot(view.x), offset.dot(view.y)).length() / camera._short_side_span() <= settings.max_offset_ratio + 0.0001
	check(body.bounce_count >= 1, "交接期间仍发生真实墙面反弹")
	check(within_bounds, "交接及转向的合计构图保持偏移上限")
	body.cancel(true)
	settings.set("charge_release_handoff_enabled", false)
	settings.charge_focus_enabled = false
	settings.charge_staging_enabled = false

func direction_checks() -> void:
	await reset()
	var screen := ColorRect.new()
	var shader := ShaderMaterial.new()
	shader.shader = load("res://shaders/post/post_process.gdshader")
	screen.material = shader
	world.add_child(screen)
	camera.post_process = screen
	camera._process(0.0)
	var presentation = load("res://scripts/player/charge_presentation.gd").new()
	if not "direction_focus_enabled" in presentation:
		check(false, "满蓄需要独立的方向清晰通道")
		presentation.free()
		return
	presentation.player = player
	presentation.enabled = true
	presentation.direction_focus_enabled = true
	world.add_child(presentation)
	await settle(3)
	presentation.set_process(false)
	check(body.begin_charge(Vector3.RIGHT), "方向聚焦使用真实蓄力")
	body.advance(0.4, Vector3.ZERO, false)
	presentation.advance(0.1, 0.1)
	check(is_zero_approx(float(screen.material.get_shader_parameter("charge_direction_amount"))), "未满蓄不提前柔化场景")
	body.advance(0.1, Vector3.ZERO, false)
	presentation.advance(0.1, 0.1)
	var amount: float = screen.material.get_shader_parameter("charge_direction_amount")
	check(amount > 0.5, "满蓄渐入方向聚焦")
	var route_start: Vector2 = screen.material.get_shader_parameter("charge_route_start")
	var route_end: Vector2 = screen.material.get_shader_parameter("charge_route_end")
	check(route_end.x > route_start.x, "世界瞄准方向正确投影到屏幕通道")
	body.aim(Vector3.FORWARD)
	presentation.advance(0.02, 0.02)
	var rotated_end: Vector2 = screen.material.get_shader_parameter("charge_route_end")
	check(rotated_end.distance_to(route_end) > 0.05, "满蓄瞄准转向更新清晰通道")
	var direction_before := body.direction
	camera._yaw_offset_degrees = 90.0
	camera._process(0.0)
	presentation.advance(0.0, 0.0)
	check(body.direction == direction_before and screen.material.get_shader_parameter("charge_route_end") != rotated_end, "Q/E 只改变通道投影，保留世界瞄准")
	session.set_combat_frozen(true)
	var frozen: float = screen.material.get_shader_parameter("charge_direction_amount")
	presentation.advance(0.3, 0.3)
	check(is_equal_approx(float(screen.material.get_shader_parameter("charge_direction_amount")), frozen), "升级冻结保持方向聚焦")
	session.set_combat_frozen(false)
	body.aim(Vector3.BACK)
	direction_before = body.direction
	check(body.release_charge(), "方向聚焦不阻挡发射")
	presentation.advance(0.0, 0.0)
	var expected_end := camera.unproject_position(player.global_position + Vector3.UP * 0.05 + direction_before * presentation.direction_focus_length) / get_root().get_visible_rect().size
	check(Vector2(screen.material.get_shader_parameter("charge_route_end")).distance_to(expected_end) < 0.001, "松手前最后一次转向使用真实发射方向")
	check(is_equal_approx(float(screen.material.get_shader_parameter("charge_direction_amount")), frozen), "松手当帧不切掉柔化效果")
	presentation.advance(0.05, 0.05)
	check(float(screen.material.get_shader_parameter("charge_direction_amount")) > 0.0, "发射后方向聚焦有柔和尾段")
	for frame in 40: presentation.advance(1.0 / 60.0, 1.0 / 60.0)
	check(is_zero_approx(float(screen.material.get_shader_parameter("charge_direction_amount"))) and not presentation.is_processing(), "尾段结束释放方向聚焦与逐帧工作")
	check(body.direction == direction_before, "表现不改变真实出射方向")
	presentation.free()
	screen.queue_free()
	body.cancel(true)
	camera._yaw_offset_degrees = 0.0
	await settle(3)
