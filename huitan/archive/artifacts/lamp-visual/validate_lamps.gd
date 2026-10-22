extends SceneTree

const OUTPUT := "D:/Project/HD-2DMap/artifacts/lamp-visual/"
var failures: Array[String] = []
var scene: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for frame in 24:
		await process_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> Image:
	await settle()
	var image := root.get_texture().get_image()
	check(image.save_png(OUTPUT + name + ".png") == OK, "Screenshot failed: " + name)
	return image

func difference(a: Image, b: Image, area: Rect2i) -> float:
	var total := 0.0
	for y in range(area.position.y, area.end.y, 2):
		for x in range(area.position.x, area.end.x, 2):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			total += absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)
	return total / (area.size.x * area.size.y / 4.0)

func white_fraction(image: Image, area: Rect2i) -> float:
	var count := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var color := image.get_pixel(x, y)
			if minf(color.r, minf(color.g, color.b)) > 0.9:
				count += 1
	return float(count) / (area.size.x * area.size.y)

func position_player(point: Vector3) -> void:
	var player: CharacterBody3D = scene.get_node("Player")
	player.position = point
	player.reset_physics_interpolation()
	for frame in 45:
		await physics_frame
	scene.get_node("Camera3D").snap_to_target()

func run() -> void:
	root.size = Vector2i(1280, 800)
	scene = load("res://scenes/four_realms.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	# Freeze weather variation for comparisons; scene defaults remain unchanged.
	scene.get_node("Weather").enabled = false
	await position_player(Vector3(-0.6, 2.6, 0.0))
	var art: ArtDirection = scene.get_node("ArtDirection")
	var lamp: OmniLight3D = scene.get_node("World/City/StreetLight1")
	var cone: SpotLight3D = lamp.get_node("Cone")
	var emitter: MeshInstance3D = scene.get_node("World/City/Lantern1")
	var window: MeshInstance3D = scene.get_node("World/City/Window1_0_0")
	check(emitter.material_override != window.material_override, "Lamp emission still shares the window material")
	var tuned := await capture("validated-side")
	scene._set_fog(false)
	var no_fog := await capture("fog-off")
	check(not (lamp.get_node("Beam") as MeshInstance3D).visible, "Fog toggle left beam visible")
	check(not (lamp.get_node("Dust") as GPUParticles3D).visible, "Fog toggle left dust visible")
	scene._set_fog(true)
	scene._set_shadows(false)
	var no_shadow := await capture("shadows-off")
	check(not cone.shadow_enabled, "Shadow toggle failed")
	scene._set_shadows(true)
	scene._set_glow(false)
	await capture("glow-off")
	scene._set_glow(true)
	var saved := [art.street_light_color, art.cone_angle, art.street_fill_range, art.street_emission]
	art.street_light_color = Color(0.7, 0.8, 1.0)
	art.cone_angle = 32.0
	art.street_fill_range = 3.8
	art.street_emission = 0.8
	art.apply()
	check(cone.light_color == art.street_light_color and lamp.light_color == art.street_light_color, "Color control failed")
	check(is_equal_approx(cone.spot_angle, 32.0) and is_equal_approx(lamp.omni_range, 3.8), "Angle/range controls failed")
	check(is_equal_approx((emitter.material_override as StandardMaterial3D).emission_energy_multiplier, 0.8), "Emission control failed")
	check(is_equal_approx((window.material_override as StandardMaterial3D).emission_energy_multiplier, 2.8), "Lamp controls changed window emission")
	art.street_light_color = saved[0]
	art.cone_angle = saved[1]
	art.street_fill_range = saved[2]
	art.street_emission = saved[3]
	art.apply()
	check(cone.light_color == saved[0] and is_equal_approx(cone.spot_angle, saved[1]), "Parameter restoration failed")
	await position_player(Vector3(-2.4, 2.6, -1.5))
	await capture("under-lamp")
	await position_player(Vector3(-7.5, 2.6, -0.5))
	await capture("second-lamp")
	var area := Rect2i(310, 220, 260, 290)
	var original := Image.load_from_file(OUTPUT + "before-lamp.png")
	var before_white := white_fraction(original, area)
	var after_white := white_fraction(tuned, area)
	var fog_difference := difference(tuned, no_fog, area)
	var shadow_difference := difference(tuned, no_shadow, Rect2i(200, 400, 550, 180))
	check(after_white < before_white * 0.6, "Overexposed area did not shrink")
	check(fog_difference > 0.001, "Fog has no visible effect")
	check(shadow_difference > 0.001, "Shadows have no visible effect")
	var report := {"failures": failures, "before_white_fraction": before_white, "after_white_fraction": after_white, "fog_difference": fog_difference, "shadow_difference": shadow_difference}
	FileAccess.open(OUTPUT + "validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
