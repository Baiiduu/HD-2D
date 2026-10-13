extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func frames(count := 8) -> void:
	for index in count: await physics_frame
	await process_frame

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	root.add_child(world)
	current_scene = world
	await frames(20)
	var dynamics: EnvironmentDynamics = world.get_node("EnvironmentDynamics")
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var weather := world.get_node("MapEffects/Weather")
	var dressing := world.get_node("GroundDressing")
	var terrain: Terrain = world.get_node("Homestead")
	var camera := world.get_node("MapEffects/Camera3D")
	var player := world.get_node("Player")
	player.set_physics_process(false)
	camera.set_process(false)
	var camera_pose: Transform3D = camera.global_transform
	var generated: Node = dressing._generated
	var terrain_mesh: Node = terrain._generated
	var home_geometry: Node = world.get_node("HouseSite/Home/Geometry")
	var positions: Dictionary = {}
	for batch in dressing.find_children("*", "MultiMeshInstance3D", true, false):
		positions[batch.get_instance_id()] = batch.multimesh.buffer.duplicate()
	var baseline := [weather.wind_strength, weather.wind_speed, weather.rain_amount, weather.rain_intensity,
		weather.ground_splash_size, weather.ground_splash_density, weather.ground_splash_strength, dressing.ground_sheen]
	var state: Dictionary = world.get_node("LoadoutUI").state.export_state().duplicate(true)
	check(not dynamics._plants.is_empty(), "Existing grass and flower batches bind to the dynamics")
	check(dynamics._lights.size() == 6, "Three existing home lights and three reusable perimeter emitters are bound")
	if dynamics._plants.is_empty():
		print(JSON.stringify({"checks": checks, "failures": failures}))
		quit(1)
		return
	var plant: ShaderMaterial = dynamics._plants[0]
	var light: ShaderMaterial = dynamics._lights[0]
	check(plant.get_shader_parameter("ambient_dynamics_enabled") == true, "Dynamics are ready on the first frame")
	check(plant.get_shader_parameter("ambient_region_wind") == dynamics.region_wind, "Calm center and stronger perimeter have distinct wind weights")
	check(light.get_shader_parameter("ambient_region_fireflies") == dynamics.region_fireflies, "Light visibility uses spatial weights")
	check(plant.get_shader_parameter("ambient_core_bounds").is_equal_approx(Vector4(-16, 28.8, 32, 32)), "Region bounds come from the actual battle component")
	check(is_equal_approx(dynamics._current.z, 0.18), "Golden hour starts with sparse lights without pressing R")
	for lamp in dynamics.get_children():
		var local: Vector3 = terrain.to_local(lamp.global_position)
		var cell := terrain.data.world_to_cell(local)
		check(is_equal_approx(local.y, terrain.data.get_level(cell) * terrain.data.layer_height + dynamics.battle_firefly_height), "Perimeter lights sit above their actual terrace")
		check(not world.get_node("BattleArea").get_core_rect().has_point(Vector2(local.x, local.z)), "No new emitter occupies the battle center")
	var previous: Vector3 = dynamics._current
	sample.style = 3
	await frames(2)
	check(dynamics._current.z > previous.z and dynamics._current.z < 1.0, "Night lights fade in without jumping to full visibility")
	dynamics.set_process(false)
	dynamics._process(2.0)
	check(dynamics._current.z > 0.99 and dynamics._current.x < 0.51, "Night has clearer lights and gentler wind")
	check(dynamics._light_size > 1.79 and light.get_shader_parameter("ambient_firefly_size") > 1.79, "Night makes existing tiny lights slightly more legible")
	var clock: float = dynamics._clock
	dynamics._process(0.25)
	check(dynamics._clock > clock and dynamics._clock - clock < 0.25, "Wind tempo advances continuously at the night rate")
	sample.style = 2
	await frames()
	dynamics._process(3.0)
	check(dynamics._current.z < 0.05 and dynamics._current.x > 1.09, "Rain reduces light visibility and strengthens natural wind")
	check(absf(dynamics._light_size - 1.0) < 0.001, "Other periods return smoothly to the base particle size")
	check(weather.rain_amount == baseline[2] and weather.rain_intensity == baseline[3], "Rain amount and intensity are unchanged")
	check([weather.ground_splash_size, weather.ground_splash_density, weather.ground_splash_strength] == baseline.slice(4, 7), "Recent ground-impact settings remain intact")
	check(weather.wind_strength == baseline[0] and weather.wind_speed == baseline[1], "Existing wind controls remain independent")
	check(dressing.ground_sheen == baseline[7], "Disabled grass sheen stays disabled")
	weather.wind_enabled = false
	await frames()
	check(is_zero_approx(float(plant.get_shader_parameter("wind_strength"))), "Turning off natural wind still stops it")
	check(weather.blink_plants_enabled, "Blink airflow remains independent of natural wind")
	weather.wind_enabled = true
	sample.style = 0
	await frames()
	dynamics._process(3.0)
	check(dynamics._current.x > 0.99 and dynamics._current.z > 0.99, "Original lighting uses its own dynamic profile")
	var saved_profile: Vector4 = dynamics.region_wind
	dynamics.region_wind = Vector4(0.4, 0.3, 0.8, 0.7)
	await frames()
	check(plant.get_shader_parameter("ambient_region_wind") == dynamics.region_wind, "Region sliders update the existing material")
	dynamics.region_wind = saved_profile
	dynamics.enabled = false
	await frames()
	check(plant.get_shader_parameter("ambient_dynamics_enabled") == false and light.get_shader_parameter("ambient_dynamics_enabled") == false, "Disabling restores baseline shaders")
	check(not dynamics.get_child(0).visible, "Disabling hides only the added battle emitters")
	check(world.get_node("GreenLights/Courtyard").visible, "Original home light controls remain available")
	sample.style = 3
	await frames()
	dynamics._process(0.1)
	check(not dynamics.get_child(0).visible, "Style changes cannot re-enable disabled perimeter lights")
	dynamics.enabled = true
	await frames()
	world.get_node("MapEffects/ArtDirection").fireflies_enabled = false
	await frames()
	dynamics._process(0.1)
	check(not dynamics.get_child(0).visible and not world.get_node("GreenLights/Courtyard").visible, "The original global light switch remains effective")
	world.get_node("MapEffects/ArtDirection").fireflies_enabled = true
	await frames()
	var growth: Node = world.get_node("WavePrototype/RunGrowth")
	growth.set_process(false)
	world.get_node("WavePrototype").set_process(false)
	clock = dynamics._clock
	dynamics._process(0.2)
	check(dynamics._clock > clock, "Environment keeps running while combat nodes are frozen")
	check(dressing._generated == generated and terrain._generated == terrain_mesh and world.get_node("HouseSite/Home/Geometry") == home_geometry, "Profile changes preserve plants, terrain, geometry and collisions")
	var stable := true
	for batch in dressing.find_children("*", "MultiMeshInstance3D", true, false):
		stable = stable and positions[batch.get_instance_id()] == batch.multimesh.buffer
	check(stable, "Plant positions, sizes and random layout are unchanged")
	check(camera.global_transform == camera_pose, "The actual camera remains unchanged")
	check(world.get_node("LoadoutUI").state.export_state() == state, "Inventory and save data are unchanged")
	var catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var indexed := false
	for entry in catalog.collect(world):
		if entry.path == "EnvironmentDynamics" and entry.property == "style_fireflies":
			indexed = entry.category == "视觉" and entry.common
	check(indexed, "Dynamic profiles appear as common visual controls in the parameter hub")
	catalog.entries.clear()
	print(JSON.stringify({"checks": checks, "failures": failures}))
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	await create_timer(0.2).timeout
	world.queue_free()
	await frames(3)
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)
