extends SceneTree

const OUTPUT := "D:/Project/HD-2DMap/artifacts/ellipse-focus/"
var failures: Array[String] = []

func _initialize() -> void:
	run_checks.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		freeze(child)

func capture(name: String) -> Image:
	await settle()
	var image := root.get_texture().get_image()
	image.save_png(OUTPUT + name + ".png")
	return image

func run_checks() -> void:
	root.size = Vector2i(1280, 800)
	var scene: Node3D = load("res://scenes/four_realms.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 45:
		await physics_frame
	var camera: FollowCamera = scene.get_node("Camera3D")
	var screen: ColorRect = scene.get_node("PostProcess/Screen")
	var material: ShaderMaterial = screen.material
	var attributes: CameraAttributesPractical = camera.attributes
	var player: CharacterBody3D = scene.get_node("Player")
	freeze(scene)
	check(camera.dof_mode == 1, "Saved scene did not select ellipse mode")
	check(material.get_shader_parameter("ellipse_enabled") == true, "Ellipse mode not connected to post process")
	check(not attributes.dof_blur_far_enabled and not attributes.dof_blur_near_enabled, "Depth blur still active in ellipse mode")
	await capture("ellipse")
	camera.dof_mode = 0
	camera._update_dof()
	check(attributes.dof_blur_far_enabled and attributes.dof_blur_near_enabled, "Original depth mode not restored")
	check(material.get_shader_parameter("ellipse_enabled") == false, "Ellipse still enabled in depth mode")
	await capture("depth")
	camera.dof_enabled = false
	camera._update_dof()
	check(not attributes.dof_blur_far_enabled and not attributes.dof_blur_near_enabled and material.get_shader_parameter("ellipse_enabled") == false, "Master switch failed")
	await capture("off")
	# 人物靠近地图边界后会偏离画面中心，验证椭圆仍跟随人物。
	camera.dof_enabled = true
	camera.dof_mode = 1
	player.position = Vector3(34.0, 0.82, 5.0)
	player.reset_physics_interpolation()
	for frame in 3:
		await physics_frame
	camera.snap_to_target()
	await settle()
	camera._update_dof()
	var expected := camera.unproject_position(player.global_position + Vector3.UP * camera.focus_height) / root.get_visible_rect().size
	var actual: Vector2 = material.get_shader_parameter("ellipse_center")
	check(actual.is_equal_approx(expected) and actual.x > 0.55 and actual.x < 1.0, "Ellipse did not follow off-center player")
	await capture("edge-follow")
	# 用稳定棋盘纹理检查清晰区和四周的实际 GPU 输出，避免水面动画干扰。
	var backdrop := CanvasLayer.new()
	backdrop.layer = -1
	scene.add_child(backdrop)
	var rectangle := ColorRect.new()
	rectangle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(rectangle)
	var checker := Shader.new()
	checker.code = "shader_type canvas_item; void fragment() { float cell = mod(floor(FRAGCOORD.x / 4.0) + floor(FRAGCOORD.y / 4.0), 2.0); COLOR = vec4(vec3(mix(0.1, 0.9, cell)), 1.0); }"
	var checker_material := ShaderMaterial.new()
	checker_material.shader = checker
	rectangle.material = checker_material
	material.set_shader_parameter("ellipse_center", Vector2(0.5, 0.5))
	material.set_shader_parameter("ellipse_radius", Vector2(0.3, 0.2))
	material.set_shader_parameter("ellipse_transition", 0.5)
	material.set_shader_parameter("ellipse_blur_amount", 0.12)
	material.set_shader_parameter("ellipse_enabled", false)
	var original := await capture("checker-off")
	material.set_shader_parameter("ellipse_enabled", true)
	var blurred := await capture("checker-ellipse")
	var inside_error := 0.0
	var outside_error := 0.0
	var inside_count := 0
	var outside_count := 0
	for y in range(0, original.get_height(), 8):
		for x in range(0, original.get_width(), 8):
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(original.get_size())
			var radius := ((uv - Vector2(0.5, 0.5)) / Vector2(0.3, 0.2)).length()
			var before := original.get_pixel(x, y)
			var after := blurred.get_pixel(x, y)
			var error := absf(before.r - after.r) + absf(before.g - after.g) + absf(before.b - after.b)
			if radius < 0.9:
				inside_error += error
				inside_count += 1
			elif radius > 1.6:
				outside_error += error
				outside_count += 1
	inside_error /= inside_count
	outside_error /= outside_count
	check(inside_error < 0.001, "Ellipse clear center changed source pixels")
	check(outside_error > 0.1, "Ellipse exterior did not actually blur")
	material.set_shader_parameter("ellipse_blur_amount", 0.0)
	var zero_blur := await capture("checker-zero")
	check(zero_blur.get_data() == original.get_data(), "Zero blur does not restore original image")
	var report := {"failures": failures, "inside_error": inside_error, "outside_error": outside_error, "off_center": str(actual), "amount": camera.dof_amount, "radius": str(camera.ellipse_radius)}
	FileAccess.open(OUTPUT + "validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
