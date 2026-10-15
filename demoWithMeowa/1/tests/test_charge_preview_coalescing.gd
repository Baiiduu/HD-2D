extends "res://tests/test_aim_path_preview.gd"

const PROBE := preload("res://tests/fixtures/counting_charge_effect.gd")
var effect
var camera: Camera3D
var report: Dictionary = {}

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func fixture() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	terrain = Terrain.new()
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i(-12, -12), Vector2i(24, 24))
	terrain.data = data
	world.add_child(terrain)
	session = SESSION.new()
	session.name = "WavePrototype"
	session.terrain = terrain
	session.phase = WavePrototype.Phase.BATTLE
	world.add_child(session)
	session._attack_root = Node3D.new()
	session.add_child(session._attack_root)
	player = Player.new()
	player.name = "Player"
	player.animations = load("res://assets/meowa/player/animations.tres")
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.ricochet_rules.bounce_speed_retention = 1.0
	player.action_visuals = PlayerActionVisuals.new()
	player.sword_rules = PlayerSwordRules.new()
	player.sword_rules.audio_enabled = false
	player.bounds = Rect2(-18, -18, 36, 36)
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.position.y = 0.75
	player.add_child(sprite)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.06592
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	player.add_child(collision)
	session.player = player
	world.add_child(player)
	body = player.body_ricochet
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.cull_mask = 1 << 19 # compare preview pixels without animated terrain/actors
	world.add_child(camera)
	camera.position = Vector3(0, 6, 8)
	camera.look_at(Vector3(0, 0, -1.5))
	camera.current = true
	player.movement_camera = camera
	effect = PROBE.new()
	player.add_child(effect)
	body._charge_effect = effect
	for node in effect.find_children("*", "GeometryInstance3D", true, false): node.layers = 1 << 19
	await settle()
	navigation.build(terrain, 0.32, [player.get_rid()])
	await reset()
	player.set_process(false)

func gameplay_state() -> Array:
	return [player.global_transform, player.velocity, PhysicsServer3D.body_get_collision_mask(player.get_rid()),
		body._settings, body._crowd, body._push_wave, player.sword._age,
		player.sword._since_strike, player.current_health]

func coalescing_checks() -> void:
	var target := enemy(Vector3(0.15, 0, -1.8))
	target.set_process(false)
	target.reset_physics_interpolation()
	var wall := box(Vector3(0, 0.6, -4), Vector3(8, 1.2, 0.02))
	await settle()
	player.action_visuals.set("coalesce_charge_preview", true)
	check(body.begin_charge(Vector3.RIGHT), "new mode starts a real charge")
	effect.set("displays", 0)
	effect.set("predictions", 0)
	for step in 8:
		body.aim(Vector3.FORWARD if step == 7 else Vector3.RIGHT)
		player.sprite.pixel_size = 0.016 + step * 0.0001
		player.action_visuals.charge_radius_pixels = 32.0 + step
		player.action_visuals.preview_distance = 3.0 + step * 0.3
		player.action_visuals.preview_bounces = step % 2
		player.action_visuals.preview_line_width_pixels = 1.0 + step * 0.1
		player.action_visuals.preview_color = Color(0.2, 0.3 + step * 0.03, 0.8)
		player.action_visuals.preview_opacity = 0.3 + step * 0.02
		wall.position.z = -4.0 + step * 0.05
		body.advance(0.05, Vector3.ZERO, false)
	check(effect.get("displays") == 8 and effect.get("predictions") == 0, "eight physics displays submit no hidden prediction or manual process flush")
	var expected := AimPathData.new()
	var before := gameplay_state()
	await effect.processed
	body.predict_path(query, expected, player.action_visuals.preview_distance, player.action_visuals.preview_bounces)
	var expected_target := player.sword.preview_target(expected)
	check(effect.get("predictions") == 1 and not effect.get("_preview_pending"), "one actual process consumes all eight pending updates exactly once")
	if effect._route.segments != expected.segments or effect._route.contacts != expected.contacts or effect._target_enemy != expected_target:
		print("LATEST_DIFF ", JSON.stringify({"expected_segments": expected.segments, "actual_segments": effect._route.segments, "expected_contacts": expected.contacts, "actual_contacts": effect._route.contacts, "expected_target": str(expected_target), "actual_target": str(effect._target_enemy)}))
	check(effect._route.segments == expected.segments and effect._route.contacts == expected.contacts and effect._target_enemy == expected_target, "flush uses the latest complete direction/world/route/target")
	check(is_equal_approx(effect._pixel, player.sprite.pixel_size * player.sprite.global_basis.x.length()) and is_equal_approx(effect._radius, player.action_visuals.charge_radius_pixels * effect._pixel), "latest native pixel scale and radius reach the flush")
	check(effect._aim._width == player.action_visuals.preview_line_width_pixels and effect._aim._opacity == player.action_visuals.preview_opacity and effect._aim._line_material.get_shader_parameter("tint") == player.action_visuals.preview_color, "latest line width/tint/opacity reach the renderer")
	check(gameplay_state() == before and target.health == target.max_health, "process prediction preserves body/mask/snapshots/sword clocks/HP")
	await effect.processed
	check(effect.get("predictions") == 1, "a second display frame without dirty input does not predict again")
	body.advance(0.0, Vector3.ZERO, false)
	var route_before: Array = effect._route.segments.duplicate(true)
	session.set_combat_frozen(true)
	await effect.processed
	check(effect.get("predictions") == 1 and effect._route.segments == route_before and effect.get("_preview_pending"), "freeze preserves the displayed route while retaining one pending latest request")
	session.set_combat_frozen(false)
	await effect.processed
	check(effect.get("predictions") == 2 and not effect.get("_preview_pending"), "resume refreshes the pending current world once")
	var pre_full_age: float = effect._age
	body.advance(0.4, Vector3.ZERO, false)
	check(body.charge_fraction == 1.0 and effect._full_at == pre_full_age, "full charge locks the original zero-delta event timestamp before actual process age advances")
	await effect.processed
	var expected_flash: float = maxf(0.0, 1.0 - (effect._age - pre_full_age) / 0.18)
	check(is_equal_approx(effect._ring_material.get_shader_parameter("full_flash"), expected_flash), "first visible full-charge flash keeps the legacy event timing")
	body.advance(0.0, Vector3.ZERO, false)
	var predictions: int = effect.get("predictions")
	body.cancel(true)
	await process_frame
	check(effect.get("predictions") == predictions and not effect.visible and not effect.get("_preview_pending") and effect._route.segments.is_empty(), "cancel before flush synchronously clears pending route and cannot resurrect it")
	check(body.begin_charge(Vector3.FORWARD), "reused effect starts another charge")
	body.advance(0.4, Vector3.ZERO, false)
	predictions = effect.get("predictions")
	check(body.release_charge(), "release remains independent of whether a preview was ever drawn")
	await process_frame
	check(effect.get("predictions") == predictions and not effect.visible and not effect.get("_preview_pending"), "release before flush creates zero delayed predictions")
	body.cancel(true)

func preview_pixels(mode: bool) -> Image:
	await reset()
	player.set_process(false)
	player.action_visuals.set("coalesce_charge_preview", mode)
	body.begin_charge(Vector3.FORWARD)
	body.advance(0.4, Vector3.ZERO, false)
	await effect.processed
	session.set_combat_frozen(true)
	effect._age = 0.25
	effect._full_at = -1.0
	effect.call("_sync_visuals", 0.0)
	effect._aim._process(0.0)
	await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	session.set_combat_frozen(false)
	body.cancel(true)
	return pixels

func actual_flight(mode: bool) -> PackedVector3Array:
	await reset()
	player.set_process(false)
	player.action_visuals.set("coalesce_charge_preview", mode)
	body.begin_charge(Vector3.FORWARD)
	body.advance(0.4, Vector3.ZERO, false)
	await effect.processed
	check(body.release_charge(), "A/B real launch succeeds")
	var points := PackedVector3Array()
	for tick in 600:
		if not body.flying: break
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		points.append(player.global_position)
	return points

func run() -> void:
	check(load("res://data/player/action_visuals.tres").coalesce_charge_preview, "formal visual resource enables render-coalesced previews")
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await fixture()
	await coalescing_checks()
	var old_pixels := await preview_pixels(false)
	var new_pixels := await preview_pixels(true)
	check(not old_pixels.is_empty() and old_pixels.get_data() == new_pixels.get_data(), "old/new visible preview pixels are identical for one frozen render snapshot")
	var old_flight := await actual_flight(false)
	var new_flight := await actual_flight(true)
	check(not old_flight.is_empty() and old_flight == new_flight, "old/new actual release trajectories match every 60 Hz step on the same actors/world")
	report = {"checks": checks, "failures": failures, "display_requests": 8, "new_flushes": 1,
		"pixel_bytes": old_pixels.get_data().size(), "flight_steps": old_flight.size()}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--output="): continue
		var output := argument.trim_prefix("--output=")
		var result := FileAccess.open(output, FileAccess.WRITE)
		if result: result.store_string(JSON.stringify(report, "\t"))
		old_pixels.save_png(output.get_basename() + "-old.png")
		new_pixels.save_png(output.get_basename() + "-new.png")
	print(JSON.stringify(report))
	body.cancel(true)
	world.queue_free()
	await settle()
	print("Late charge preview: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
