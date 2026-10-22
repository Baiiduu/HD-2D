extends SceneTree
## Run with the actual Forward+ renderer to validate compute/raster shaders, resizing and focus.
## Optional user arg: --capture-dir=D:/.codexfile/work/city-night-fx

var failures: Array[String] = []
var checks := 0
var capture_dir := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	create_timer(120.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func frames(count: int) -> void:
	for i in count: await process_frame

func capture(name: String) -> void:
	if capture_dir.is_empty() or not RenderingServer.get_rendering_device(): return
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))
	check(error == OK, "Saved " + name)

func lit_pixels(image: Image, rect: Rect2i) -> int:
	var count := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.06: count += 1
	return count

func fixture_mote(parent: Node, at: Vector3, size: float) -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/visual/atmosphere_motes.gdshader")
	material.set_shader_parameter("box_size", Vector3.ZERO)
	material.set_shader_parameter("particle_size", size)
	material.set_shader_parameter("energy", 8.0)
	var quad := QuadMesh.new()
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	multimesh.set_instance_custom_data(0, Color(0.25, 0.5, 0.5, 0.5))
	var mote := MultiMeshInstance3D.new()
	mote.multimesh = multimesh
	mote.custom_aabb = AABB(Vector3.ONE * -1.0, Vector3.ONE * 2.0)
	parent.add_child(mote)
	mote.position = at - Vector3(0.35, 0, 0)

func verify_optics() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 320)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = 28.0
	camera.near = 0.05
	camera.far = 40.0
	viewport.add_child(camera)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	viewport.add_child(environment)
	var effect := HDRBokeh.new()
	effect.tilt_strength = 0.0
	effect.blur_pixels_1080 = 26.0
	effect.set_camera_state(12.0, camera.near, camera.far)
	var compositor := Compositor.new()
	compositor.compositor_effects = [effect]
	camera.compositor = compositor
	effect.enabled = false
	var pixels_per_meter := 320.0 / (2.0 * 4.0 * tan(deg_to_rad(14.0)))
	fixture_mote(viewport, Vector3(-48.0 / pixels_per_meter, 50.0 / pixels_per_meter, -4.0), 0.03)
	fixture_mote(viewport, Vector3(144.0 / pixels_per_meter, 150.0 / pixels_per_meter, -12.0), 0.09)
	await frames(12)
	await RenderingServer.frame_post_draw
	var sharp := viewport.get_texture().get_image()
	effect.enabled = true
	await frames(12)
	await RenderingServer.frame_post_draw
	var blurred := viewport.get_texture().get_image()
	var near_rect := Rect2i(192, 94, 32, 32)
	var focus_rect := Rect2i(288, 94, 32, 32)
	var before := lit_pixels(sharp, near_rect)
	var after := lit_pixels(blurred, near_rect)
	check(before > 0, "Production mote shader outputs visible HDR light")
	check(after > before + 4, "Out-of-focus highlight expands into a disc (%d -> %d pixels)" % [before, after])
	check(lit_pixels(blurred, Rect2i(192, 194, 32, 32)) == 0, "Scatter retains the highlight's vertical position")
	var preserved := true
	for y in range(focus_rect.position.y, focus_rect.end.y):
		for x in range(focus_rect.position.x, focus_rect.end.x):
			if sharp.get_pixel(x, y) != blurred.get_pixel(x, y): preserved = false
	check(preserved, "In-focus pixels remain exact while nearby highlights scatter")
	if not capture_dir.is_empty():
		sharp.save_png(capture_dir.path_join("optics-sharp.png"))
		blurred.save_png(capture_dir.path_join("optics-bokeh.png"))
	viewport.queue_free()
	await frames(4)

func run() -> void:
	var layout_hash := FileAccess.get_sha256("res://data/city_layout.json")
	var world_hash := FileAccess.get_sha256("res://scenes/world/world.tscn")
	var city: Node3D = load("res://scenes/city/city.tscn").instantiate()
	root.add_child(city)
	current_scene = city
	await frames(120)
	var effects: MapEffects = city.get_node("MapEffects")
	var atmosphere: NightAtmosphere = city.get_node("NightAtmosphere")
	var camera := effects.get_map_camera()
	var player: Player = city.get_node("Player")
	var art: ArtDirection = effects.get_node("ArtDirection")
	check(city.find_children("*", "Camera3D", true, false).size() == 1, "Exactly one city camera")
	check(city.find_children("*", "WorldEnvironment", true, false).size() == 1, "Exactly one city environment")
	check(art.moon == effects.get_node("Moon") and art.post_process == effects.get_node("PostProcess/Screen"), "Art direction binds the active render resources")
	check(root.get_camera_3d() == camera and camera.target == player, "Active camera follows the player")
	check(is_equal_approx(camera.fov, 28.0) and camera.distance == 28.0 and camera.pitch_degrees == 32.0, "City framing remains 28 degrees / 28m / 32 degrees")
	check(art.moon_color.b > art.moon_color.r and art.ambient_color.b > art.ambient_color.r, "Night uses cool moonlight and ambient fill")
	check(atmosphere._lamps.size() == 4 and atmosphere._groups.shafts.get_child_count() == 7, "Four existing lamps and three local moon shafts")
	check(atmosphere._groups.smoke.get_child_count() == 3 and atmosphere._groups.fire.get_child_count() == 4, "Roof/brazier smoke, flame, embers and warm fire light are present")
	check(not atmosphere._tree_materials.is_empty() and atmosphere._grass_materials.size() == 10, "Existing foliage and all five planters receive wind")
	var generated_id := atmosphere._generated.get_instance_id()
	var node_count := city.find_children("*", "", true, false).size()
	var camera_pose := camera.global_transform
	var clock := atmosphere._clock
	await frames(15)
	check(atmosphere._clock > clock, "Atmosphere continues to animate")
	atmosphere.wind_enabled = false
	await frames(3)
	check((atmosphere._tree_materials[0].get_shader_parameter("atmosphere_wind") as Vector2) == Vector2.ZERO, "Independent wind switch stops GPU displacement")
	atmosphere.wind_enabled = true
	atmosphere.smoke_enabled = false
	await frames(3)
	check(not atmosphere._groups.smoke.visible, "Smoke has an independent switch")
	atmosphere.smoke_enabled = true
	atmosphere.bokeh_enabled = false
	await frames(3)
	check(camera.dof_mode == 0, "Disabling HDR bokeh restores native depth of field")
	check(camera.global_transform.is_equal_approx(camera_pose), "Effect switches preserve camera pose")
	check(atmosphere._generated.get_instance_id() == generated_id and city.find_children("*", "", true, false).size() == node_count, "Toggles reuse batches and nodes")
	await capture("native-dof")
	atmosphere.bokeh_enabled = true
	await frames(8)
	if RenderingServer.get_rendering_device():
		check(camera.dof_mode == 2 and camera.compositor != null, "HDR compositor replaces native DOF")
		check(not (camera.attributes as CameraAttributesPractical).dof_blur_near_enabled, "Native and HDR depth of field never stack")
		var state := atmosphere.bokeh.debug_state()
		check(state.frames > 0 and not state.failed, "HDR compute and scatter stages rendered")
		camera.dof_enabled = false
		await frames(3)
		check(not atmosphere.bokeh.enabled and not (camera.attributes as CameraAttributesPractical).dof_blur_near_enabled, "Camera DOF master switch disables both paths")
		camera.dof_enabled = true
		await frames(3)
		player.set_physics_process(false)
		var spawn := player.position
		player.position = Vector3(-16, spawn.y, -2)
		camera.yaw_degrees = 60.0
		camera.snap_to_target()
		await frames(8)
		var chest_view := camera.global_transform.affine_inverse() * (player.global_position + Vector3.UP * camera.focus_height)
		check(absf(atmosphere.bokeh.debug_state().focus_depth + chest_view.z) < 0.02, "Focus follows chest view depth at a rotated, clamped map edge")
		player.position = spawn
		camera.yaw_degrees = 0.0
		camera.snap_to_target()
		await verify_optics()
		root.size = Vector2i(1301, 813)
		await frames(12)
		check(not atmosphere.bokeh.debug_state().failed, "Odd-sized resize recreates HDR buffers")
		root.size = Vector2i(1440, 900)
		await frames(45)
		await capture("city-night")
		camera.yaw_degrees = 45.0
		camera.snap_to_target()
		await frames(15)
		await capture("city-night-rotated")
		camera.yaw_degrees = 0.0
		camera.snap_to_target()
	check(FileAccess.get_sha256("res://data/city_layout.json") == layout_hash and FileAccess.get_sha256("res://scenes/world/world.tscn") == world_hash, "Layout data and formal world scene remain unchanged")
	atmosphere.set_process(false)
	if RenderingServer.get_rendering_device():
		atmosphere.queue_free()
		await frames(5)
		check(camera.compositor == null and camera.dof_mode == 0, "Removing atmosphere restores the camera and retires the HDR effect")
	for audio in city.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	city.queue_free()
	await frames(5)
	print(JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
