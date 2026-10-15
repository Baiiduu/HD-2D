extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func frames(count: int) -> void:
	for index in count:
		await physics_frame
	await process_frame

func verify_scene(scene_path: String, weather_path: String, dressing_path: String) -> void:
	var world := (load(scene_path) as PackedScene).instantiate()
	root.add_child(world)
	await frames(20)
	var player := world.get_node("Player") as Player
	var weather := world.get_node(weather_path)
	var dressing := world.get_node(dressing_path)
	weather.set_process(false)
	weather._blink_paths.clear()
	weather._write_blink_airflow()
	check(weather.player == player and player.blink_travelled.is_connected(weather._on_blink_travelled), scene_path + ": character is connected")
	check(not weather._vegetation.is_empty(), scene_path + ": existing vegetation materials are connected")
	if weather._vegetation.is_empty():
		world.queue_free()
		await frames(2)
		return
	var plant: ShaderMaterial = weather._vegetation[0]
	var visible_heights_valid := true
	for material: ShaderMaterial in weather._vegetation:
		var texture := material.get_shader_parameter("sprite_texture") as Texture2D
		var image := texture.get_image()
		var visible_height := float(image.get_used_rect().size.y) / float(image.get_height())
		visible_heights_valid = visible_heights_valid and is_equal_approx(float(material.get_shader_parameter("visible_height_uv")), visible_height)
	check(visible_heights_valid, "Bending uses actual visible plant height rather than transparent texture padding")
	var rain: ShaderMaterial = weather._rain_material
	var slant: Vector2 = rain.get_shader_parameter("slant")
	var wind: float = plant.get_shader_parameter("wind_strength")
	var start := player.global_position
	var end := start + Vector3(1.3, 0.0, -0.6)
	player.blink_travelled.emit(start, end)
	check(weather._blink_paths.size() == 1 and int(plant.get_shader_parameter("blink_path_count")) == 1 and int(rain.get_shader_parameter("blink_path_count")) == 1, "One completed blink reaches both plants and rain")
	var starts: PackedVector4Array = rain.get_shader_parameter("blink_path_starts")
	var ends: PackedVector4Array = plant.get_shader_parameter("blink_path_ends")
	check(Vector3(starts[0].x, starts[0].y, starts[0].z).is_equal_approx(start) and Vector3(ends[0].x, ends[0].y, ends[0].z).is_equal_approx(end), "Shaders receive exact world-space endpoints")
	weather._advance_blink_airflow(0.1)
	starts = rain.get_shader_parameter("blink_path_starts")
	check(is_equal_approx(starts[0].w, 0.1), "Transient age advances independently of weather wind time")
	check(rain.get_shader_parameter("slant") == slant and is_equal_approx(plant.get_shader_parameter("wind_strength"), wind), "Local impulse leaves the global weather wind unchanged")
	player.global_position += Vector3(0.0, 0.0, 0.4)
	weather._advance_blink_airflow(0.02)
	starts = rain.get_shader_parameter("blink_path_starts")
	check(Vector3(starts[0].x, starts[0].y, starts[0].z).is_equal_approx(start), "Impulse remains at its original path when the character moves on")
	weather.blink_plants_enabled = false
	weather._write_blink_airflow()
	check(int(plant.get_shader_parameter("blink_path_count")) == 0 and int(rain.get_shader_parameter("blink_path_count")) == 1, "Plant response can be disabled independently")
	weather.blink_plants_enabled = true
	weather.blink_rain_enabled = false
	weather._write_blink_airflow()
	check(int(plant.get_shader_parameter("blink_path_count")) == 1 and int(rain.get_shader_parameter("blink_path_count")) == 0, "Rain response can be disabled independently")
	weather.blink_rain_enabled = true
	weather._advance_blink_airflow(3.0)
	check(weather._blink_paths.is_empty() and int(plant.get_shader_parameter("blink_path_count")) == 0 and int(rain.get_shader_parameter("blink_path_count")) == 0, "Expired impulses are removed from both shaders")
	player.blink_travelled.emit(start, start)
	check(weather._blink_paths.is_empty(), "Zero-length paths do not create NaNs or impulses")
	weather.wind_enabled = false
	weather.weather_mode = 0
	await frames(2)
	player.blink_travelled.emit(start, end)
	check(int(plant.get_shader_parameter("blink_path_count")) == 1 and is_zero_approx(float(plant.get_shader_parameter("wind_strength"))), "Plants still respond in calm sunny weather")
	check(not weather._rain.emitting, "A blink does not start rain in sunny weather")
	for index in 12:
		player.blink_travelled.emit(start + Vector3(index, 0, 0), end + Vector3(index, 0, 0))
	check(weather._blink_paths.size() == weather.MAX_BLINK_PATHS, "Repeated impulses stay within the shader's bounded capacity")
	dressing._rebuild()
	check(int(weather._vegetation[0].get_shader_parameter("blink_path_count")) == weather.MAX_BLINK_PATHS, "Rebuilt vegetation retains active impulses")
	var anchored := true
	for batch: MultiMeshInstance3D in dressing.find_children("*", "MultiMeshInstance3D", true, false):
		if not batch.multimesh.mesh.material is ShaderMaterial or batch.multimesh.instance_count == 0:
			continue
		anchored = anchored and batch.multimesh.use_custom_data
		# Dummy rendering does not retain GPU instance buffers; verify their values in the render run.
		if DisplayServer.get_name() != "headless":
			anchored = anchored and batch.multimesh.get_instance_custom_data(0).r > 0.0
	check(anchored, "Vegetation provides its actual root height to the shader")
	world.queue_free()
	await frames(2)

func _run() -> void:
	await verify_scene("res://scenes/world/world.tscn", "MapEffects/Weather", "GroundDressing")
	await verify_scene("res://scenes/previews/four_realms.tscn", "Weather", "World/GroundDressing")
	print(JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
