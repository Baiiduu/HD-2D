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

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("VisualSample").follow_weather = false
	world.get_node("VisualSample").original_light_refinement_enabled = false
	root.add_child(world)
	current_scene = world
	await frames(30)
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var art: ArtDirection = world.get_node("MapEffects/ArtDirection")
	var moon: DirectionalLight3D = world.get_node("MapEffects/Moon")
	var screen: CanvasItem = world.get_node("MapEffects/PostProcess/Screen")
	var reflection := world.get_node("MapEffects/WaterReflection")
	var accents := world.get_node("MapEffects/AtmosphericLight")
	check(art.moon == moon, "The controller binds to the actual directional light")
	check(art.post_process == screen, "The controller binds to the actual post process")
	check(art.water_reflection == reflection, "The water reflection binding survives the audio integration")
	check(world.has_node("MapEffects/GameAudio"), "The shared audio manager is retained")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	world.get_node("Player").set_physics_process(false)
	camera.set_process(false)
	camera.snap_to_target()
	var pose := camera.global_transform
	var lens := [camera.fov, camera.distance, camera.pitch_degrees, camera.dof_amount]
	var dressing := world.get_node("GroundDressing")
	var terrain: Terrain = world.get_node("Homestead")
	var generated := [terrain._generated, dressing._generated]
	var common := [sample.color_palette, dressing.color_palette, dressing.grass_density,
		dressing.flower_density, dressing.layered_growth_strength, dressing.leaf_normals_enabled,
		sample.surface_normals_enabled, sample.character_normals_enabled, sample.edge_blending_enabled]
	for enabled in [false, true]:
		sample.value_sample_enabled = enabled
		await frames()
		for style in [0, 1, 2, 3, 0]:
			sample.style = style
			await frames()
			if style == 0:
				# Preserve the warm light the user actually reviewed before the binding repair.
				check(is_equal_approx(moon.light_energy, 1.65) and moon.light_color.is_equal_approx(Color(1, 0.71, 0.4)), "Original retains its reviewed main light")
				check(is_equal_approx(moon.rotation_degrees.x, -28.0) and is_equal_approx(moon.rotation_degrees.y, -112.0), "Original retains its reviewed light direction")
				check(is_equal_approx(moon.shadow_opacity, 0.72) and is_equal_approx(moon.light_angular_distance, 1.4), "Original retains its reviewed shadow")
				var az := deg_to_rad(-24.0)
				var el := deg_to_rad(38.0)
				check(not accents.follow_global_direction and accents._surface_direction.is_equal_approx(Vector3(sin(az) * cos(el), -sin(el), cos(az) * cos(el))), "Original retains its reviewed local light direction")
			else:
				check(is_equal_approx(moon.light_energy, art.moon_energy) and moon.light_color.is_equal_approx(art.moon_color), "Style %d reaches the rendered light, with value sample %s" % [style, enabled])
				check(is_equal_approx(moon.rotation_degrees.x, -art.moon_elevation) and is_equal_approx(moon.rotation_degrees.y, art.moon_azimuth), "Style %d reaches the rendered light direction" % style)
				check(is_equal_approx(moon.shadow_opacity, art.moon_shadow_opacity), "Style %d reaches the rendered shadow" % style)
				check(accents.follow_global_direction and accents._surface_direction.is_equal_approx(-moon.global_basis.z.normalized()), "Lumina local accents follow the actual main light")
			check(is_equal_approx(float(screen.material.get_shader_parameter("split_toning")), art.split_toning), "The rendered split toning follows the controller")
			check(camera.global_transform == pose and [camera.fov, camera.distance, camera.pitch_degrees, camera.dof_amount] == lens, "Switching Style retains the camera")
			check([terrain._generated, dressing._generated] == generated, "Switching Style does not rebuild terrain or vegetation")
		# A value-palette toggle is independent; capture the new common layer before R-only checks.
		common = [sample.color_palette, dressing.color_palette, dressing.grass_density,
			dressing.flower_density, dressing.layered_growth_strength, dressing.leaf_normals_enabled,
			sample.surface_normals_enabled, sample.character_normals_enabled, sample.edge_blending_enabled]
		for style in [1, 2, 3, 0]:
			sample.style = style
			await frames()
			check([sample.color_palette, dressing.color_palette, dressing.grass_density,
				dressing.flower_density, dressing.layered_growth_strength, dressing.leaf_normals_enabled,
				sample.surface_normals_enabled, sample.character_normals_enabled, sample.edge_blending_enabled] == common, "Style preserves the shared palettes, plant layers and normal maps")
			if style == 2: check(moon.light_color.b > moon.light_color.r, "Rain has a cool main light")
			if style == 3: check(moon.light_color.b > moon.light_color.r and art.moon_azimuth > 0.0, "Night has a blue main light from its own direction")
	print("Style light bindings: ", checks, " checks; ", failures.size(), " failures")
	world.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
