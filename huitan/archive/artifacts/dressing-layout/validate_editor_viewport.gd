extends SceneTree

func _initialize() -> void:
	run_check.call_deferred()

func settle() -> void:
	for frame in 8:
		await process_frame

func run_check() -> void:
	await settle()
	EditorInterface.open_scene_from_path("res://scenes/four_realms.tscn")
	EditorInterface.set_main_screen_editor("3D")
	await settle()
	var scene := EditorInterface.get_edited_scene_root()
	if not scene:
		print("No edited scene root")
		quit(1)
		return
	var dressing := scene.get_node("World/GroundDressing")
	var baseline: int = dressing.instance_count
	var region := dressing.get_node("UpperGrass")
	var outline_exists: bool = region.has_node("AreaOutline")
	EditorInterface.edit_node(dressing)
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	# 只设置本次验证进程的编辑器相机，不修改游戏相机和场景文件。
	camera.position = Vector3(25.0, 14.0, 17.0)
	camera.look_at(Vector3(24.0, 0.8, -5.6))
	await settle()
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("D:/Project/HD-2DMap/artifacts/dressing-layout/editor-preview.png")
	dressing.editor_preview_enabled = false
	await settle()
	var hidden: bool = dressing.instance_count == 0 and not dressing.has_node("Layers")
	dressing.editor_preview_enabled = true
	await settle()
	var restored: bool = dressing.instance_count == baseline
	var original_points: Array[Dictionary] = dressing._placements()
	region.position.x += 2.0
	await settle()
	var moved: bool = dressing._placements() != original_points
	region.position.x -= 2.0
	region.grass_variants = 4
	region.flower_variants = 0
	await settle()
	var selected: bool = true
	for placement: Dictionary in dressing._placements():
		var local: Vector3 = region.to_local(dressing.to_global(placement["point"]))
		if absf(local.x) <= region.area_size.x * 0.5 and absf(local.z) <= region.area_size.y * 0.5:
			selected = selected and placement["asset"] == "grass_03"
	region.grass_variants = 63
	region.flower_variants = 63
	dressing.grass_density *= 2.0
	await settle()
	var updated: bool = dressing.instance_count > baseline
	dressing._generated.free()
	dressing.refresh_preview.call()
	await settle()
	var button_rebuilt: bool = dressing.has_node("Layers") and dressing.instance_count > baseline
	var ok: bool = Engine.is_editor_hint() and not EditorInterface.is_playing_scene() and baseline > 0 and outline_exists and hidden and restored and moved and selected and updated and button_rebuilt
	var report := {"editor_hint": Engine.is_editor_hint(), "playing": EditorInterface.is_playing_scene(), "default": baseline, "outline": outline_exists, "toggle_off": hidden, "toggle_restore": restored, "area_live": moved, "resources_live": selected, "density_live": updated, "refresh_button": button_rebuilt, "viewport_size": str(viewport.size), "passed": ok}
	FileAccess.open("D:/Project/HD-2DMap/artifacts/dressing-layout/editor-viewport-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if ok else 1)
