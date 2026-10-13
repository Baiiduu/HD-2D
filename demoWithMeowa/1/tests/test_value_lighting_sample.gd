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

func frames(count := 10) -> void:
	for index in count: await physics_frame
	await process_frame

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("VisualSample").follow_weather = false
	root.add_child(world)
	current_scene = world
	await frames(30)
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var profile := sample.value_sample_profile
	var art: ArtDirection = world.get_node("MapEffects/ArtDirection")
	var env: Environment = world.get_node("MapEffects/WorldEnvironment").environment
	var terrain: Terrain = world.get_node("Homestead")
	var dressing = world.get_node("GroundDressing")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	world.get_node("Player").set_physics_process(false)
	camera.set_process(false)
	camera.distance = 29.0
	camera._yaw_offset_degrees = 45.0
	camera._yaw_target_degrees = 45.0
	camera.snap_to_target()
	var pose := camera.global_transform
	var generated := [terrain._generated, dressing._generated, world.get_node("HouseSite/Home/Geometry"), world.get_node("TrainingHut/Geometry")]
	var terrain_values := [terrain.data.heights.duplicate(), terrain.data.biomes.duplicate(), terrain.data.overlays.duplicate()]
	var distribution := [dressing.grass_density, dressing.flower_density, dressing.cluster_size, dressing.minimum_spacing]
	var independent := [sample.grass_variation_strength, sample.grass_variation_size, sample.surface_normals_enabled, sample.character_normals_enabled, dressing.ground_sheen]
	var original_colors := profile.original_material_palette.grass.duplicate()
	for enabled in [false, true, false, true]:
		sample.value_sample_enabled = enabled
		await frames()
		check(sample.color_palette == (profile.material_palette if enabled else profile.original_material_palette), "Sample toggle selects the matching material resource")
		check(dressing.color_palette == (profile.foliage_palette if enabled else profile.original_foliage_palette), "Sample toggle selects the matching foliage resource")
		for style in [1, 2, 3, 0]:
			sample.style = style
			await frames()
			check(art.hemisphere_fill_enabled == (enabled and style > 0) and env.ambient_light_source == (Environment.AMBIENT_SOURCE_SKY if enabled and style > 0 else Environment.AMBIENT_SOURCE_COLOR), "Every Style applies or restores the intended fill")
		check(camera.global_transform == pose and camera.distance == 29.0, "Sample and Style retain custom camera and yaw")
		check([terrain._generated, dressing._generated, world.get_node("HouseSite/Home/Geometry"), world.get_node("TrainingHut/Geometry")] == generated, "Sample and Style do not rebuild terrain, plants or building collisions")
		check([terrain.data.heights, terrain.data.biomes, terrain.data.overlays] == terrain_values and [dressing.grass_density, dressing.flower_density, dressing.cluster_size, dressing.minimum_spacing] == distribution, "Terrain painting and foliage distribution remain unchanged")
		check([sample.grass_variation_strength, sample.grass_variation_size, sample.surface_normals_enabled, sample.character_normals_enabled, dressing.ground_sheen] == independent, "Independent meadow, normals and wet sheen values survive")
	var custom: PixelColorPalette = profile.material_palette.duplicate(true)
	sample.color_palette = custom
	for style in [1, 2, 3, 0]:
		sample.style = style
		await frames()
		check(sample.color_palette == custom, "R-style changes preserve an independently selected palette")
	sample.apply_value_sample()
	await frames()
	check(sample.color_palette == profile.material_palette, "Explicit apply restores the configured sample palette")
	sample.apply_vegetation_sample()
	await frames()
	check(dressing.color_palette == profile.foliage_palette, "Vegetation refresh keeps the enabled sample palette")
	sample.vegetation_sample_enabled = false
	await frames()
	check(dressing.color_palette == profile.original_foliage_palette, "Disabling the independent vegetation sample restores its original palette")
	sample.vegetation_sample_enabled = true
	await frames()
	check(dressing.color_palette == profile.foliage_palette, "Re-enabling vegetation reapplies the configured value palette")
	sample.value_sample_enabled = false
	sample.style = 1
	await frames()
	check(is_equal_approx(art.moon_energy, SpawnVisualSample.DAY.node_values["MapEffects/ArtDirection"].moon_energy) and is_equal_approx(art.ambient_energy, SpawnVisualSample.DAY.node_values["MapEffects/ArtDirection"].ambient_energy), "Turning the sample off restores the original light balance")
	check(profile.original_material_palette.grass == original_colors, "Applying the sample never edits baseline palette colours")
	var catalog = load("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(world)
	check(entries.any(func(entry): return entry.property == "value_sample_enabled" and entry.category == "视觉" and entry.common), "The toggle is a common visual parameter")
	check(entries.any(func(entry): return entry.property == "hemisphere_sky_color" and entry.category == "视觉" and entry.common), "Hemisphere tuning is indexed in the original control")
	check(entries.any(func(entry): return entry.object == profile and entry.property == "lighting_presets" and entry.category == "视觉"), "Profile resources remain in the visual category")
	print("Value lighting: ", checks, " checks; ", failures.size(), " failures")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	for audio in world.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	await create_timer(0.15).timeout
	world.free()
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)
