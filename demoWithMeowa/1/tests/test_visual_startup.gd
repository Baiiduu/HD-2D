extends SceneTree

const PARAMETERS := ["wild_tint", "path_tint", "wild_surface", "path_surface", "lumina_relief_enabled",
	"pixel_palette_enabled", "pixel_grass_contrast", "grass_relief", "grass_root_occlusion", "grass_wet_response", "grass_sheen",
	"grass_variation_enabled", "grass_variation_strength", "grass_variation_size"]
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

func frames(count := 8) -> void:
	for index in count: await physics_frame
	await process_frame

func capture(material: ShaderMaterial) -> Dictionary:
	var values := {}
	for name in PARAMETERS: values[name] = material.get_shader_parameter(name)
	return values

func check_state(material: ShaderMaterial, expected: Dictionary, label: String) -> void:
	for name in PARAMETERS:
		var actual: Variant = material.get_shader_parameter(name)
		check(typeof(actual) == typeof(expected[name]) and actual == expected[name], label + ": " + name)

func key_r() -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_R
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.physical_keycode = KEY_R
	Input.parse_input_event(event)

func run() -> void:
	var source := "res://data/world/spawn_paint_palette.tres"
	var source_hash := FileAccess.get_sha256(source)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await frames(24)
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var terrain: Terrain = world.get_node("Homestead")
	var dressing := world.get_node("GroundDressing")
	var material := terrain.top_material
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	var player: Player = world.get_node("Player")
	player.set_physics_process(false)
	camera.set_process(false)
	var camera_pose := camera.global_transform
	var mesh := terrain._generated
	var startup := capture(material)
	check(sample.style == 0 and sample.original_light_refinement_enabled, "Refined original lighting is selected without R")
	check(startup.wild_tint == sample.ORIGINAL.palette_values[0].tint, "Startup grass tint matches the selected style")
	check(startup.path_tint == sample.ORIGINAL.palette_values[1].tint, "Startup road tint matches the selected style")
	check(not startup.lumina_relief_enabled and startup.pixel_palette_enabled, "Original lighting retains the independent pixel palette")
	check(startup.grass_relief == dressing.ground_relief and startup.grass_root_occlusion == dressing.root_occlusion, "Grass lighting uses the dressing controller")
	check(startup.grass_variation_enabled and is_equal_approx(startup.grass_variation_strength, sample.grass_variation_strength), "Meadow variation is enabled independently at startup")
	# 同一风格重新应用不应改变启动画面；旧代码在这里把白色草底改成风格色调。
	sample.apply_style()
	await frames()
	check_state(material, startup, "Reapplying the same style preserves startup")
	for style in [1, 2, 3, 0]:
		sample.style = style
		await frames()
		var expected := capture(material)
		check(expected.grass_variation_enabled and expected.grass_variation_size == sample.grass_variation_size, "Every style retains independent meadow variation")
		var emissions: Array[int] = [0]
		var count := func(_index, _title): emissions[0] += 1
		sample.style_changed.connect(count)
		# 模拟改画笔、材质或启动延迟刷新，不使用额外按键修复。
		terrain._queue_palette_apply()
		await frames()
		check_state(material, expected, "Late palette apply preserves style %d" % style)
		check(emissions[0] == 0, "Palette refresh does not reapply unrelated scene effects")
		sample.style_changed.disconnect(count)
	sample.style = 0
	await frames()
	for style in [1, 2, 3, 0]:
		key_r()
		await frames()
		check(sample.style == style, "R still cycles to %d" % style)
	check_state(material, startup, "R round trip returns to the initial grass")
	var plants: Node3D = dressing._generated
	sample.grass_variation_strength = 0.28
	sample.grass_variation_size = 4.5
	await frames()
	check(material.get_shader_parameter("grass_variation_strength") == 0.28 and material.get_shader_parameter("grass_variation_size") == 4.5, "Meadow strength and world size update independently")
	sample.style = 0
	await frames()
	check(material.get_shader_parameter("grass_variation_enabled") and material.get_shader_parameter("grass_variation_strength") == 0.28 and not material.get_shader_parameter("lumina_relief_enabled"), "Original lighting retains meadow variation with Lumina disabled")
	sample.grass_variation_enabled = false
	await frames()
	check(not material.get_shader_parameter("grass_variation_enabled"), "Meadow variation can be disabled independently")
	sample.style = 1
	await frames()
	check(not material.get_shader_parameter("grass_variation_enabled") and dressing._generated == plants, "Style preserves the meadow toggle and plants")
	check(camera.global_transform == camera_pose and terrain._generated == mesh, "Initialization repair preserves camera and terrain geometry")
	check(FileAccess.get_sha256(source) == source_hash, "Source paint palette remains unchanged")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	await create_timer(0.1).timeout
	world.free()
	await frames(2)
	print(JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
