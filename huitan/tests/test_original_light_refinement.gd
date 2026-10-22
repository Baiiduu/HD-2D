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

func light_state(world: Node3D) -> Array:
	var moon: DirectionalLight3D = world.get_node("MapEffects/Moon")
	var env: Environment = world.get_node("MapEffects/WorldEnvironment").environment
	var post: ShaderMaterial = world.get_node("MapEffects/PostProcess/Screen").material
	return [moon.light_color, moon.light_energy, moon.rotation_degrees, moon.shadow_opacity,
		moon.light_angular_distance, env.ambient_light_color, env.ambient_light_energy,
		env.ambient_light_source, env.tonemap_exposure, env.adjustment_contrast,
		env.adjustment_saturation, env.volumetric_fog_density,
		post.get_shader_parameter("split_toning"), post.get_shader_parameter("vignette_strength"),
		world.get_node("MapEffects/AtmosphericLight").surface_energy]

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var protected := ["res://data/visual/spawn_original.tres", "res://data/visual/spawn_original_render.tres",
		"res://data/visual/spawn_lumina_day.tres", "res://data/visual/spawn_lumina_rain.tres",
		"res://data/visual/spawn_lumina_night.tres", "res://data/world/spawn_terrain.tres"]
	var hashes := {}
	for path in protected: hashes[path] = FileAccess.get_sha256(path)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("VisualSample").follow_weather = false
	world.get_node("VisualSample").fog_post_enabled = false
	root.add_child(world)
	current_scene = world
	await frames(30)
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var moon: DirectionalLight3D = world.get_node("MapEffects/Moon")
	var art: ArtDirection = world.get_node("MapEffects/ArtDirection")
	var accents := world.get_node("MapEffects/AtmosphericLight")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	var terrain: Terrain = world.get_node("Homestead")
	var dressing := world.get_node("GroundDressing")
	var weather := world.get_node("MapEffects/Weather")
	world.get_node("Player").set_physics_process(false)
	camera.set_process(false)
	camera.snap_to_target()
	var pose := camera.global_transform
	var lens := [camera.fov, camera.distance, camera.pitch_degrees, camera.focus_height, camera.dof_amount]
	var common := [sample.color_palette, dressing.color_palette, sample.grass_variation_strength,
		sample.grass_variation_size, sample.surface_normals_enabled, sample.character_normals_enabled,
		dressing.grass_density, dressing.flower_density, dressing.layered_growth_strength,
		dressing.leaf_normals_enabled, dressing.ground_sheen]
	var generated := [terrain._generated, dressing._generated, world.get_node("HouseSite/Home/Geometry"), world.get_node("TrainingHut/Geometry")]
	check(sample.style == 0 and sample.original_light_refinement_enabled, "Formal map starts with the requested refined original style")
	var refined := light_state(world)
	var rain := [weather.weather_mode, weather.rain_intensity, weather.rain_amount]
	sample.original_light_refinement_enabled = false
	await frames()
	var baseline := light_state(world)
	check(is_equal_approx(moon.light_energy, 1.65) and is_equal_approx(art.exposure, 0.86) and is_equal_approx(moon.shadow_opacity, 0.72), "Disabled refinement restores the reviewed original parameters")
	var other_styles := {}
	for style in [1, 2, 3]:
		sample.style = style
		await frames()
		other_styles[style] = light_state(world)
	for enabled in [true, false, true, false, true]:
		sample.original_light_refinement_enabled = enabled
		for style in [0, 1, 2, 3, 0]:
			sample.style = style
			await frames()
			check(light_state(world) == ((refined if enabled else baseline) if style == 0 else other_styles[style]), "Repeated toggles and Style round trips restore the correct rendered light")
			check(not accents.enabled and accents._rays.all(func(ray): return not ray.is_visible_in_tree())
				and accents._distant_rays.all(func(ray): return not ray.is_visible_in_tree())
				and accents._beams.all(func(beam): return not beam.is_visible_in_tree())
				and not accents._fog.is_visible_in_tree(), "Style and refinement toggles keep decorative lighting disabled")
		check(camera.global_transform == pose and [camera.fov, camera.distance, camera.pitch_degrees, camera.focus_height, camera.dof_amount] == lens, "Refinement preserves the camera and DOF")
		check([terrain._generated, dressing._generated, world.get_node("HouseSite/Home/Geometry"), world.get_node("TrainingHut/Geometry")] == generated, "Refinement does not rebuild vegetation, geometry or collisions")
		check([sample.color_palette, dressing.color_palette, sample.grass_variation_strength,
			sample.grass_variation_size, sample.surface_normals_enabled, sample.character_normals_enabled,
			dressing.grass_density, dressing.flower_density, dressing.layered_growth_strength,
			dressing.leaf_normals_enabled, dressing.ground_sheen] == common, "Refinement preserves palettes, plant layers and independent normal maps")
		check([weather.weather_mode, weather.rain_intensity, weather.rain_amount] == rain, "Original refinement preserves rain settings")
	check(is_equal_approx(moon.light_energy, 2.85) and is_equal_approx(art.ambient_energy, 0.85) and is_equal_approx(art.exposure, 1.08), "Rendered main light and visible shadow fill are brighter")
	check(moon.light_color.is_equal_approx(Color(1,0.71,0.4)) and is_equal_approx(moon.rotation_degrees.y,-112.0) and is_equal_approx(moon.rotation_degrees.x,-28.0), "Original warm key colour and direction are retained")
	check(moon.shadow_opacity > 0.72 and moon.light_angular_distance < 1.4 and art.moon_energy / art.ambient_energy > 1.65 / 0.6, "The physical key/fill ratio and shadow boundary contrast increase")
	check(art.ambient_color.b > art.ambient_color.r and not art.hemisphere_fill_enabled, "Shadow fill is cool and retains the original environment model")
	check(accents.follow_global_direction and accents._surface_direction.is_equal_approx(-moon.global_basis.z.normalized()), "Warm ground accents and the main light cast shadows in the same world direction")
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		camera._yaw_offset_degrees = yaw
		camera._yaw_target_degrees = yaw
		camera._clear_yaw_motion()
		camera.snap_to_target()
		await frames()
		check(light_state(world) == refined, "Camera rotation does not rotate world lighting")
		var active := 0
		for ray: SpotLight3D in accents._rays:
			if not ray.visible or ray.light_energy <= 0.001: continue
			active += 1
			check((-ray.global_basis.z).is_equal_approx(-moon.global_basis.z), "The actual warm spotlight axis follows the main light at every camera yaw")
		check(active == 0, "Camera rotation does not reactivate decorative spotlights")
	var catalog = load("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(world)
	check(entries.any(func(entry): return entry.property == "original_light_refinement_enabled" and entry.category == "视觉" and entry.common), "The reversible refinement toggle is indexed")
	check(entries.any(func(entry): return entry.object == sample.original_light_preset and entry.category == "视觉"), "Persistent refinement settings are indexed")
	for path in protected: check(FileAccess.get_sha256(path) == hashes[path], "Baseline source remains unchanged: " + path)
	print("Original light refinement: ", checks, " checks; ", failures.size(), " failures")
	world.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
