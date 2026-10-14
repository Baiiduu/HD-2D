extends SceneTree

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func run() -> void:
	var path := "res://data/world/world_terrain.tres"
	var source: TerrainData = load(path)
	var saved_hash := FileAccess.get_sha256(path)
	var area: CityPlaza = load("res://scenes/world/city_plaza.tscn").instantiate()
	area.position = Vector3(58.4,0,44)
	var edited := source.duplicate(true) as TerrainData
	var cell := Vector2i(-4,2)
	edited.heights[edited._index(cell)] = TerrainData.HEIGHT_OFFSET + 2
	edited.paints[edited._index(cell)] = 6
	edited.overlays[edited._index(cell)] = TerrainData.OVERLAY_DIRT
	var generated := area.make_terrain(edited)
	var core := area.get_core_rect()
	var connection := area.get_connection_rect()
	var flat := area.get_flat_rect()
	for z in edited.size.y:
		for x in edited.size.x:
			cell = edited.origin + Vector2i(x,z)
			if flat.has_point(Vector2(cell) * edited.cell_size) or connection.has_point(Vector2(cell) * edited.cell_size): continue
			var old := edited._index(cell)
			var new := generated._index(cell)
			assert(edited.heights[old] == generated.heights[new])
			assert(edited.biomes[old] == generated.biomes[new])
			assert(edited.overlays[old] == generated.overlays[new])
			assert(edited.paint_at_index(old) == generated.paint_at_index(new))
	for z in generated.size.y:
		for x in generated.size.x:
			cell = generated.origin + Vector2i(x,z)
			var point := Vector2(cell) * generated.cell_size
			if flat.has_point(point) or connection.has_point(point): assert(generated.get_level(cell) == 0)
			if core.has_point(point) or connection.has_point(point):
				assert(generated.get_biome(cell) == TerrainData.Biome.CITY)
				assert(generated.overlays[generated._index(cell)] == 0)
	area.free()
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	for frame in 12: await physics_frame
	var plaza: CityPlaza = world.get_node("CityPlaza")
	var battle: BattleArea = world.get_node("BattleArea")
	var terrain: Terrain = world.get_node("Homestead")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	assert(camera.fov == 28 and camera.distance == 28 and camera.pitch_degrees == 32)
	assert(camera.dof_enabled and is_equal_approx(camera.dof_amount,0.065))
	assert(camera.bounds_max.x > plaza.get_core_rect().end.x)
	assert(battle.get_activity_rect().end.x < plaza.get_core_rect().position.x)
	assert(battle.dressing_bounds == Rect2(-52,-26.4,104,123.2))
	var rebuilt := battle.make_terrain(terrain.data)
	for z in terrain.data.size.y:
		for x in terrain.data.size.x:
			cell = terrain.data.origin + Vector2i(x,z)
			var point := Vector2(cell) * terrain.data.cell_size
			if not plaza.get_flat_rect().has_point(point) and not plaza.get_connection_rect().has_point(point): continue
			var old := terrain.data._index(cell)
			var new := rebuilt._index(cell)
			assert(terrain.data.biomes[old] == rebuilt.biomes[new])
			assert(terrain.data.overlays[old] == rebuilt.overlays[new])
			assert(terrain.data.heights[old] == rebuilt.heights[new])
			assert(terrain.data.paint_at_index(old) == rebuilt.paint_at_index(new))
	var space := world.get_world_3d().direct_space_state
	for lane in [-2.9,0.0,2.9]:
		for step in 76:
			var point := Vector3(24.0 + step * 0.4, 2, 44.0 + lane)
			var query := PhysicsRayQueryParameters3D.create(point,point - Vector3.UP * 4,1)
			var hit := space.intersect_ray(query)
			assert(not hit.is_empty(), "Continuous floor through all three connection lanes")
			assert(absf(hit.position.y) < 0.015, "No steps or invisible barriers in the connection")
	assert(FileAccess.get_sha256(path) == saved_hash, "Loading and tests never save terrain")
	print("PASS: old cells and hand paint preserved outside authorized footprint; flat plaza/3-lane collision connection; old-area rebuild preserves new region; camera/DOF/bounds; no source writes")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	await create_timer(0.1).timeout
	world.queue_free()
	await process_frame
	await process_frame
	quit()
