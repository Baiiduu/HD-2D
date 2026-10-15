extends SceneTree

const SCRATCH := "D:/.codexfile/work/lumina-spawn-regression/"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func frames(count := 6) -> void:
	for frame in count: await physics_frame
	await process_frame

func equivalent(actual: Variant, expected: Variant) -> bool:
	if typeof(expected) in [TYPE_FLOAT, TYPE_INT] and typeof(actual) in [TYPE_FLOAT, TYPE_INT]:
		return is_equal_approx(float(actual), float(expected))
	return actual == expected

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func run() -> void:
	var source_palette: TerrainPaintPalette = load("res://data/world/spawn_paint_palette.tres")
	var source_grass_tint := source_palette.brushes[0].tint
	var protected_paths := ["res://data/world/spawn_paint_palette.tres", "res://data/world/spawn_terrain.tres", "res://materials/world/spawn_ground.tres", "res://materials/world/spawn_cliff.tres"]
	var hashes := {}
	for path in protected_paths: hashes[path] = FileAccess.get_sha256(path)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	# Verify the base presets here; the optional value layer has its own restoration checks.
	world.get_node("VisualSample").value_sample_enabled = false
	world.get_node("VisualSample").original_light_refinement_enabled = false
	world.get_node("VisualSample").fog_post_enabled = false
	var loadout: LoadoutUI = world.get_node("LoadoutUI")
	var save_path: String = loadout.save_path
	var save_exists := FileAccess.file_exists(save_path)
	var save_hash := FileAccess.get_sha256(save_path) if save_exists else ""
	loadout.save_enabled = false
	root.add_child(world)
	current_scene = world
	await frames(10)
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var terrain: Terrain = world.get_node("Homestead")
	var player: Player = world.get_node("Player")
	var farm: Farming = world.get_node("Farming")
	var training: TrainingUI = world.get_node("TrainingUI")
	var home: Node3D = world.get_node("HouseSite/Home")
	var camera: FollowCamera = world.get_node("MapEffects").get_map_camera()
	var art: ArtDirection = world.get_node("MapEffects/ArtDirection")
	var weather: Node3D = world.get_node("MapEffects/Weather")
	var camera_before := {"distance": camera.distance, "pitch_degrees": camera.pitch_degrees, "fov": camera.fov,
		"focus_height": camera.focus_height, "dof_amount": camera.dof_amount}
	var sites_before := [world.get_node("HouseSite").position, world.get_node("TrainingHut").position]
	check(terrain.paint_palette != source_palette and terrain.paint_palette.brushes[0] != source_palette.brushes[0], "Palette and mutable brushes are isolated from editor source")
	check(terrain.top_material != load("res://materials/world/spawn_ground.tres") and terrain.wall_material != load("res://materials/world/spawn_cliff.tres"), "World materials are local to the scene instance")
	check(terrain.data != farm._base_data, "Farming still owns a runtime terrain copy")
	var terrain_before := {"origin": terrain.data.origin, "cell_size": terrain.data.cell_size, "heights": terrain.data.heights.duplicate(), "biomes": terrain.data.biomes.duplicate(), "overlays": terrain.data.overlays.duplicate()}
	var plot := Vector2i(-2, 4)
	check(farm._base_data.has_cell(plot) and farm._base_data.get_biome(plot) == TerrainData.Biome.WILD and not farm._base_data.has_overlay(plot, TerrainData.OVERLAY_PATH | TerrainData.OVERLAY_RAMP), "Fixture farmland is existing grass, outside the path")
	loadout.state.till_farm_plot(farm.world_id, plot)
	await frames()
	var state_before := loadout.state.export_state().duplicate(true)
	var marker := training.interaction_point
	var offsets := marker.position
	var styles := [0, 1, 2, 3, 0]
	for style in styles:
		sample.style = style
		await frames()
		var preset: SpawnVisualPreset = [sample.ORIGINAL, sample.DAY, sample.RAIN, sample.NIGHT][style]
		var expected := sample._merged_values(preset.node_values, sample.ORIGINAL_RENDER.node_values) if style == 0 else preset.node_values
		for path in ["HouseSite", "TrainingHut", "GroundDressing", "MapEffects/ArtDirection", "MapEffects/Weather"]:
			for name in expected.get(path, {}):
				if not sample._visual_property(path, name): continue
				check(equivalent(world.get_node(path).get(name), expected[path][name]), "%d restores %s.%s" % [style, path, name])
		check(camera.target == player and camera.dof_enabled and camera.dof_mode == 0, "%d preserves follow and depth DOF" % style)
		for property in camera_before:
			check(equivalent(camera.get(property), camera_before[property]), "%d preserves current camera %s" % [style, property])
		check(world.get_node("HouseSite").position == sites_before[0] and world.get_node("TrainingHut").position == sites_before[1], "%d preserves current building placement" % style)
		check(is_equal_approx(world.get_node("MapEffects/WorldEnvironment").environment.adjustment_saturation, art.saturation), "%d writes grading to the actual environment" % style)
		check(terrain.data.origin == terrain_before.origin and terrain.data.cell_size == terrain_before.cell_size and terrain.data.heights == terrain_before.heights and terrain.data.biomes == terrain_before.biomes and terrain.data.overlays == terrain_before.overlays, "%d preserves terrain coordinates, heights and roads" % style)
		if DisplayServer.get_name() != "headless":
			check(RenderingServer.material_get_param(terrain.top_material.get_rid(), &"map_origin") == terrain.data.origin and is_equal_approx(float(RenderingServer.material_get_param(terrain.top_material.get_rid(), &"cell_size")), terrain.data.cell_size), "%d preserves true render-server map coordinates" % style)
			check(RenderingServer.material_get_param(terrain.top_material.get_rid(), &"terrain_map") == terrain._map_texture.get_rid(), "%d keeps the generated terrain map bound" % style)
			check(RenderingServer.material_get_param(terrain.top_material.get_rid(), &"paint_textures") == terrain._paint_textures.paint_textures.get_rid(), "%d keeps custom paint texture-array binding" % style)
		check(terrain.paint_palette.brush_for_id(farm.soil_paint_id).paint_id == 3 and terrain.data.paint_at_index(terrain.data._index(plot)) == 3 and farm._base_data.paint_at_index(farm._base_data._index(plot)) == 0, "%d preserves soil id3 and runtime farmland" % style)
		check(loadout.state.export_state() == state_before, "%d does not modify inventory, vitals or farmland save state" % style)
		check(is_instance_valid(training.interaction_point) and training.interaction_point == marker and marker.position == offsets and marker.global_position.is_equal_approx(world.get_node("TrainingHut").to_global(offsets)), "%d moves the existing training marker with its building" % style)
		player.set_physics_process(false)
		player.global_position = marker.global_position + Vector3(0.0, -0.72, 0.3)
		player.reset_physics_interpolation()
		await frames(2)
		check(training.can_interact(), "%d training remains reachable without wall obstruction" % style)
		if style in [0, 1]:
			player.set_physics_process(true)
			player.movement_camera = null
			player.global_position = home.global_position + Vector3(0.0, 0.3, home.depth * 0.5 + 3.4)
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
			await frames(30)
			key(KEY_W, true)
			await frames(45)
			key(KEY_W, false)
			check(player.global_position.y > home.global_position.y + 0.52 and home.to_local(player.global_position).z < home.depth * 0.5 + 1.1 and player.is_on_floor(), "%d actual home stairs remain walkable after settled placement" % style)
			player.set_physics_process(false)
		check(source_palette.brushes[0].tint == source_grass_tint, "%d leaves shared source grass tint unchanged" % style)
	# Weather switching must update lighting without altering the legacy style.
	sample.style = 1
	await frames()
	weather.weather_mode = 1
	await frames()
	check(sample.style == 2 and equivalent(art.moon_color, sample.RAIN.node_values["MapEffects/ArtDirection"].moon_color), "Changing rain mode automatically selects matching illumination")
	sample.style = 0
	await frames()
	weather.weather_mode = 0
	await frames()
	check(sample.style == 0, "Original mode preserves independent weather control")
	var pixel_enabled := sample.pixel_art_enabled
	for code in [KEY_F7, KEY_F8]:
		key(code, true)
		key(code, false)
		await frames()
		check(sample.style == 0 and sample.pixel_art_enabled == pixel_enabled, "Function key %d does not change visual presets or materials" % code)
	sample.style = 2
	await frames()
	check(sample.style == 2, "Inspector selection applies the rain preset")
	sample.style = 0
	await frames()
	check(sample.style == 0 and home.get_parent().position == sites_before[0] and not terrain.top_material.get_shader_parameter("lumina_relief_enabled") and not world.get_node("MapEffects/PostProcess/Screen").material.get_shader_parameter("lumina_grade_enabled"), "Inspector selection preserves positions and disables Lumina grading/relief")
	for path in protected_paths: check(FileAccess.get_sha256(path) == hashes[path], "Source file unchanged: " + path)
	check(FileAccess.file_exists(save_path) == save_exists and (not save_exists or FileAccess.get_sha256(save_path) == save_hash), "Existing user save is unchanged")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	await create_timer(0.15).timeout
	world.free()
	await frames(2)
	await create_timer(0.1).timeout
	print(JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
