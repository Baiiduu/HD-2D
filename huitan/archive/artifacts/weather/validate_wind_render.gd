extends SceneTree

func _initialize() -> void:
	run_check.call_deferred()

func render(viewport: SubViewport) -> Image:
	for frame in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func run_check() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(0.0, 0.46875, 3.0)
	viewport.add_child(camera)
	var light := OmniLight3D.new()
	light.position = camera.position
	light.omni_range = 10.0
	viewport.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	viewport.add_child(env)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/vegetation_wind.gdshader")
	material.set_shader_parameter("sprite_texture", load("res://assets/meowa/dressing/grass/grass_01.png"))
	material.set_shader_parameter("wind_direction", Vector2(1.0, 0.0))
	material.set_shader_parameter("wind_strength", 2.0)
	material.set_shader_parameter("gust_strength", 0.0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.125, 1.125)
	mesh.subdivide_depth = 11
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position.y = 0.46875
	viewport.add_child(instance)
	material.set_shader_parameter("wind_time", 0.0)
	var before := await render(viewport)
	before.save_png("D:/Project/HD-2DMap/artifacts/weather/wind-before.png")
	material.set_shader_parameter("wind_time", 1.0)
	var after := await render(viewport)
	after.save_png("D:/Project/HD-2DMap/artifacts/weather/wind-after.png")
	var moving_pixels := 0
	var root_changes := 0
	var root_pixels := 0
	# The anchor projects to Y=94. Row 93 is the visible pixel row touching it.
	# Rows 91/92 are above the anchor and legitimately belong to the bending stem.
	var anchor_screen := camera.unproject_position(Vector3.ZERO)
	var root_row := int(floor(anchor_screen.y)) - 1
	for y in 128:
		for x in 128:
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if a != b:
				moving_pixels += 1
				if y >= root_row: root_changes += 1
			if y >= root_row and a.r + a.g + a.b > 0.05: root_pixels += 1
	var ok := moving_pixels > 30 and root_changes == 0 and root_pixels > 0
	var report := {"anchor_screen_y": anchor_screen.y, "root_pixel_row": root_row, "moving_pixels": moving_pixels, "root_changed_pixels": root_changes, "root_visible_pixels": root_pixels, "passed": ok}
	FileAccess.open("D:/Project/HD-2DMap/artifacts/weather/wind-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	viewport.free()
	await process_frame
	quit(0 if ok else 1)
