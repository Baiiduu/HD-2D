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

func atmosphere_state(world: Node) -> Array:
	var env: Environment = world.get_node("MapEffects/WorldEnvironment").environment
	var post: ShaderMaterial = world.get_node("MapEffects/PostProcess/Screen").material
	return [env.fog_light_color, env.fog_depth_begin, env.fog_depth_end, env.fog_depth_curve,
		env.fog_density, env.fog_height_density, env.volumetric_fog_enabled,
		env.volumetric_fog_density, env.volumetric_fog_length, env.volumetric_fog_sky_affect,
		env.glow_intensity, env.glow_hdr_threshold, env.glow_bloom,
		post.get_shader_parameter("vignette_strength"), post.get_shader_parameter("vignette_radius"),
		post.get_shader_parameter("split_toning"), post.get_shader_parameter("shadow_lift"),
		post.get_shader_parameter("lumina_grade_enabled")]

func light_state(world: Node) -> Array:
	var moon: DirectionalLight3D = world.get_node("MapEffects/Moon")
	var env: Environment = world.get_node("MapEffects/WorldEnvironment").environment
	return [moon.light_color, moon.light_energy, moon.rotation_degrees, moon.shadow_opacity,
		moon.light_angular_distance, env.ambient_light_color, env.ambient_light_energy,
		env.ambient_light_source, env.tonemap_exposure, env.adjustment_brightness,
		env.adjustment_contrast, env.adjustment_saturation]

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("VisualSample").follow_weather = false
	root.add_child(world)
	current_scene = world
	await frames(30)
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var art: ArtDirection = world.get_node("MapEffects/ArtDirection")
	var env: Environment = world.get_node("MapEffects/WorldEnvironment").environment
	var post: ShaderMaterial = world.get_node("MapEffects/PostProcess/Screen").material
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	var terrain: Terrain = world.get_node("Homestead")
	var dressing := world.get_node("GroundDressing")
	var weather := world.get_node("MapEffects/Weather")
	world.get_node("Player").set_physics_process(false)
	camera.set_process(false)
	camera.distance = 29.0
	camera._yaw_offset_degrees = 45.0
	camera._yaw_target_degrees = 45.0
	camera.snap_to_target()
	var pose := camera.global_transform
	var lens := [camera.fov, camera.distance, camera.pitch_degrees, camera.focus_height, camera.dof_amount]
	var generated := [terrain._generated, dressing._generated, world.get_node("HouseSite/Home/Geometry"), world.get_node("TrainingHut/Geometry")]
	var terrain_state := [terrain.data.heights.duplicate(), terrain.data.biomes.duplicate(), terrain.data.overlays.duplicate()]
	var foliage := [dressing.grass_density, dressing.flower_density, dressing.cluster_size, dressing.minimum_spacing, dressing.layered_growth_strength]
	var independent := [sample.color_palette, dressing.color_palette, sample.grass_variation_strength,
		sample.grass_variation_size, sample.surface_normals_enabled, sample.character_normals_enabled,
		dressing.leaf_normals_enabled, dressing.ground_sheen, weather.rain_volume_db, weather.wind_volume_db,
		weather.ground_splash_size, weather.ground_splash_density, weather.ground_splash_strength]
	var save_state: Dictionary = world.get_node("LoadoutUI").state.export_state().duplicate(true)
	check(sample.fog_post_enabled, "The formal scene starts with the reversible atmosphere sample")
	check(env.fog_mode == Environment.FOG_MODE_DEPTH, "Distance controls use depth fog")
	for style in [0, 1, 2, 3]:
		sample.style = style
		sample.fog_post_enabled = false
		await frames()
		var before := atmosphere_state(world)
		var lighting := light_state(world)
		var rain := [weather.weather_mode, weather.rain_amount, weather.rain_intensity]
		for enabled in [true, false, true]:
			sample.fog_post_enabled = enabled
			await frames()
			check(light_state(world) == lighting, "Atmosphere toggle retains actual main light, fill, exposure and contrast")
			check([weather.weather_mode, weather.rain_amount, weather.rain_intensity] == rain, "Atmosphere toggle retains actual rain settings")
			check([terrain._generated, dressing._generated, world.get_node("HouseSite/Home/Geometry"), world.get_node("TrainingHut/Geometry")] == generated, "Atmosphere toggle does not regenerate geometry or plants")
			check(camera.global_transform == pose and [camera.fov, camera.distance, camera.pitch_degrees, camera.focus_height, camera.dof_amount] == lens, "Atmosphere toggle preserves custom camera and depth of field")
			if enabled:
				check(env.fog_depth_begin > before[1] and env.volumetric_fog_density < before[7], "The near viewing range has later distance fog and thinner volume fog")
				check(env.glow_bloom == 0.0 and env.glow_hdr_threshold >= before[11], "Low brightness surfaces stop participating in bloom")
				check(float(post.get_shader_parameter("vignette_strength")) < before[13] and float(post.get_shader_parameter("vignette_radius")) > before[14], "The vignette is lighter and farther from the subject")
				check(bool(post.get_shader_parameter("lumina_grade_enabled")) == (style > 0), "Original retains its own grading model")
			else:
				check(atmosphere_state(world) == before, "Disabling restores every atmosphere and post processing binding for this Style")
	check([terrain.data.heights, terrain.data.biomes, terrain.data.overlays] == terrain_state, "Terrain painting remains unchanged")
	check([dressing.grass_density, dressing.flower_density, dressing.cluster_size, dressing.minimum_spacing, dressing.layered_growth_strength] == foliage, "Foliage distribution remains unchanged")
	check([sample.color_palette, dressing.color_palette, sample.grass_variation_strength,
		sample.grass_variation_size, sample.surface_normals_enabled, sample.character_normals_enabled,
		dressing.leaf_normals_enabled, dressing.ground_sheen, weather.rain_volume_db, weather.wind_volume_db,
		weather.ground_splash_size, weather.ground_splash_density, weather.ground_splash_strength] == independent, "Independent palettes, normal maps, rain feedback and audio values survive")
	check(world.get_node("WavePrototype").phase == WavePrototype.Phase.READY and world.get_node("LoadoutUI").state.export_state() == save_state, "Combat and inventory remain unchanged")
	# Inspector controls must reach the renderer, including sub-millistep volume density.
	art.fog_curve = 1.4
	art.volumetric_density = 0.0007
	art.bloom_threshold = 1.3
	art.bloom_floor = 0.02
	art.vignette_radius = 1.05
	art.shadow_lift = Vector3(0.003, 0.006, 0.009)
	art.apply()
	check(is_equal_approx(env.fog_depth_curve, 1.4) and is_equal_approx(env.volumetric_fog_density, 0.0007), "Inspector fog tuning reaches Environment")
	check(is_equal_approx(env.glow_hdr_threshold, 1.3) and is_equal_approx(env.glow_bloom, 0.02), "Inspector bloom tuning reaches Environment")
	check(is_equal_approx(float(post.get_shader_parameter("vignette_radius")), 1.05) and post.get_shader_parameter("shadow_lift") == art.shadow_lift, "Inspector post tuning reaches the actual screen shader")
	sample.apply_style()
	await frames()
	var configured := atmosphere_state(world)
	for enabled in [false, true]:
		sample.value_sample_enabled = enabled
		await frames()
		check(atmosphere_state(world) == configured, "Value palette and light toggle preserves the atmosphere layer")
	sample.style = 0
	await frames()
	configured = atmosphere_state(world)
	for enabled in [false, true]:
		sample.original_light_refinement_enabled = enabled
		await frames()
		check(atmosphere_state(world) == configured, "Original light refinement preserves the atmosphere layer")
	var catalog = load("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(world)
	for property in ["fog_post_enabled", "fog_post_presets", "fog_curve", "bloom_threshold", "bloom_floor", "vignette_radius", "shadow_lift"]:
		check(entries.any(func(entry): return entry.property == property and entry.category == "视觉" and entry.common), "Atmosphere control is indexed: " + property)
	for preset in sample.fog_post_presets:
		check(entries.any(func(entry): return entry.object == preset and entry.category == "视觉"), "Persistent Style tuning resource is indexed")
	print("Fog and post: ", checks, " checks; ", failures.size(), " failures")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	await create_timer(0.15).timeout
	world.free()
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)
