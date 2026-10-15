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
	check(formal_settings != null and formal_settings.enabled and formal_settings == load("res://data/player/ricochet_camera.tres"), "正式地图默认接入共享弹射镜头反馈配置")
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(formal)
	for property in ["launch_lag_seconds", "lookahead_ratio", "bounce_inertia_seconds", "max_offset_ratio", "impact_shake_pixels"]:
		check(entries.any(func(item): return item.property == property and item.category == "视觉" and item.common), "视觉参数入口可调整：" + property)
	formal.get_node("LoadoutUI").save_enabled = false
	formal.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(formal)
	await settle(6)
	for audio in formal.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	formal.free()
	await settle()

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
	await settings_checks()
	world.queue_free()
	await settle()
	print("Ricochet camera: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
