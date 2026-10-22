extends SceneTree

const CAMERA := preload("res://scripts/camera/follow_camera.gd")
const SETTINGS_PATH := "res://scripts/ui/camera_settings_page.gd"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var probe = CAMERA.new()
	check("follow_enabled" in probe, "Camera exposes follow and edge scrolling modes")
	probe.free()
	check(ResourceLoader.exists(SETTINGS_PATH), "Shared camera settings are available in menus")
	if failures.is_empty():
		await motion_checks()
		await settings_checks()
	print(JSON.stringify({"suite":"camera_edge_pan", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func motion_checks() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var target := Node3D.new()
	world.add_child(target)
	var camera = CAMERA.new()
	camera.target = target
	camera.dof_enabled = false
	world.add_child(camera)
	camera.set_process(false)
	camera.set_world_rect(Rect2(-16, -16, 32, 32))
	camera.snap_to_target()
	var before: Vector3 = camera.focus
	camera.follow_enabled = false
	check(camera.focus == before and camera.anchor == before, "Unlocking retains the current view")
	var mouse := InputEventMouseMotion.new()
	mouse.position = root.get_visible_rect().get_center()
	mouse.global_position = mouse.position
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	target.position = Vector3(8, 4, 7)
	target.reset_physics_interpolation()
	camera._process(0.5)
	check(camera.focus.is_equal_approx(before), "Walking and jumping do not move an unlocked camera")
	var viewport := Rect2(20, 30, 1000, 700)
	var center := viewport.get_center()
	check(camera.edge_pan_input(center, viewport) == Vector2.ZERO, "The screen center does not scroll")
	check(camera.edge_pan_input(Vector2(1019, 380), viewport).x > 0.9, "The right edge scrolls right")
	check(camera.edge_pan_input(Vector2(21, 380), viewport).x < -0.9, "The left edge scrolls left")
	check(camera.edge_pan_input(Vector2(520, 31), viewport).y < -0.9, "The upper edge scrolls forward")
	check(camera.edge_pan_input(Vector2(520, 729), viewport).y > 0.9, "The lower edge scrolls backward")
	check(camera.edge_pan_input(Vector2(1021, 380), viewport) == Vector2.ZERO, "A cursor outside the viewport cannot scroll")
	check(camera.edge_pan_input(Vector2(21, 31), viewport).length() <= 1.0001, "Corner scrolling has the same maximum speed as cardinal scrolling")
	for angle in [0.0, 90.0, 135.0, 270.0]:
		camera.yaw_degrees = angle
		camera.anchor = before
		camera.focus = before
		camera._apply_transform()
		var right: Vector3 = camera.global_basis.x
		camera._advance_edge_pan(0.05, Vector2(1019, 380), viewport)
		var motion: Vector3 = camera.anchor - before
		check(motion.normalized().dot(right) > 0.999, "Edge scrolling follows the current Q/E view")
		camera._advance_edge_pan(100.0, Vector2(1019, 31), viewport)
		check(camera.anchor.x >= camera.bounds_min.x and camera.anchor.x <= camera.bounds_max.x and camera.anchor.z >= camera.bounds_min.y and camera.anchor.z <= camera.bounds_max.y, "Large steps and rotated corners remain inside map bounds")
	var blocker := Node.new()
	blocker.add_to_group(&"gameplay_input_blockers")
	world.add_child(blocker)
	check(not camera._can_edge_pan(), "Settings and other management screens suppress edge input")
	blocker.free()
	camera.anchor = before
	camera.focus = before
	camera.follow_enabled = true
	camera._process(0.05)
	var destination: Vector3 = camera._clamp_to_bounds(camera._target_point())
	check(camera.focus.distance_to(destination) < before.distance_to(destination) and camera.focus.distance_to(destination) > 0.1, "Relocking smoothly returns toward the player")
	camera._process(5.0)
	check(camera.focus.distance_to(destination) < camera.dead_zone + 0.01, "Follow mode tracks the player again")
	world.free()
	await process_frame

func settings_checks() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	root.add_child(world)
	for index in 12: await process_frame
	var settings = world.get_node("GameSettingsUI")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	settings.open_menu()
	settings.select_page(3)
	var page = settings._camera_page
	check(page.visible and settings._tabs[3].text == "镜头", "In-game settings include a camera page")
	page.follow_toggle.button_pressed = false
	check(not camera.follow_enabled, "The follow checkbox changes the real gameplay camera immediately")
	camera._bind_ricochet_camera()
	check(camera._ricochet_camera == null, "Unlocked mode does not bind player-driven charge or flight framing")
	var player := world.get_node("Player") as Player
	player.set_physics_process(false)
	var body := player.body_ricochet
	var previous_state: PlayerRicochet.State = body.state
	body.state = PlayerRicochet.State.CHARGING
	camera.anchor = camera._clamp_to_bounds(camera.focus + Vector3(3, 0, 3))
	camera.focus = camera.anchor
	camera._apply_transform()
	var cursor := camera.get_viewport().get_visible_rect().get_center() + Vector2(120, 40)
	var actual: Variant = Plane(Vector3.UP, player.global_position.y).intersects_ray(camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
	var aimed: Variant = camera.project_charge_aim(cursor, player.global_position.y)
	check(actual is Vector3 and aimed is Vector3 and actual.distance_to(aimed) < 0.001, "Charge aiming uses the actual unlocked view without recentering on the player")
	body.state = PlayerRicochet.State.FLYING
	var flight_focus: Vector3 = camera.focus
	camera._process(0.2)
	check(camera.focus.is_equal_approx(flight_focus), "Real-player flight cannot pull the unlocked camera toward the player")
	body.state = previous_state
	var manual_focus: Vector3 = camera.focus
	world.get_node("MapEffects")._update_bounds()
	check(camera.focus.is_equal_approx(manual_focus), "Refreshing map bounds does not silently relock an unlocked camera")
	page.speed_input.value = 17.0
	check(is_equal_approx(camera.edge_pan_speed, 17.0), "Camera scroll speed is adjustable")
	page.follow_speed_input.value = 9.0
	page.follow_lag_input.value = 2.5
	check(is_equal_approx(camera.follow_max_speed, 9.0) and is_equal_approx(camera.follow_max_lag, 2.5), "Follow comfort speed and the safe lag distance are adjustable in settings")
	page.config_path = "D:/.codexfile/work/camera-edge-pan-20261019/camera.cfg"
	page.save_enabled = true
	check(page.save_settings() == OK, "Camera preferences can be saved independently of graphics")
	var saved := ConfigFile.new()
	saved.load(page.config_path)
	check(not saved.has_section_key("camera", "follow_enabled"), "Follow mode is temporary and is not saved separately")
	camera.follow_enabled = true
	camera.edge_pan_speed = 12.0
	camera.follow_max_speed = 10.0
	camera.follow_max_lag = 3.0
	page.load_settings()
	check(camera.follow_enabled and is_equal_approx(camera.edge_pan_speed, 17.0) and is_equal_approx(camera.follow_max_speed, 9.0) and is_equal_approx(camera.follow_max_lag, 2.5), "Loading numeric camera preferences does not change the current follow mode")
	var config := ConfigFile.new()
	config.set_value("camera", "follow_enabled", false)
	config.set_value("camera", "edge_pan_speed", -100)
	config.save(page.config_path)
	page.load_settings()
	check(camera.follow_enabled and camera.edge_pan_speed >= 2.0, "Legacy follow preferences are ignored and negative pan speed is rejected")
	page.save_enabled = false
	settings.close_menu()
	camera.set_process(false)
	camera.snap_to_target()
	camera.follow_max_speed = 0.1
	camera._bind_ricochet_camera()
	body.state = PlayerRicochet.State.CHARGING
	body._charge_age = 0.25
	var speed_limited := true
	for index in 12:
		var previous := camera.focus
		camera._process(1.0 / 60.0)
		speed_limited = speed_limited and camera.focus.distance_to(previous) <= 0.1 / 60.0 + 0.0001
	check(camera._ricochet_camera.active and speed_limited, "The real charge-feedback path also obeys the follow speed limit inside the safe distance")
	body.cancel(true)
	camera.snap_to_target()
	camera.follow_max_speed = 9.0
	camera.set_process(true)
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_Y
	toggle.keycode = KEY_Y
	toggle.pressed = true
	Input.parse_input_event(toggle)
	Input.flush_buffered_events()
	check(not camera.follow_enabled, "Y reaches the real World camera through the unhandled gameplay input pipeline")
	var release := toggle.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.parse_input_event(toggle)
	Input.flush_buffered_events()
	check(camera.follow_enabled, "A second fresh Y press restores follow in actual gameplay input")
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	var startup = world.get_node("WorldMainMenu")
	startup.open_menu()
	for index in 20: await process_frame
	check(startup.menu._camera_page != null, "The embedded main menu exposes the same camera settings")
	startup.menu._camera_page.follow_toggle.button_pressed = false
	check(not camera.follow_enabled, "Main-menu settings can unlock the prepared gameplay camera")
	startup.menu._camera_page.follow_toggle.button_pressed = true
	check(camera.follow_enabled, "Main-menu camera settings update the already prepared World")
	world.free()
	await process_frame
	await process_frame
