extends SceneTree

func _initialize() -> void:
	run_check.call_deferred()

func settle() -> void:
	for frame in 20:
		await process_frame

func run_check() -> void:
	await settle()
	EditorInterface.open_scene_from_path("res://scenes/four_realms.tscn")
	EditorInterface.set_main_screen_editor("3D")
	await settle()
	var scene := EditorInterface.get_edited_scene_root()
	var weather := scene.get_node("Weather")
	var rain: GPUParticles3D = weather.get_node("Rain")
	var default_on: bool = rain.emitting and weather._vegetation.size() > 0
	var inspector_properties: Array[Dictionary] = weather.get_property_list()
	var exports := 0
	for property in inspector_properties:
		if String(property["name"]) in ["weather_mode", "rain_intensity", "wind_strength", "grass_sway", "flower_sway", "lens_drop_lifetime", "lens_blur", "editor_preview"] and int(property["usage"]) & PROPERTY_USAGE_EDITOR:
			exports += 1
	EditorInterface.edit_node(weather)
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	await settle()
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("D:/Project/HD-2DMap/artifacts/weather/editor-preview.png")
	weather.editor_preview = false
	await settle()
	var preview_off: bool = not rain.visible
	for material: ShaderMaterial in weather._vegetation:
		preview_off = preview_off and material.get_shader_parameter("wind_strength") == 0.0
	weather.editor_preview = true
	weather.rain_intensity = 0.8
	weather.wind_direction = Vector2(-1.0, 0.5)
	await settle()
	var updated: bool = rain.visible and rain.emitting and is_equal_approx(rain.amount_ratio, 0.8)
	var first_material: ShaderMaterial = weather._vegetation[0]
	var clock_before: float = first_material.get_shader_parameter("wind_time")
	await settle()
	var clock_after: float = first_material.get_shader_parameter("wind_time")
	var ok: bool = Engine.is_editor_hint() and not EditorInterface.is_playing_scene() and default_on and exports == 8 and preview_off and updated and clock_after > clock_before and weather._drops.is_empty()
	var report := {"editor_hint": Engine.is_editor_hint(), "playing": EditorInterface.is_playing_scene(), "default_on": default_on, "editable_properties": exports, "preview_off": preview_off, "live_update": updated, "wind_animated": clock_after > clock_before, "lens_transients_not_created_in_editor": weather._drops.is_empty(), "passed": ok}
	FileAccess.open("D:/Project/HD-2DMap/artifacts/weather/editor-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if ok else 1)
