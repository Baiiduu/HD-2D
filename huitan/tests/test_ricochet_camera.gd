extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0
var world: Node3D
var player: Player
var session: WavePrototype
var camera: FollowCamera
var body: PlayerRicochet
var settings := RicochetCameraSettings.new()

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 5) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func box(point: Vector3, size: Vector3) -> void:
	var block := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	block.add_child(collision)
	world.add_child(block)
	block.position = point

func reset() -> void:
	body.cancel(true)
	player.global_position = Vector3(0, 0.02, 0)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await settle(8)
	player.set_physics_process(false)
	player.reset_physics_interpolation()
	camera.snap_to_target()

func launch() -> void:
	check(body.begin_charge(Vector3.RIGHT), "可从地面蓄力")
	check(body.release_charge(), "真实弹射触发镜头时间线")

func motion_checks(enabled: bool) -> Array[Vector3]:
	settings.enabled = enabled
	await reset()
	launch()
	var path: Array[Vector3] = []
	var capped := true
	var small_shake := true
	var launch_lag := false
	var lead := false
	var recoil := false
	var preserves_lens := true
	var catches_bounce_velocity := false
	for frame in 72:
		var before_bounce := body.bounce_count
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		if enabled and body.bounce_count > before_bounce: catches_bounce_velocity = camera._ricochet_camera._velocity.x > 0.0
		player.reset_physics_interpolation()
		camera._process(1.0 / 60.0)
		path.append(player.global_position)
		var feedback := camera._ricochet_camera
		capped = capped and (feedback.framing + feedback.shake).length() <= settings.max_offset_ratio + 0.000001
		small_shake = small_shake and feedback.shake.length() * 800.0 <= settings.impact_shake_pixels + 0.0001
		launch_lag = launch_lag or feedback.framing.x < -0.001
		lead = lead or feedback.framing.x > 0.001
		recoil = recoil or not feedback.shake.is_zero_approx()
		preserves_lens = preserves_lens and camera.fov == 28.0 and camera.distance == 15.0 and camera.pitch_degrees == 25.414 and Engine.time_scale == 1.0
	check(body.bounce_count == 1, "真实胶囊撞墙并原路反弹")
	check(preserves_lens, "运镜不改变基础视野、距离、俯角或全局时间")
	check(capped, "新增构图与轻震合计保持偏移上限")
	check(small_shake, "屏幕轻震保持像素上限")
	check((launch_lag and lead and recoil) if enabled else (not launch_lag and not lead and not recoil), "开关控制起射滞后、前视与撞墙轻震")
	if enabled: check(catches_bounce_velocity, "人物原路折返时镜头接住原方向速度，避免立即反向")
	check(not camera._ricochet_camera.active and camera._ricochet_camera.framing == Vector2.ZERO, "结束后按时归位且无残留时间线")
	return path

func lifecycle_checks() -> void:
	settings.enabled = true
	await reset()
	launch()
	body.advance(0.1, Vector3.ZERO, false)
	player.reset_physics_interpolation()
	camera._process(0.1)
	var feedback := camera._ricochet_camera
	var age := feedback._age
	var framing := feedback.framing
	var pose := camera.global_transform
	session.set_combat_frozen(true)
	camera._process(0.2)
	check(feedback._age == age and feedback.framing == framing and camera.global_transform.is_equal_approx(pose), "升级冻结保留镜头时间线和构图")
	session.set_combat_frozen(false)
	var heading := body.direction
	camera._yaw_offset_degrees = 90.0
	camera._process(0.02)
	check(body.direction == heading and is_equal_approx(camera.global_basis.z.x, cos(deg_to_rad(camera.pitch_degrees))), "Q/E 朝向偏移可作用于反馈，不改变世界飞行方向")
	feedback._on_bounced(Vector3.ZERO, Vector3.LEFT)
	var impact_direction := feedback._impact_direction
	feedback._on_bounced(Vector3.ZERO, Vector3.FORWARD)
	check(feedback._impact_direction == impact_direction and feedback._impact_age == 0.0, "同帧窄角多次碰撞不反复叠加震动")
	settings.enabled = false
	camera._process(0.02)
	check(not feedback.active and camera._impact_offset == Vector3.ZERO, "关闭立即停止反馈，不残留轻震")
	settings.enabled = true
	camera._process(0.02)
	check(feedback.active, "飞行中开启对比开关可接续反馈")
	camera.ricochet_camera_settings = null
	feedback._on_bounced(Vector3.ZERO, Vector3.LEFT)
	camera._process(0.02)
	check(camera._ricochet_camera == null and not feedback.active, "移除配置时安全解绑，不残留反弹回调")
	camera.ricochet_camera_settings = settings
	camera._process(0.02)
	feedback = camera._ricochet_camera
	camera.snap_to_target()
	check(not feedback.active and camera.focus.is_equal_approx(camera._target_point()), "显式重置镜头清理惯性和构图")
	body.cancel(true)
	camera._yaw_offset_degrees = 0.0
	camera.snap_to_target()
	camera.set_world_rect(Rect2(-1, -1, 2, 2))
	player.global_position.x = 8.0
	player.reset_physics_interpolation()
	camera._process(0.1)
	check(camera.anchor.x >= camera.bounds_min.x and camera.anchor.x <= camera.bounds_max.x, "原地图边缘保护仍有效")
	camera.bounds_min = Vector2(-INF, -INF)
	camera.bounds_max = Vector2(INF, INF)

func settings_checks() -> void:
	var formal: Node = load("res://scenes/world/world.tscn").instantiate()
	var formal_settings: RicochetCameraSettings = formal.get_node("MapEffects/Camera3D").ricochet_camera_settings
	check(formal_settings != null and formal_settings.enabled and formal_settings == load("res://data/combat/scenes/world/player/ricochet_camera.tres"), "正式地图编辑器与运行时共用独立弹射镜头配置")
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(formal)
	for property in ["launch_lag_seconds", "lookahead_ratio", "bounce_inertia_seconds", "max_offset_ratio", "impact_shake_pixels", "impact_shot_curve", "impact_split_enabled", "impact_punch_pixels", "impact_punch_seconds", "charge_focus_enabled", "charge_zoom_ratio", "charge_onset_ratio", "charge_focus_seconds", "charge_release_seconds", "charge_cancel_seconds", "charge_full_shake_enabled", "charge_full_shake_pixels", "charge_full_shake_seconds"]:
		check(entries.any(func(item): return item.property == property and item.category == "视觉" and item.common), "视觉参数入口可调整：" + property)
	formal.get_node("LoadoutUI").save_enabled = false
	formal.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(formal)
	await settle(6)
	for audio in formal.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	formal.free()
	await settle()

func charge_checks() -> void:
	if not "charge_focus_enabled" in settings:
		check(false, "镜头配置需要独立的蓄力聚焦开关")
		return
	settings.enabled = true
	settings.set("charge_focus_enabled", true)
	player.ricochet_rules.full_charge_seconds = 0.5
	await reset()
	camera.focus -= Vector3(0.4, 0.0, 0.0)
	camera._apply_transform()
	var entry_pose := camera.global_transform
	check(body.begin_charge(Vector3.RIGHT), "蓄力聚焦使用真实人物状态")
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(entry_pose), "开始蓄力接住走路构图，零时间不跳变")
	var previous_distance := camera._orbit_offset().length()
	var monotonic := true
	for frame in 60:
		if frame < 30:
			player.position.x += 0.025
			player.reset_physics_interpolation()
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		camera._process(1.0 / 60.0)
		var actual := camera._orbit_offset().length()
		monotonic = monotonic and actual <= previous_distance + 0.00001
		previous_distance = actual
	check(monotonic and previous_distance < camera.distance * 0.95, "蓄力持续推近，满蓄有明确取景变化")
	check(camera.focus.distance_to(camera._target_point()) < 0.02, "边走边蓄力围绕当前人物聚焦，不追旧起点")
	var ratio: float = settings.get("charge_zoom_ratio")
	check(absf(previous_distance / camera.distance - (1.0 - ratio)) < 0.001, "满蓄取景受配置比例限制")
	var full_distance := previous_distance
	for frame in 20: camera._process(1.0 / 60.0)
	check(absf(camera._orbit_offset().length() - full_distance) < 0.002, "满蓄维持取景，不持续抽近或抖动")
	var heading := body.direction
	var rotated_distance := camera._orbit_offset().length()
	camera._yaw_offset_degrees = 45.0
	camera._process(0.0)
	check(body.direction == heading and is_equal_approx(camera._orbit_offset().length(), rotated_distance), "聚焦期间可旋转镜头，保持推近量及世界瞄准方向")
	var launch_distance := camera._orbit_offset().length()
	check(body.release_charge(), "松手立即发射，不等待运镜完成")
	camera._process(0.0)
	check(is_equal_approx(camera._orbit_offset().length(), launch_distance), "发射从已有推近量拉开，事件帧不重置距离")
	for frame in 20:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		player.reset_physics_interpolation()
		camera._process(1.0 / 60.0)
	check(is_equal_approx(camera._orbit_offset().length(), camera.distance), "发射拉开完成后恢复基础距离")
	check(camera._ricochet_camera.framing.length() > 0.001, "推近释放平滑接续既有飞行前视")
	check(camera.fov == 28.0 and camera.distance == 15.0 and camera.pitch_degrees == 25.414 and Engine.time_scale == 1.0, "运行时推近不改写编辑器基础镜头或游戏时间")
	camera._yaw_offset_degrees = 0.0
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "可重新开始蓄力")
	body.advance(0.3, Vector3.ZERO, false)
	camera._process(0.12)
	var cancelled_distance := camera._orbit_offset().length()
	var cancelled_focus := camera.focus
	body.cancel(true)
	camera._process(0.0)
	check(is_equal_approx(camera._orbit_offset().length(), cancelled_distance) and camera.focus.is_equal_approx(cancelled_focus), "取消时从当前距离与构图回位，事件帧不跳变")
	camera._process(0.04)
	check(camera._orbit_offset().length() > cancelled_distance and camera._orbit_offset().length() < camera.distance, "取消回位具有连续过渡")
	var repress_distance := camera._orbit_offset().length()
	check(body.begin_charge(Vector3.RIGHT), "回位中可以再次蓄力")
	camera._process(0.0)
	check(is_equal_approx(camera._orbit_offset().length(), repress_distance), "快速重按继承尚未回完的推近量")
	camera._process(0.05)
	var frozen_pose := camera.global_transform
	session.set_combat_frozen(true)
	camera._process(0.5)
	check(camera.global_transform.is_equal_approx(frozen_pose), "升级冻结同时保留蓄力聚焦状态")
	session.set_combat_frozen(false)
	body.cancel(true)
	for frame in 30: camera._process(1.0 / 60.0)
	check(not camera._ricochet_camera.active and is_equal_approx(camera._orbit_offset().length(), camera.distance), "取消回位结束释放镜头时间线")
	check(body.begin_charge(Vector3.RIGHT), "重置用例开始蓄力")
	body.advance(0.25, Vector3.ZERO, false)
	camera._process(0.1)
	camera.snap_to_target()
	check(is_equal_approx(camera._orbit_offset().length(), camera.distance), "显式镜头重置清除运行时推近量")
	camera._process(0.05)
	settings.enabled = false
	camera._process(0.02)
	check(not camera._ricochet_camera.active and is_equal_approx(camera._orbit_offset().length(), camera.distance), "关闭总开关不会遗留推近状态")
	body.cancel(true)
	settings.enabled = true
	settings.set("charge_focus_enabled", false)
	camera.snap_to_target()
	var world_profile := load("res://data/combat/scenes/world/configuration.tres") as SceneCombatConfiguration
	var city_profile := load("res://data/combat/scenes/city/configuration.tres") as SceneCombatConfiguration
	check(world_profile.ricochet_camera_settings.get("charge_focus_enabled") == true, "World 独立配置明确开启蓄力聚焦")
	check(is_equal_approx(world_profile.ricochet_camera_settings.charge_zoom_ratio, 0.12), "World 蓄力推近增强到百分之十二")
	check(is_equal_approx(world_profile.ricochet_camera_settings.charge_onset_ratio, 0.5), "World 起手先追向最大推近的一半")
	check(city_profile.ricochet_camera_settings.get("charge_focus_enabled") == false, "City 保留当前镜头表现")

func full_charge_checks() -> void:
	if not "charge_full_shake_enabled" in settings:
		check(false, "满蓄需要独立的单次定向轻震配置")
		return
	settings.charge_focus_enabled = true
	settings.set("charge_full_shake_enabled", true)
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "满蓄反馈使用实际蓄力状态")
	body.advance(0.49, Vector3.ZERO, false)
	camera._process(0.01)
	var feedback := camera._ricochet_camera
	check(feedback.shake.is_zero_approx(), "未满蓄时不提前震动")
	body.advance(0.02, Vector3.ZERO, false)
	camera._process(0.01)
	camera._process(0.025)
	var pulse := feedback.shake
	check(not pulse.is_zero_approx() and pulse.x > 0.0 and absf(pulse.y) < 0.000001, "刚满蓄时沿实际瞄准方向产生一次镜头反馈")
	check(pulse.length() * 800.0 <= float(settings.get("charge_full_shake_pixels")) + 0.001, "满蓄震动服从像素强度上限")
	var age: float = feedback.get("_full_shake_age")
	var pose := camera.global_transform
	session.set_combat_frozen(true)
	camera._process(0.3)
	check(feedback.get("_full_shake_age") == age and camera.global_transform.is_equal_approx(pose), "升级冻结暂停满蓄反馈的时间与位置")
	session.set_combat_frozen(false)
	var follows_heading := body.direction
	check(body.release_charge(), "满蓄震动中同样立即发射")
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(pose) and body.direction == follows_heading, "发射接住尚未结束的满蓄反馈，零时间不跳变或改方向")
	for frame in 20: camera._process(1.0 / 60.0)
	check(feedback.shake.is_zero_approx(), "发射后满蓄轻震按时收尾")
	body.cancel(true)
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "新一次蓄力可重新触发满蓄反馈")
	body.advance(0.5, Vector3.ZERO, false)
	camera._process(0.01)
	camera._process(0.025)
	check(not feedback.shake.is_zero_approx(), "第二次满蓄重新触发一次轻震")
	var cancel_pose := camera.global_transform
	body.cancel(true)
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(cancel_pose), "取消蓄力同样接住震动尾部，避免突然截断")
	for frame in 25: camera._process(1.0 / 60.0)
	check(not feedback.active and feedback.shake.is_zero_approx(), "取消后轻震与推近共同清理")
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "持续满蓄用例可开始")
	body.advance(0.5, Vector3.ZERO, false)
	camera._process(0.01)
	for frame in 60: camera._process(1.0 / 60.0)
	check(feedback.shake.is_zero_approx(), "持续按住满蓄不反复震动")
	check(body.release_charge(), "渲染采样前达到满蓄也能发射")
	body.cancel(true)
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "快速满蓄发射用例可开始")
	body.advance(0.5, Vector3.ZERO, false)
	check(body.release_charge(), "实际满蓄后不等待额外渲染帧即可发射")
	camera._process(0.025)
	check(not feedback.shake.is_zero_approx(), "刚满即松手时仍保留一次满蓄反馈")
	body.cancel(true)
	await reset()
	settings.set("charge_full_shake_enabled", false)
	check(body.begin_charge(Vector3.RIGHT), "独立开关对照用例可开始")
	body.advance(0.5, Vector3.ZERO, false)
	camera._process(0.025)
	check(feedback.shake.is_zero_approx() and camera._orbit_offset().length() < camera.distance, "关闭满蓄震动后仍保留蓄力推近")
	body.cancel(true)
	settings.charge_focus_enabled = false
	var profile := load("res://data/combat/scenes/world/configuration.tres") as SceneCombatConfiguration
	var city := load("res://data/combat/scenes/city/configuration.tres") as SceneCombatConfiguration
	check(profile.ricochet_camera_settings.get("charge_full_shake_enabled") == true, "World 明确开启满蓄反馈")
	check(city.ricochet_camera_settings.get("charge_full_shake_enabled") == false, "City 不自动加入满蓄反馈")

func run() -> void:
	root.size = Vector2i(1280, 800)
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	box(Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))
	box(Vector3(2, 0.8, 0), Vector3(0.1, 1.6, 4))
	session = SESSION.new()
	session.name = "WavePrototype"
	session.phase = WavePrototype.Phase.BATTLE
	world.add_child(session)
	player = Player.new()
	player.name = "Player"
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.minimum_launch_speed = 8.0
	player.ricochet_rules.maximum_launch_speed = 8.0
	# 固定镜头夹具的续航，不依赖正式弹射耗速的后续调参。
	player.ricochet_rules.flight_deceleration = 6.0
	player.ricochet_rules.bounce_speed_retention = 1.0
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
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
	camera.distance = 15.0
	camera.pitch_degrees = 25.414
	camera.fov = 28.0
	camera.horizontal_rotation_enabled = false
	camera.ricochet_camera_settings = settings
	world.add_child(camera)
	camera.set_process(false)
	camera._bind_ricochet_camera()
	body = player.body_ricochet
	await settle(10)
	var baseline := await motion_checks(false)
	var feedback := await motion_checks(true)
	check(baseline == feedback, "反馈开关不改变实际飞行路径、速度和反弹结果")
	await lifecycle_checks()
	await charge_checks()
	await full_charge_checks()
	await settings_checks()
	world.queue_free()
	await settle()
	print("Ricochet camera: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
