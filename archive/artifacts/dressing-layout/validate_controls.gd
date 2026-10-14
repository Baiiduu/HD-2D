extends SceneTree

const OUTPUT := "D:/Project/HD-2DMap/artifacts/dressing-layout/"
var scene: Node3D
var dressing: Node3D
var failures: Array[String] = []

func _initialize() -> void:
	run_checks.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	await process_frame
	await process_frame
	await physics_frame

func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for batch: MultiMeshInstance3D in dressing.find_children("*", "MultiMeshInstance3D", true, false):
		var material: StandardMaterial3D = batch.multimesh.mesh.material
		var texture_path := material.albedo_texture.resource_path
		check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "Nearest pixel sampling changed")
		check(batch.multimesh.mesh.size.is_equal_approx(Vector2(1.125, 1.125)), "Native pixel scale changed")
		for index in batch.multimesh.instance_count:
			var point := batch.multimesh.get_instance_transform(index).origin - Vector3.UP * 0.46875
			result.append({"point": point, "texture": texture_path})
	check(result.size() == dressing.instance_count, "Rendered instance counter mismatch")
	return result

func check_surfaces(items: Array[Dictionary]) -> void:
	var terrain: Terrain = scene.get_node("World/Ground")
	var ground_body := terrain.get_node("Generated/Body")
	var player: CharacterBody3D = scene.get_node("Player")
	for item: Dictionary in items:
		var point: Vector3 = item["point"]
		var cell := terrain.data.world_to_cell(point - terrain.global_position)
		check(terrain.data.has_cell(cell), "Scatter escaped the map")
		for flag in [1, 2, 4, 8, 16]:
			check(not terrain.data.has_overlay(cell, flag), "Scatter entered a path, water or ramp")
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.6, point - Vector3.UP * 0.2)
		query.exclude = [player.get_rid()]
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "Scatter has no ground below it")
		if not hit.is_empty():
			check(hit["collider"] == ground_body, "Scatter intersects a prop")
			check(absf(hit["position"].y - point.y) < 0.015 and hit["normal"].y > 0.99, "Scatter did not land on flat ground")

func run_checks() -> void:
	root.size = Vector2i(1280, 800)
	scene = load("res://scenes/four_realms.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 25:
		await physics_frame
	dressing = scene.get_node("World/GroundDressing")
	var base := snapshot()
	check(base.size() == 103, "Default scene no longer has the original 103 plants")
	check(dressing.get_node("Layers/pebbles").get_child_count() == 0, "Default scene displays pebbles")
	var properties: Array[Dictionary] = dressing.get_property_list()
	for name in ["grass_density", "flower_density", "pebble_density"]:
		var property: Dictionary = properties.filter(func(item: Dictionary) -> bool: return item["name"] == name)[0]
		var limits: PackedStringArray = property["hint_string"].split(",")
		check(property["hint"] == PROPERTY_HINT_RANGE and limits[0].to_float() == 0.0 and limits[1].to_float() == 10.0, "Inspector density range is not 0 to 10")
	for name in ["grass_variants", "flower_variants", "pebble_variants"]:
		var property: Dictionary = properties.filter(func(item: Dictionary) -> bool: return item["name"] == name)[0]
		check(property["hint"] == PROPERTY_HINT_FLAGS and property["hint_string"].split(",").size() == 6, "Inspector resource picker is not a six-option multi-select")
	await capture("controls-base.png")
	dressing.grass_density = 2.0
	dressing.flower_density = 2.0
	await settle()
	var doubled := snapshot()
	check(doubled.size() > base.size(), "Density above 1 did not add plants")
	check_surfaces(doubled)
	await capture("controls-dense.png")
	dressing.grass_density = 10.0
	dressing.flower_density = 10.0
	await settle()
	var maximum := snapshot()
	check(maximum.size() > doubled.size(), "Density 10 did not add more plants than density 2")
	check_surfaces(maximum)
	dressing.grass_density = 1.0
	dressing.flower_density = 1.0
	await settle()
	check(snapshot() == base, "Restoring density 1 did not exactly restore the original layout")
	dressing.grass_variants = 1
	dressing.flower_variants = 1 << 4
	await settle()
	var selected := snapshot()
	check(selected.size() == base.size(), "Choosing resources altered the baseline quantity")
	for item: Dictionary in selected:
		check(item["texture"].ends_with("grass_01.png") or item["texture"].ends_with("flower_05.png"), "A deselected resource is still visible")
		check(base.any(func(original: Dictionary) -> bool: return original["point"].is_equal_approx(item["point"])), "Choosing resources moved a baseline point")
	await capture("controls-selected.png")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "Could not serialize editable configuration")
	check(ResourceSaver.save(packed, OUTPUT + "configuration-check.tscn") == OK, "Could not save editable configuration")
	var restored: Node3D = load(OUTPUT + "configuration-check.tscn").instantiate()
	var saved: Node3D = restored.get_node("World/GroundDressing")
	check(saved.grass_variants == 1 and saved.flower_variants == 16 and saved.pebble_density == 0.0, "Resource selection did not survive scene save/load")
	check(not saved.has_node("Layers"), "Transient scatter meshes were serialized")
	restored.free()
	dressing.grass_variants = 0
	dressing.flower_variants = 0
	await settle()
	check(snapshot().is_empty(), "Deselecting every resource did not clear the plants")
	dressing.pebble_density = 2.0
	dressing.pebble_variants = 4
	await settle()
	var stones := snapshot()
	check(stones.size() > 20, "Pebble density above 1 did not add pebbles")
	for item: Dictionary in stones:
		check(item["texture"].ends_with("pebble_03.png"), "A deselected pebble resource is still visible")
	check_surfaces(stones)
	dressing.pebble_density = 0.0
	dressing.pebble_variants = 63
	dressing.grass_variants = 63
	dressing.flower_variants = 63
	await settle()
	check(snapshot() == base, "Restoring the original selection did not restore the layout")
	var report := {"default_plants": base.size(), "density_2_plants": doubled.size(), "density_10_plants": maximum.size(), "selected_resources_plants": selected.size(), "density_2_pebbles": stones.size(), "failures": failures}
	FileAccess.open(OUTPUT + "controls-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var player: CharacterBody3D = scene.get_node("Player")
	var camera: FollowCamera = scene.get_node("Camera3D")
	player.global_position = Vector3(18.0, 1.12, -3.2)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	camera.snap_to_target()
	for frame in 30:
		await physics_frame
	camera.snap_to_target()
	for frame in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + filename) == OK, "Screenshot could not be saved")
