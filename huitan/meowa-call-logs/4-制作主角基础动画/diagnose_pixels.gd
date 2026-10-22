extends SceneTree

const OUT := "D:/Project/HD-2DMap/meowa-call-logs/4-制作主角基础动画/"

func _initialize() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	for tick in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "pixels-" + name + ".png")

func _run() -> void:
	var world: Node3D = load("res://scenes/four_realms.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for tick in 60:
		await physics_frame
	var player: Player = world.get_node("Player")
	player.set_process(false)
	player.set_physics_process(false)
	player.sprite.texture = load("res://assets/meowa/player/idle_00.png")
	var camera: FollowCamera = world.get_node("Camera3D")
	camera.set_process(false)
	var art: ArtDirection = world.get_node("ArtDirection")
	art.set_process(false)
	var imported: Image = player.sprite.texture.get_image()
	var source := Image.load_from_file(ProjectSettings.globalize_path("res://assets/meowa/player/idle_00.png"))
	var mismatches := 0
	for y in source.get_height():
		for x in source.get_width():
			if source.get_pixel(x,y).a > 0.0 and source.get_pixel(x,y) != imported.get_pixel(x,y):
				mismatches += 1
	var center := camera.unproject_position(player.sprite.global_position)
	var pixel_width := camera.unproject_position(player.sprite.global_position + Vector3.RIGHT * player.sprite.pixel_size).x - center.x
	print("Opaque imported pixel mismatches: ", mismatches)
	print("Sprite center: ", center, "; projected source pixel width: ", pixel_width, "; viewport: ", root.get_visible_rect().size)
	await capture("current")
	camera.attributes.dof_blur_far_enabled = false
	camera.attributes.dof_blur_near_enabled = false
	await capture("no-dof")
	player.sprite.shaded = false
	await capture("unshaded")
	var env: Environment = world.get_node("WorldEnvironment").environment
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = false
	env.glow_enabled = false
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	world.get_node("PostProcess").visible = false
	root.msaa_3d = Viewport.MSAA_DISABLED
	await capture("neutral")
	var report := {"opaque_import_mismatches":mismatches,"center":[center.x,center.y],"projected_source_pixel_width":pixel_width,"logical_viewport":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"viewport":[root.size.x,root.size.y],"projected_window_pixel_width":pixel_width * root.size.x / root.get_visible_rect().size.x}
	var file := FileAccess.open(OUT + "pixel-diagnosis.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	quit(0 if mismatches == 0 else 1)
