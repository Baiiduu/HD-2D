extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ", message)

func frames(count := 12) -> void:
	for frame in count: await process_frame

func photo() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func sample(image: Image, camera: Camera3D, point: Vector3) -> float:
	var screen := camera.unproject_position(point) * Vector2(image.get_size()) / camera.get_viewport().get_visible_rect().size
	var pixel := Vector2i(screen.round())
	return image.get_pixel(clampi(pixel.x, 0, image.get_width() - 1), clampi(pixel.y, 0, image.get_height() - 1)).r

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: soft foliage shadows require native rendering")
		quit()
		return
	AudioServer.set_bus_mute(0, true)
	root.positional_shadow_atlas_size = 2048
	for fixture in [{"kind": "plant", "directional": false}, {"kind": "tree", "directional": false},
		{"kind": "plant", "directional": true}, {"kind": "tree", "directional": true}]:
		var kind: String = fixture.kind
		var label := kind + (" directional" if fixture.directional else " spot")
		var stage := Node3D.new()
		root.add_child(stage)
		current_scene = stage
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.2, 0.2, 0.2)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.25
		stage.add_child(environment)
		var floor := MeshInstance3D.new()
		var floor_mesh := PlaneMesh.new()
		floor_mesh.size = Vector2(30, 30)
		var floor_material := StandardMaterial3D.new()
		floor_material.roughness = 1.0
		floor_material.metallic_specular = 0.0
		floor_mesh.material = floor_material
		floor.mesh = floor_mesh
		stage.add_child(floor)
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/environment/vegetation_wind.gdshader" if kind == "plant" else "res://shaders/environment/tree_billboard.gdshader")
		material.set_shader_parameter("sprite_texture" if kind == "plant" else "tree_texture", load("res://assets/meowa/dressing/grass/grass_01.png" if kind == "plant" else "res://assets/meowa/buildings/tree_planter/tree.png"))
		material.set_shader_parameter("wind_strength", 0.0)
		if kind == "plant":
			material.set_shader_parameter("visible_height_uv", 20.0 / 48.0)
			material.set_shader_parameter("visible_width_uv", 30.0 / 48.0)
		var casters: Array[MeshInstance3D] = []
		for index in (2 if kind == "plant" else 1):
			var card := MeshInstance3D.new()
			var mesh := QuadMesh.new()
			mesh.size = Vector2.ONE * (1.125 if kind == "plant" else 3.2)
			mesh.material = material
			card.mesh = mesh
			card.position = Vector3(index * 0.32, 0.46875 if kind == "plant" else 1.45, 0)
			card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			stage.add_child(card)
			casters.append(card)
		var light: Light3D = DirectionalLight3D.new() if fixture.directional else SpotLight3D.new()
		light.position = Vector3(-3, 6, -2)
		stage.add_child(light)
		light.look_at(Vector3.ZERO)
		light.light_energy = 3.0
		if light is SpotLight3D:
			light.spot_range = 25.0
			light.spot_angle = 60.0
		else:
			# Keep the white probe floor below clipping; partial coverage must stay measurable.
			light.light_energy = 0.9
			light.light_angular_distance = 1.0
			light.shadow_blur = 1.5
			light.directional_shadow_max_distance = 45.0
		light.shadow_enabled = true
		light.shadow_bias = 0.01
		light.shadow_normal_bias = 0.05
		var camera := Camera3D.new()
		camera.fov = 28.0
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		stage.add_child(camera)
		camera.current = true
		var points: Array[Vector3] = []
		var area := Rect2(-0.6, -0.6, 1.8, 1.8) if kind == "plant" else Rect2(-1.8, -1.8, 5.4, 5.4)
		for y in 80:
			for x in 80:
				points.append(Vector3(area.position.x + (x + 0.5) / 80.0 * area.size.x, 0.01, area.position.y + (y + 0.5) / 80.0 * area.size.y))
		var baseline := PackedFloat32Array()
		for angle in [0.0, 60.0, 120.0]:
			var pitch := deg_to_rad(32.0)
			var yaw := deg_to_rad(angle)
			var focus := Vector3(0, 0.9, 0)
			camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 28.0
			camera.look_at(focus)
			for card in casters: card.hide()
			await frames()
			var clear := await photo()
			for card in casters: card.show()
			await frames()
			var shadow := await photo()
			var shades := PackedFloat32Array()
			var maximum := 0.0
			for point in points:
				var shade := clampf((sample(clear, camera, point) - sample(shadow, camera, point)) / maxf(0.001, sample(clear, camera, point)), 0.0, 1.0)
				shades.append(shade)
				maximum = maxf(maximum, shade)
			check(maximum > 0.1, "%s %d: casts a visible ground shadow" % [label, angle])
			var penumbra := 0
			for shade in shades:
				if shade > maximum * 0.2 and shade < maximum * 0.8: penumbra += 1
			check(penumbra > 40, "%s %d: a broad soft transition surrounds the clump" % [label, angle])
			if baseline.is_empty():
				baseline = shades
			else:
				var error := 0.0
				for index in shades.size(): error += absf(shades[index] - baseline[index])
				error /= shades.size()
				print(label, " yaw=", angle, " world shadow mean difference=", error, " penumbra samples=", penumbra)
				check(error < 0.035, "%s %d: world shadow remains stable through camera rotation" % [label, angle])
			if kind == "plant":
				var middle := Vector3(0.3, 0.01, 0.1)
				var darkness := 0.0
				# Measure a small world patch, rather than one PSSM texel at the dithered edge.
				for z in range(-2, 3):
					for x in range(-2, 3):
						var point := middle + Vector3(x * 0.04, 0, z * 0.04)
						darkness += sample(clear, camera, point) - sample(shadow, camera, point)
				darkness /= 25.0
				check(darkness > 0.04, "Neighboring plants share a continuous clump shadow")
		stage.queue_free()
		await frames(2)
	print("Soft foliage shadows: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
