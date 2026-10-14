extends SceneTree

const OUTPUT := "D:/Project/HD-2DMap/artifacts/weather/"
var failures: Array[String] = []
var scene: Node3D
var weather: Node3D

func _initialize() -> void:
	run_checks.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle(frames: int = 8) -> void:
	for frame in frames:
		await process_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> Image:
	await settle()
	var image := root.get_texture().get_image()
	image.save_png(OUTPUT + name + ".png")
	return image

func points(dressing: Node3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for batch: MultiMeshInstance3D in dressing.find_children("*", "MultiMeshInstance3D", true, false):
		for index in batch.multimesh.instance_count:
			result.append(batch.multimesh.get_instance_transform(index))
	return result

func run_checks() -> void:
	root.size = Vector2i(1280, 800)
	scene = load("res://scenes/four_realms.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 80:
		await physics_frame
	weather = scene.get_node("Weather")
	var camera: FollowCamera = scene.get_node("Camera3D")
	var dressing: Node3D = scene.get_node("World/GroundDressing")
	var rain: GPUParticles3D = weather.get_node("Rain")
	var initial_points := points(dressing)
	var initial_camera := {"mode": camera.dof_mode, "amount": camera.dof_amount, "radius": camera.ellipse_radius, "distance": camera.distance, "pitch": camera.pitch_degrees}
	check(rain.emitting and rain.amount_ratio > 0.0 and not rain.local_coords, "Rain was not enabled in world space")
	check(weather._vegetation.size() > 0, "Wind did not bind to vegetation")
	for material: ShaderMaterial in weather._vegetation:
		check(material.get_shader_parameter("wind_strength") > 0.0, "Vegetation did not receive weather wind")
	var plant_meshes := dressing.find_children("*", "MultiMeshInstance3D", true, false)
	var root_rows := 0
	for batch: MultiMeshInstance3D in plant_meshes:
		if batch.multimesh.mesh.material is ShaderMaterial:
			var mesh: QuadMesh = batch.multimesh.mesh
			var arrays := mesh.get_mesh_arrays()
			for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
				if is_equal_approx(uv.y, 44.0 / 48.0):
					root_rows += 1
	check(root_rows > 0, "Vegetation has no fixed root row")
	await capture("drizzle")
	# 同一片野外草地拍摄风摆与细雨序列。
	var player: CharacterBody3D = scene.get_node("Player")
	player.position = Vector3(20.0, 0.02, 5.0)
	player.reset_physics_interpolation()
	for frame in 5:
		await physics_frame
	camera.snap_to_target()
	for index in 18:
		for frame in 8:
			await physics_frame
		await capture("rain-%02d" % index)
	check(not weather._drops.is_empty(), "Lens never spawned droplets")
	var drops_during_rain: int = weather._drops.size()
	weather.weather_mode = 0
	await settle()
	check(not rain.emitting, "Clear weather still emits rain")
	weather._advance_drops(15.0)
	check(weather._drops.is_empty(), "Lens droplets did not expire after rain stopped")
	check(weather._post.get_shader_parameter("lens_enabled") == false, "Expired lens droplets still rendered")
	weather.enabled = false
	await settle()
	check(not rain.visible, "Disabled weather still displays rain")
	for material: ShaderMaterial in weather._vegetation:
		check(material.get_shader_parameter("wind_strength") == 0.0, "Disabled weather still bends plants")
	await capture("weather-off")
	check(points(dressing) == initial_points, "Weather moved or regenerated scatter anchors")
	check(camera.dof_mode == initial_camera["mode"] and camera.dof_amount == initial_camera["amount"] and camera.ellipse_radius == initial_camera["radius"] and camera.distance == initial_camera["distance"] and camera.pitch_degrees == initial_camera["pitch"], "Weather changed camera configuration")
	weather.enabled = true
	weather.weather_mode = 1
	weather.wind_direction = Vector2(-1.0, 0.5)
	weather.rain_intensity = 0.8
	weather.grass_sway = 0.04
	weather.flower_sway = 0.025
	await settle()
	check(is_equal_approx(rain.amount_ratio, 0.8), "Rain intensity did not update live")
	check((rain.process_material as ParticleProcessMaterial).direction.x < 0.0, "Rain direction did not follow wind")
	for material: ShaderMaterial in weather._vegetation:
		check(material.get_shader_parameter("wind_direction").x < 0.0, "Vegetation direction did not update live")
	# 改地编资源会重建材质，天气仍需自动绑定新批次。
	dressing.flower_variants = 1
	await settle()
	check(weather._vegetation.size() > 0, "Wind lost all bindings after scatter rebuild")
	for material: ShaderMaterial in weather._vegetation:
		check(material.get_shader_parameter("wind_strength") > 0.0, "Rebuilt vegetation lost wind")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "Weather scene cannot serialize")
	var restored: Node3D = packed.instantiate()
	var settings: Node3D = restored.get_node("Weather")
	check(settings.rain_intensity == 0.8 and settings.wind_direction == Vector2(-1.0, 0.5), "Weather configuration was not saved")
	check(not settings.has_node("Rain"), "Transient rain particles were serialized")
	restored.free()
	# 稳定的棋盘图验证镜头水滴只影响局部，并保护人物位置。
	weather.set_process(false)
	camera.set_process(false)
	var post: ShaderMaterial = scene.get_node("PostProcess/Screen").material
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
	post.set_shader_parameter("ellipse_enabled", false)
	post.set_shader_parameter("lens_enabled", false)
	var original := await capture("lens-off")
	var drops := PackedVector4Array()
	drops.resize(12)
	drops[0] = Vector4(0.25, 0.3, 32.0, 1.0)
	drops[1] = Vector4(0.5, 0.5, 32.0, 1.0)
	post.set_shader_parameter("ellipse_center", Vector2(0.5, 0.5))
	post.set_shader_parameter("lens_drops", drops)
	post.set_shader_parameter("lens_drop_count", 2)
	post.set_shader_parameter("lens_enabled", true)
	var with_drops := await capture("lens-local")
	var changed := 0
	var center_changes := 0
	for y in original.get_height():
		for x in original.get_width():
			if original.get_pixel(x, y) != with_drops.get_pixel(x, y):
				changed += 1
				if Vector2(x - original.get_width() * 0.5, y - original.get_height() * 0.5).length() < 50.0:
					center_changes += 1
	check(changed > 100 and changed < original.get_width() * original.get_height() * 0.02, "Lens blur is missing or affects too much of the screen")
	check(center_changes == 0, "Lens droplets blur the protected player area")
	drops.fill(Vector4.ZERO)
	post.set_shader_parameter("lens_drops", drops)
	var faded := await capture("lens-faded")
	check(faded.get_data() == original.get_data(), "Fully faded droplets leave blur behind")
	var report := {"failures": failures, "vegetation_materials": weather._vegetation.size(), "scatter_instances": initial_points.size(), "lens_drops_during_rain": drops_during_rain, "lens_changed_pixels": changed, "lens_center_changed_pixels": center_changes, "fixed_root_vertices": root_rows, "camera_configuration": initial_camera}
	FileAccess.open(OUTPUT + "validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
