extends SceneTree

const PARAMETERS := ["wet_surface_enabled", "wet_surface_minimum", "wet_surface_coverage",
	"wet_surface_patch_size", "wet_surface_roughness", "wet_surface_reflectivity",
	"wet_surface_ripple_strength", "wet_surface_ripple_speed", "wet_surface_grass_response"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ", message)

func frames(count := 8) -> void:
	for index in count: await physics_frame
	await process_frame

func light_state(world: Node3D) -> Array:
	var states: Array = []
	for light: Light3D in world.find_children("*", "Light3D", true, false):
		states.append([light.get_instance_id(), light.global_transform, light.visible,
			light.light_color, light.light_energy, light.light_specular, light.light_cull_mask, light.shadow_enabled])
	return states

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var protected := ["res://data/world/world_terrain.tres", "res://data/world/world_surface.res",
		"res://data/world/spawn_paint_palette.tres", "res://shaders/water/water.gdshader"]
	var hashes := {}
	for path in protected: hashes[path] = FileAccess.get_sha256(path)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("VisualSample").follow_weather = false
	root.add_child(world)
	current_scene = world
	await frames(30)
	var art: ArtDirection = world.get_node("MapEffects/ArtDirection")
	var terrain: Terrain = world.get_node("Homestead")
	var material := terrain.top_material
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var weather := world.get_node("MapEffects/Weather")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	world.get_node("Player").set_physics_process(false)
	camera.set_process(false)
	camera.distance = 29.0
	camera._yaw_offset_degrees = 45.0
	camera._yaw_target_degrees = 45.0
	camera.snap_to_target()
	var pose := camera.global_transform
	var lens := [camera.fov, camera.distance, camera.pitch_degrees, camera.focus_height, camera.dof_amount]
	var generated := [terrain._generated, world.get_node("GroundDressing")._generated, terrain.surface_canvas]
	var layout := [terrain.data.heights.duplicate(), terrain.data.biomes.duplicate(), terrain.data.overlays.duplicate(), terrain.data.paints.duplicate()]
	var audio_and_rain := [weather.enabled, weather.rain_volume_db, weather.wind_volume_db,
		weather.ground_rain_enabled, weather.ground_splash_size, weather.ground_splash_density, weather.ground_splash_strength]
	var independent := [sample.surface_normals_enabled, sample.character_normals_enabled,
		sample.grass_variation_enabled, sample.grass_variation_strength, sample.grass_variation_size,
		world.get_node("GroundDressing").stable_shadows, world.get_node("GroundDressing").ground_sheen]
	var values := {}
	for property in PARAMETERS: values[property] = art.get(property)
	check(art.wet_surface_enabled and material.get_shader_parameter("ground_directional_reflection_strength") == 0.0, "Formal ground keeps wet lamp reflections without directional glare")
	check(art.wet_surface_grass_response < 0.1, "Grass has a restrained wet response")
	for style in [0, 1, 2, 3, 0]:
		sample.style = style
		await frames()
		check(material.get_shader_parameter("ground_directional_reflection_strength") == 0.0, "Style preserves the directional-only reflection choice")
		var lights := light_state(world)
		for enabled in [false, true]:
			art.wet_surface_enabled = enabled
			await frames()
			check(light_state(world) == lights, "Wet film toggle preserves every actual light and shadow")
			for property in PARAMETERS:
				check(material.get_shader_parameter(property) == art.get(property), "The actual terrain material receives " + property)
			check([terrain._generated, world.get_node("GroundDressing")._generated, terrain.surface_canvas] == generated, "Wet film toggle does not rebuild terrain, paint canvas or foliage")
		art.wet_surface_enabled = values["wet_surface_enabled"]
		await frames()
		check(camera.global_transform == pose and [camera.fov, camera.distance, camera.pitch_degrees, camera.focus_height, camera.dof_amount] == lens, "Style and wet film preserve the custom camera and depth of field")
		check([weather.enabled, weather.rain_volume_db, weather.wind_volume_db,
			weather.ground_rain_enabled, weather.ground_splash_size, weather.ground_splash_density, weather.ground_splash_strength] == audio_and_rain, "Style and wet film preserve the existing weather switch, rain feedback and sound")
		check(PARAMETERS.all(func(property): return art.get(property) == values[property]), "Style preserves independently selected wet surface settings")
	check([terrain.data.heights, terrain.data.biomes, terrain.data.overlays, terrain.data.paints] == layout, "Terrain and authored brush IDs stay unchanged")
	check([sample.surface_normals_enabled, sample.character_normals_enabled,
		sample.grass_variation_enabled, sample.grass_variation_strength, sample.grass_variation_size,
		world.get_node("GroundDressing").stable_shadows, world.get_node("GroundDressing").ground_sheen] == independent, "Normal maps, meadow settings and fixed clump shadows stay unchanged")
	var clock: float = material.get_shader_parameter("rain_clock")
	await frames(12)
	check(float(material.get_shader_parameter("rain_clock")) > clock, "Wet ripples still advance when the formal weather switch is disabled")
	art.wet_surface_ripple_speed = 0.0
	art.wet_surface_ripple_strength = 0.0
	art.wet_surface_coverage = 0.0
	await frames()
	for property in ["wet_surface_ripple_speed", "wet_surface_ripple_strength", "wet_surface_coverage"]:
		check(material.get_shader_parameter(property) == 0.0, "Inspector zero values reach the renderer without being reset")
	var catalog = load("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(world)
	for property in PARAMETERS:
		check(entries.any(func(entry): return entry.object == art and entry.property == property and entry.category == "视觉"), "Wet surface parameter is indexed: " + property)
	for path in protected: check(FileAccess.get_sha256(path) == hashes[path], "Protected source is unchanged: " + path)
	print("Wet surface: ", checks, " checks; ", failures.size(), " failures")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	await create_timer(0.15).timeout
	world.free()
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)
