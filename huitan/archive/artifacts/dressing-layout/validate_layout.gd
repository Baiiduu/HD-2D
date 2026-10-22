extends SceneTree

const OUTPUT := "D:/Project/HD-2DMap/artifacts/dressing-layout/"
var failures: Array[String] = []
var scene: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	root.size = Vector2i(1280, 800)
	scene = load("res://scenes/four_realms.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 20:
		await physics_frame
	var dressing: Node3D = scene.get_node("World/GroundDressing")
	var terrain: Terrain = scene.get_node("World/Ground")
	var player: CharacterBody3D = scene.get_node("Player")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dressing_layout.json"))
	var visible_placements: Array = layout["instances"].filter(func(item: Dictionary) -> bool: return not String(item["asset"]).begins_with("pebbles_"))
	var categories := {"grass": 0, "flowers": 0, "pebbles": 0}
	var batches := dressing.find_children("*", "MultiMeshInstance3D", true, false)
	var total := 0
	for batch: MultiMeshInstance3D in batches:
		total += batch.multimesh.instance_count
	check(total == visible_placements.size(), "Rendered plant count differs from fixed layout")
	check(dressing.instance_count == total, "Dressing total does not match render batches")
	check(dressing.pebble_density == 0.0, "Pebbles must be disabled in the main scene")
	check(dressing.get_node("Layers/pebbles").get_child_count() == 0, "Pebbles are still rendered")
	check(dressing.find_children("*", "CollisionShape3D", true, false).is_empty(), "Dressing must not add collision")
	var ground_body: StaticBody3D = terrain.get_node("Generated/Body")
	for item: Dictionary in visible_placements:
		var coords: Array = item["position"]
		var point := Vector3(coords[0], coords[1], coords[2])
		var cell := terrain.data.world_to_cell(point - terrain.global_position)
		var category: String = item["asset"].get_slice("_", 0)
		categories[category] += 1
		check(terrain.data.has_cell(cell), "Placement outside terrain")
		for flag in [1, 2, 4, 8, 16]:
			check(not terrain.data.has_overlay(cell, flag), "Placement on path/water/ramp: %s" % point)
		if category != "pebbles":
			check(terrain.data.get_biome(cell) == TerrainData.Biome.WILD, "Plant outside grass biome")
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.6, point - Vector3.UP * 0.2)
		query.exclude = [player.get_rid()]
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "Placement has no surface below it: %s" % point)
		if not hit.is_empty():
			check(hit["collider"] == ground_body, "Placement intersects a prop: %s" % point)
			check(absf(hit["position"].y - point.y) < 0.015, "Placement height differs from actual ground: %s" % point)
			check(hit["normal"].y > 0.99, "Placement is not on flat ground: %s" % point)
	# Check that the three density controls reduce and restore only their layers.
	dressing.grass_density = 0.5
	dressing.flower_density = 0.5
	await process_frame
	await process_frame
	var reduced_count: int = dressing.instance_count
	check(reduced_count > 0 and reduced_count < total, "Density controls do not reduce instances")
	dressing.grass_density = 1.0
	dressing.flower_density = 1.0
	await process_frame
	await process_frame
	check(dressing.instance_count == total, "Restoring density does not restore fixed layout")
	var report := {"total": total, "categories": categories, "batches": batches.size(), "half_density_count": reduced_count, "failures": failures}
	FileAccess.open(OUTPUT + "validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	if DisplayServer.get_name() != "headless":
		await capture("start.png", Vector3(0.0, 0.3, 1.4))
		await capture("grass.png", Vector3(6.4, 0.3, 4.5))
		await capture("path-edge.png", Vector3(2.4, 0.3, 5.8))
		await capture("upper-west.png", Vector3(18.0, 0.3, -3.2))
		await capture("upper-east.png", Vector3(31.0, 0.3, -6.4))
	quit(0 if failures.is_empty() else 1)

func capture(filename: String, point: Vector3) -> void:
	var player: CharacterBody3D = scene.get_node("Player")
	var camera: FollowCamera = scene.get_node("Camera3D")
	var terrain: Terrain = scene.get_node("World/Ground")
	point.y = terrain.global_position.y + terrain.data.get_level(terrain.data.world_to_cell(point - terrain.global_position)) * terrain.data.layer_height + 0.3
	player.global_position = point
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	camera.snap_to_target()
	for frame in 35:
		await physics_frame
	camera.snap_to_target()
	for frame in 25:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT + filename)
	check(error == OK, "Screenshot failed: " + filename)
	print("Saved ", filename, " player=", player.global_position)
