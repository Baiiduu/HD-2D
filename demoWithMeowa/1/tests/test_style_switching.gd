extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func frames(count := 8) -> void:
	for index in count: await physics_frame
	await process_frame

func key(code: Key, echo := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	event.shift_pressed = shift
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.physical_keycode = code
	Input.parse_input_event(release)

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await frames(20)
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	var wave: WavePrototype = world.get_node("WavePrototype")
	var terrain: Terrain = world.get_node("Homestead")
	var dressing := world.get_node("GroundDressing")
	var home := world.get_node("HouseSite/Home")
	var training := world.get_node("TrainingHut")
	var weather := world.get_node("MapEffects/Weather")
	var player: Player = world.get_node("Player")
	player.set_physics_process(false)
	camera.set_process(false)
	camera._yaw_offset_degrees = 45.0
	camera._yaw_target_degrees = 45.0
	camera.distance = 29.0
	camera.snap_to_target()
	weather.blink_plant_strength = 0.21
	weather.rain_volume_db = -23.0
	weather.ground_splash_size = 0.19
	weather.ground_splash_density = 1.1
	weather.ground_splash_strength = 0.57
	var camera_pose := camera.global_transform
	var geometry := home.get_node("Geometry")
	var training_geometry := training.get_node("Geometry")
	var flora: Node3D = dressing._generated
	var terrain_mesh: Node3D = terrain._generated
	var sites := [home.get_parent().position, training.position]
	var density: float = dressing.grass_density
	var state_before: Dictionary = world.get_node("LoadoutUI").state.export_state().duplicate(true)
	for next in [2, 3, 0, 1, 2, 3, 0, 1]:
		var sheen := 0.0 if next % 2 == 0 else 0.12
		dressing.ground_sheen = sheen
		key(KEY_R)
		await frames()
		check(sample.style == next, "R cycles to style %d once" % next)
		check(camera.global_transform == camera_pose and camera.distance == 29.0 and camera._yaw_offset_degrees == 45.0, "Style preserves custom camera and current rotation")
		check(home.get_parent().position == sites[0] and training.position == sites[1], "Style preserves layout")
		check(home.get_node("Geometry") == geometry and training.get_node("Geometry") == training_geometry, "Style preserves buildings and physical collisions")
		check(dressing._generated == flora and dressing.grass_density == density and terrain._generated == terrain_mesh, "Style does not rebuild plants or terrain")
		check(weather.blink_plant_strength == 0.21 and weather.rain_volume_db == -23.0, "Style preserves independently adjusted blink and audio")
		check(dressing.ground_sheen == sheen and is_equal_approx(terrain.top_material.get_shader_parameter("grass_sheen"), sheen), "Style preserves disabled and custom grass sheen")
		check(weather.ground_splash_size == 0.19 and weather.ground_splash_density == 1.1 and weather.ground_splash_strength == 0.57, "Style preserves independent rain-impact tuning")
		check(wave.phase == WavePrototype.Phase.READY and world.get_node("LoadoutUI").state.export_state() == state_before, "Style preserves combat and save state")
	key(KEY_R, true)
	key(KEY_R, false, true)
	await frames()
	check(sample.style == 1, "Held R and modified R do not cycle")
	sample.runtime_switch_enabled = false
	key(KEY_R)
	await frames()
	check(sample.style == 1, "Runtime switching can be disabled")
	sample.runtime_switch_enabled = true
	var edit := LineEdit.new()
	root.add_child(edit)
	edit.grab_focus()
	await frames(2)
	key(KEY_R)
	await frames()
	check(sample.style == 1, "Typing R does not switch visuals")
	edit.free()
	var menu := Node.new()
	root.add_child(menu)
	menu.add_to_group(&"gameplay_input_blockers")
	key(KEY_R)
	await frames()
	check(sample.style == 1, "Management and growth input blockers keep R")
	menu.free()
	player.global_position = wave.global_position
	player.reset_physics_interpolation()
	check(wave.start_run(), "Battle starts with the current wave setup")
	wave.set_combat_frozen(true)
	var generation: int = wave._generation
	var pending: int = wave._spawn_queue.size()
	key(KEY_R)
	await frames()
	check(sample.style == 2 and wave.phase == WavePrototype.Phase.BATTLE and wave._generation == generation and wave._spawn_queue.size() == pending, "R preserves the active battle and scheduled spawns")
	wave.retreat()
	sample.style = 1
	await frames()
	wave._set_phase(WavePrototype.Phase.RESULT)
	key(KEY_R)
	await frames()
	check(sample.style == 2 and wave.phase == WavePrototype.Phase.RESULT and wave.retry_key == KEY_T, "R switches in result without retrying")
	var pixels := sample.pixel_art_enabled
	key(KEY_F7)
	key(KEY_F8)
	await frames()
	check(sample.style == 2 and sample.pixel_art_enabled == pixels, "Function keys remain unused")
	# 独立素材开关恢复原图，R 不改变这项选择。
	sample.pixel_art_enabled = false
	await frames()
	check(home.plaster_texture_override == null and not terrain.paint_palette.brushes[0].texture.resource_path.begins_with(sample.PIXEL_SAMPLE_PATH), "Independent material toggle restores source art")
	key(KEY_R)
	await frames()
	check(not sample.pixel_art_enabled and home.plaster_texture_override == null, "Style preserves source-art selection")
	sample.pixel_art_enabled = true
	await frames()
	check(home.plaster_texture_override.resource_path.begins_with(sample.PIXEL_SAMPLE_PATH), "Independent material toggle reapplies pixel art")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	world.free()
	await frames(2)
	await create_timer(0.15).timeout
	print(JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
