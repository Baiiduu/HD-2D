extends "res://tests/test_ricochet_camera.gd"

func settings_checks() -> void:
	if not "charge_staging_enabled" in settings:
		check(false, "蓄力需要独立的分段运镜配置")
		return
	await super.settings_checks()
	var formal := load("res://data/combat/scenes/world/player/ricochet_camera.tres")
	var city := load("res://data/combat/scenes/city/player/ricochet_camera.tres")
	check(formal.get("charge_staging_enabled") and not city.get("charge_staging_enabled"), "分段运镜只由 World 独立启用")
	await staged_camera_checks()
	await presentation_checks()

func staged_camera_checks() -> void:
	settings.charge_focus_enabled = true
	settings.set("charge_staging_enabled", true)
	settings.charge_full_shake_enabled = true
	await reset()
	player.movement_camera = camera
	var cursor := Vector2(890, 490)
	camera.focus -= Vector3(0.4, 0.0, 0.0)
	camera._apply_transform()
	var entry_aim: Vector3 = Plane(Vector3.UP, player.global_position.y).intersects_ray(camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
	check(body.begin_charge(Vector3.RIGHT), "分段运镜使用真实蓄力")
	var aim: Vector3 = camera.call("project_charge_aim", cursor, player.global_position.y)
	check(entry_aim.distance_to(aim) < 0.001, "起手瞄准保留走路时的镜头余量")
	var original := camera.global_transform
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(original), "起手零时间接住现有镜头")
	for frame in 15:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		camera._process(1.0 / 60.0)
	var feedback := camera._ricochet_camera
	check(float(feedback.get("pitch_offset")) < -0.5 and absf(feedback.framing.x) > 0.001, "中段同时压低视角与横向划弧")
	var mid_distance := camera._orbit_offset().length()
	check(mid_distance < camera.distance, "中段推进人物")
	check(aim.distance_to(camera.call("project_charge_aim", cursor, player.global_position.y)) < 0.001, "分段运镜不带偏鼠标地面瞄准")
	for frame in 16:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		camera._process(1.0 / 60.0)
	for frame in 30: camera._process(1.0 / 60.0)
	check(absf(feedback.framing.x) < 0.0001 and float(feedback.get("pitch_offset")) < -3.0, "满蓄横移收住并保持低角度")
	var held := camera.global_transform
	for frame in 20: camera._process(1.0 / 60.0)
	check(camera.global_transform.is_equal_approx(held), "满蓄保持稳定，不反复播放挤压")
	check(camera.pitch_degrees == 25.414 and camera.fov == 28.0 and camera.distance == 15.0, "分段运镜不回写基础镜头")
	body.cancel(true)
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(held), "取消从当前完整姿态接续")
	camera._process(0.04)
	var returning := camera.global_transform
	check(body.begin_charge(Vector3.RIGHT), "回位中可重新蓄力")
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(returning), "快速重按继承角度和位置，不只继承距离")
	body.cancel(true)
	for frame in 30: camera._process(1.0 / 60.0)
	check(is_zero_approx(float(feedback.get("pitch_offset"))) and not feedback.active, "收尾完全恢复日常构图")
	settings.set("charge_staging_enabled", false)
	settings.charge_focus_enabled = false

func presentation_checks() -> void:
	var audio := GameAudio.new()
	audio.player = player
	audio.session = session
	audio.load_local_mix = false
	audio.music_volume_db = -4.0
	world.add_child(audio)
	var weather = load("res://scripts/world/weather.gd").new()
	weather.rain_audio_enabled = false
	weather.wind_audio_enabled = false
	weather.player = player
	var dressing := Node3D.new()
	world.add_child(dressing)
	var plants := MultiMeshInstance3D.new()
	plants.name = "grass_fixture"
	plants.multimesh = MultiMesh.new()
	plants.multimesh.mesh = QuadMesh.new()
	var plant_material := ShaderMaterial.new()
	plant_material.shader = load("res://shaders/environment/vegetation_wind.gdshader")
	plants.multimesh.mesh.material = plant_material
	dressing.add_child(plants)
	weather.dressing = dressing
	world.add_child(weather)
	var screen := ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/post/post_process.gdshader")
	screen.material = material
	world.add_child(screen)
	camera.post_process = screen
	camera._process(0.0)
	var presentation = load("res://scripts/player/charge_presentation.gd").new()
	presentation.player = player
	presentation.weather = weather
	presentation.audio = audio
	presentation.enabled = true
	world.add_child(presentation)
	await settle(3)
	presentation.set_process(false)
	check(not presentation.is_processing() and Engine.time_scale == 1.0, "闲置表现停止更新，默认不改变战斗时间")
	check(body.begin_charge(Vector3.RIGHT), "场景反馈由真实蓄力启动")
	body.advance(0.25, Vector3.ZERO, false)
	presentation.advance(0.15, 0.15)
	var level: float = presentation.level
	check(level > 0.2 and level < 1.0, "半蓄反馈按真实进度增强")
	check(float(screen.material.get_shader_parameter("charge_focus_amount")) > 0.2, "后处理接收人物周围的聚焦权重")
	check(float(weather._rain_material.get_shader_parameter("charge_pull")) > 0.0, "局部雨丝接收聚拢气流")
	check(float(plant_material.get_shader_parameter("charge_pull")) > 0.0, "真实地编材质接收聚拢气流")
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")) < -4.0, "音乐在原音量上叠加临时退让")
	audio.mix.set_bus_gain(&"Music", -2.0)
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")) < -6.0, "本机混音改变时仍保留临时退让")
	weather._apply()
	check(float(weather._rain_material.get_shader_parameter("charge_pull")) > 0.0, "天气重新应用后仍保留蓄力气流")
	check(float(plant_material.get_shader_parameter("charge_pull")) > 0.0, "地编材质重新登记后保留聚拢气流")
	var previous_post: ShaderMaterial = screen.material
	screen.material = previous_post.duplicate()
	presentation.advance(0.0, 0.0)
	check(is_zero_approx(float(previous_post.get_shader_parameter("charge_focus_amount"))) and float(screen.material.get_shader_parameter("charge_focus_amount")) > 0.2, "后处理替换后清理旧材质并续接当前聚焦")
	session.set_combat_frozen(true)
	presentation.advance(0.4, 0.4)
	check(is_equal_approx(presentation.level, level), "升级冻结保持场景反馈进度")
	session.set_combat_frozen(false)
	body.cancel(true)
	for frame in 60: presentation.advance(1.0 / 60.0, 1.0 / 60.0)
	check(is_zero_approx(presentation.level) and not presentation.is_processing(), "取消后平滑清理场景反馈并停止闲置工作")
	check(is_zero_approx(float(screen.material.get_shader_parameter("charge_focus_amount"))) and is_zero_approx(float(weather._rain_material.get_shader_parameter("charge_pull"))), "取消后清除聚焦和气流")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), -6.0), "取消恢复基础音量与本机混音之和")
	presentation.full_slow_enabled = true
	check(body.begin_charge(Vector3.RIGHT), "慢动作对照由同一蓄力触发")
	body.advance(0.5, Vector3.ZERO, false)
	presentation.advance(0.01, 0.01)
	check(Engine.time_scale < 1.0 and Engine.time_scale > 0.0, "可选满蓄慢动作短暂缩放真实时间")
	check(camera.charge_unscaled_time, "可选慢动作期间相机独立使用真实时间")
	presentation.advance(0.2, 0.2)
	check(Engine.time_scale == 1.0, "慢动作按真实时间恢复")
	presentation.advance(0.2, 0.2)
	check(Engine.time_scale == 1.0, "保持满蓄不会重复触发慢动作")
	body.cancel(true)
	Engine.time_scale = 0.8
	check(body.begin_charge(Vector3.RIGHT), "已有时间比例仍可蓄力")
	body.advance(0.5, Vector3.ZERO, false)
	presentation.advance(0.01, 0.01)
	check(is_equal_approx(Engine.time_scale, 0.8 * presentation.full_slow_scale), "慢动作基于已有时间比例")
	presentation.advance(0.2, 0.2)
	check(is_equal_approx(Engine.time_scale, 0.8), "结束恢复进入前的时间比例")
	body.cancel(true)
	Engine.time_scale = 1.0
	check(body.begin_charge(Vector3.RIGHT), "刚满即释放可启动慢动作对照")
	body.advance(0.5, Vector3.ZERO, false)
	body.release_charge()
	check(Engine.time_scale < 1.0, "满蓄边沿先于表现更新时仍触发一次")
	session.set_combat_frozen(true)
	presentation.advance(0.01, 0.01)
	check(Engine.time_scale == 1.0 and not camera.charge_unscaled_time, "升级冻结立即释放全局慢动作所有权")
	session.set_combat_frozen(false)
	body.cancel(true)
	check(body.begin_charge(Vector3.RIGHT), "时间接管用例可开始")
	body.advance(0.5, Vector3.ZERO, false)
	presentation.advance(0.01, 0.01)
	Engine.time_scale = 0.6
	presentation.reset()
	check(is_equal_approx(Engine.time_scale, 0.6), "其它系统接管时间后不被蓄力恢复覆盖")
	Engine.time_scale = 1.0
	body.cancel(true)
	presentation.reset()
	check(Engine.time_scale == 1.0 and is_zero_approx(presentation.level), "重置清理完整反馈")
	body.cancel(true)
	check(body.begin_charge(Vector3.RIGHT), "慢动作退出用例可开始蓄力")
	body.advance(0.5, Vector3.ZERO, false)
	presentation.advance(0.01, 0.01)
	presentation.free()
	check(Engine.time_scale == 1.0, "退出节点不会遗留全局慢动作")
	check(not camera.charge_unscaled_time, "退出还原相机时间通路")
	dressing.queue_free()
	weather.queue_free()
	audio.queue_free()
	screen.queue_free()
	body.cancel(true)
	await settle(3)
