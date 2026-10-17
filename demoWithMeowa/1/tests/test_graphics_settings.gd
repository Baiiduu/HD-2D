extends SceneTree

const PAGE = preload("res://scripts/ui/graphics_settings_page.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").set("save_graphics_settings", false)
	root.add_child(world)
	current_scene = world
	for frame in 12: await process_frame
	var page = world.get_node("GameSettingsUI")._graphics_page
	check(page.configured, "Graphics page finishes initialization")
	check(page.controls.shadow_atlas.get_selected_metadata() == root.positional_shadow_atlas_size, "The shadow dropdown accurately reflects the scene's current value")
	check(page.overrides.is_empty(), "First launch keeps the scene's exact settings")
	var art: ArtDirection = world.get_node("MapEffects/ArtDirection")
	var env: Environment = world.get_node("MapEffects/WorldEnvironment").environment
	var camera: FollowCamera = world.get_node("Player").movement_camera
	var fov := camera.fov
	var player_position: Vector3 = world.get_node("Player").global_position
	var original_size := root.size
	var original_scale_size := root.content_scale_size
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	await process_frame
	check(page.set_option("render_height", 720), "720p is selectable independently of window mode")
	check(root.size == Vector2i(1920, 1080) and is_equal_approx(root.scaling_3d_scale, 2.0 / 3.0), "Lower resolution reduces the actual 3D buffer while retaining full-size output")
	check(root.content_scale_size == Vector2i.ZERO and camera.fov == fov, "Resolution does not resize UI coordinates or change FOV")
	root.size = Vector2i(2560, 1440)
	await process_frame
	check(is_equal_approx(root.scaling_3d_scale, 0.5), "Resolution remains 720p when the full-screen-sized output changes")
	check(page.set_option("fill_shadows", false), "Fill shadows can be changed from gameplay settings")
	page.controls.fill_shadows.button_pressed = true
	check(art.street_fill_shadows_enabled, "Checkbox changes the correct live setting")
	page.controls.fill_shadows.button_pressed = false
	check(page.set_option("cone_shadows", false), "Cone shadows can be controlled separately")
	check(page.set_option("ssao", false) and not env.ssao_enabled, "Ambient occlusion reaches the live environment")
	check(page.set_option("volumetric_fog", false) and not env.volumetric_fog_enabled, "Volumetric fog uses the scene controller")
	check(page.set_option("msaa", 0) and root.msaa_3d == Viewport.MSAA_DISABLED, "Anti-aliasing reaches the live viewport")
	page.controls.msaa.item_selected.emit(1)
	check(root.msaa_3d == Viewport.MSAA_2X, "Dropdown changes the correct live setting")
	page.set_option("msaa", 0)
	for style in 4:
		world.get_node("VisualSample").style = style
		world.get_node("VisualSample").apply_style()
		for frame in 3: await process_frame
		check(not env.ssao_enabled and not env.volumetric_fog_enabled and not art.street_fill_shadows_enabled, "Style preserves explicit quality choices")
		for lamp in get_nodes_in_group("environment_lanterns"):
			check(not lamp.get_node("Light").shadow_enabled and not lamp.get_node("Cone").shadow_enabled, "Both lamp shadow choices survive reapplication")
	check(not page.set_option("msaa", 999) and not page.set_option("unknown", false), "Unknown settings and invalid enums are rejected")
	check(not page.set_option("rain_intensity", "invalid") and not page.set_option("ssao", "false"), "Saved values are type-checked")
	check(page.set_option("rain_intensity", 5.0) and is_equal_approx(world.get_node("MapEffects/Weather").rain_intensity, 1.0), "Numeric settings are clamped")
	check(world.get_node("WavePrototype").enemies.is_empty() and camera.fov == fov and world.get_node("Player").global_position.is_equal_approx(player_position), "Graphics settings do not change gameplay or camera framing")
	var path := "D:/.codexfile/work/graphics-settings/quality-%d.cfg" % OS.get_process_id()
	page.config_path = path
	page.save_enabled = true
	check(page.save_settings() == OK, "Quality choices can be saved locally")
	var saved := ConfigFile.new()
	check(saved.load(path) == OK and saved.get_value(page.scene_section(), "fill_shadows") == false and saved.get_value("display", "render_height") == 720, "Map quality and display choices are stored separately")
	page.save_enabled = false
	page.reset_defaults()
	check(page.overrides.is_empty() and is_equal_approx(root.scaling_3d_scale, 1.0), "Reset restores native resolution and removes overrides")
	page.save_enabled = true
	page.load_settings()
	page.apply_settings()
	check(not art.street_fill_shadows_enabled and is_equal_approx(root.scaling_3d_scale, 0.5), "Saved settings restore after reload")
	page.save_enabled = false
	page.reset_defaults()
	root.size = original_size
	root.content_scale_size = original_scale_size
	world.queue_free()
	for frame in 4: await process_frame
	await create_timer(0.2).timeout
	print("GRAPHICS_SETTINGS_TEST ", checks, " checks, failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
