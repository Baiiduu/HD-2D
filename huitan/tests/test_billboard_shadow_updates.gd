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

func frames(count := 20) -> void:
	for index in count: await process_frame

func photo() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func different_pixels(first: Image, second: Image) -> int:
	var count := 0
	for y in range(385, 485):
		for x in range(550, 730):
			var a := first.get_pixel(x,y)
			var b := second.get_pixel(x,y)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))) > 2.0/255.0: count += 1
	return count

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: billboard shadow pixel regression requires a native rendering driver")
		quit()
		return
	# Isolated shader probe: no gameplay, wind, post processing or temporal animation.
	root.positional_shadow_atlas_size = 1024
	for kind in ["plant", "character"]:
		var stage := Node3D.new()
		root.add_child(stage)
		current_scene = stage
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.2,0.2,0.2)
		stage.add_child(environment)
		var floor := MeshInstance3D.new()
		var floor_mesh := PlaneMesh.new()
		floor_mesh.size = Vector2(20,20)
		floor.mesh = floor_mesh
		stage.add_child(floor)
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/environment/vegetation_wind.gdshader" if kind == "plant" else "res://shaders/character/character_lighting.gdshader")
		material.set_shader_parameter("sprite_texture",load("res://assets/meowa/dressing/grass/grass_01.png" if kind == "plant" else "res://assets/meowa/player/idle_00.png"))
		if kind == "plant":
			material.set_shader_parameter("stable_shadows",false)
			material.set_shader_parameter("wind_strength",0.0)
		var card := MeshInstance3D.new()
		var card_mesh := QuadMesh.new()
		card_mesh.size = Vector2(1.125,1.125)
		card_mesh.material = material
		card.mesh = card_mesh
		card.position = Vector3(0,0.46875,0)
		stage.add_child(card)
		var light := SpotLight3D.new()
		light.position = Vector3(-3,6,-2)
		stage.add_child(light)
		light.look_at(Vector3.ZERO)
		light.light_energy = 3.0
		light.spot_range = 20.0
		light.spot_angle = 35.0
		light.shadow_enabled = true
		light.shadow_bias = 0.01
		light.shadow_normal_bias = 0.05
		var camera := Camera3D.new()
		camera.fov = 28.0
		stage.add_child(camera)
		camera.current = true
		camera.position = Vector3(0,15.738,23.745)
		camera.look_at(Vector3(0,0.9,0))
		await frames()
		camera.position = Vector3(sin(deg_to_rad(60))*23.745,15.738,cos(deg_to_rad(60))*23.745)
		camera.look_at(Vector3(0,0.9,0))
		await frames()
		var rotated := await photo()
		# A newly created identical light cannot reuse the previous camera's shadow cache.
		var fresh := light.duplicate() as SpotLight3D
		stage.remove_child(light)
		light.free()
		stage.add_child(fresh)
		await frames()
		var expected := await photo()
		var difference := different_pixels(rotated,expected)
		check(difference <= 10, "%s: rotated shadow matches a fresh render, different pixels=%d" % [kind,difference])
		stage.queue_free()
		await frames(3)
	print("Billboard shadow updates: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
