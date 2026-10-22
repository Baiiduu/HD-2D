extends SceneTree
## Enlarged overlapping ground regions and wide live/preview queries.
const QUERY = preload("res://scripts/combat/attack_surface_query.gd")
const VIEW = preload("res://scripts/combat/preview_spatial_query_view.gd")
const INDEX_ORACLE = preload("res://tests/test_spatial_index_reuse.gd")
class CountedTerrain extends Terrain:
	var corners_read := 0
	func _corner_heights(cell: Vector2i) -> PackedFloat32Array:
		corners_read += 1
		return super._corner_heights(cell)
class OriginalQuery extends "res://scripts/combat/attack_surface_query.gd":
	func _same_height(first: Vector2i, last: Vector2i, height: float) -> bool:
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var cell := Vector2i(x, z)
				if not _data.has_cell(cell): return false
				var bridge := _data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)
				if _data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not bridge: return false
				for corner in _terrain._corner_heights(cell):
					if not is_equal_approx(corner + (_data.layer_height if bridge else 0.0), height): return false
		return true

var checks := 0
var failures := 0
var world: Node3D

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func ground_checks() -> void:
	var terrain := CountedTerrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-16, -16), Vector2i(32, 32))
	world.add_child(terrain)
	await process_frame
	var query := QUERY.new()
	var old := OriginalQuery.new()
	query.configure(terrain, [])
	old.configure(terrain, [])
	var origins: Array[Vector3] = []
	for index in 24: origins.append(Vector3((index % 6) * 0.77 - 1.5, 0.0, (index / 6) * 0.81 - 1.2))
	terrain.corners_read = 0
	for origin in origins: check(old.flat_ground(origin, 8.0), "Original enlarged region is flat")
	var old_reads := terrain.corners_read
	terrain.corners_read = 0
	for origin in origins: check(query.flat_ground(origin, 8.0), "Overlapping enlarged regions retain exact flat eligibility")
	var new_reads := terrain.corners_read
	check(new_reads < old_reads * 0.7, "Overlapping sword/tail regions reuse their terrain blocks within one physics frame")
	print(JSON.stringify({"range_ground_corner_reads": {"before":old_reads, "after":new_reads}}))
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, true)
	check(not query.flat_ground(Vector3.ZERO, 8.0), "Water edits invalidate reused blocks immediately")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, false)
	check(query.flat_ground(Vector3.ZERO, 8.0), "Removing water restores exact flat eligibility")
	terrain.data.heights[terrain.data._index(Vector2i.ZERO)] = TerrainData.HEIGHT_OFFSET + 1
	await physics_frame
	check(not query.flat_ground(Vector3.ZERO, 8.0), "Raw height changes are reread at the next physics frame")
	terrain.data.heights.fill(TerrainData.HEIGHT_OFFSET + 1)
	terrain.data.emit_changed()
	check(query.flat_ground(Vector3.UP * 0.8, 8.0), "A uniform raised plane qualifies at its actual height")
	terrain.data.layer_height = 0.6
	check(not query.flat_ground(Vector3.UP * 0.8, 8.0), "Changing layer height cannot reuse an old plane in the same frame")
	check(query.flat_ground(Vector3.UP * 0.6, 8.0), "New layer height is read immediately")
	terrain.data.heights.fill(TerrainData.HEIGHT_OFFSET)
	terrain.data.emit_changed()
	# A rejected full block must not poison a smaller query covering only its flat part.
	terrain.data.set_overlay(Vector2i(-4, 0), TerrainData.OVERLAY_WATER, true)
	check(not query.flat_ground(Vector3.ZERO, 6.0), "An interior water cell rejects the wider region")
	check(query.flat_ground(Vector3.ZERO, 2.0), "Water outside a partial boundary block cannot reject the actual region")
	for cell in [Vector2i(-7, -2), Vector2i(3, 4), Vector2i(1, 0)]:
		terrain.data.set_level(cell, 1)
		terrain.data.set_overlay(cell + Vector2i.LEFT, TerrainData.OVERLAY_RAMP, true)
	terrain.data.set_overlay(Vector2i(6, 3), TerrainData.OVERLAY_BRIDGE | TerrainData.OVERLAY_WATER, true)
	for origin in [Vector3.ZERO, Vector3(-8, 0, -4), Vector3(10, 0.6, 5)]:
		for radius in [0.1, 1.0, 2.0, 4.0, 8.0, 40.0]:
			check(query.flat_ground(origin, radius) == old.flat_ground(origin, radius), "Block reuse preserves exact water/ramp/bridge/missing-cell eligibility")
	var previous := terrain.data
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-16, -16), Vector2i(32, 32))
	check(query.flat_ground(Vector3.ZERO, 8.0), "Replacing terrain data discards all old block results")
	check(not previous.changed.is_connected(query.clear_cache), "Replacing data disconnects the former invalidator")
	check(query.unclipped_flat(Vector3.ZERO, 8.0), "An open enlarged region is unobstructed")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	wall.add_child(collision)
	wall.position = Vector3(2, 0.5, 0)
	world.add_child(wall)
	await physics_frame
	check(query.flat_ground(Vector3.ZERO, 8.0), "A live wall does not change flat terrain eligibility")
	check(not query.unclipped_flat(Vector3.ZERO, 8.0), "A new live wall is checked despite cached flat blocks")
	wall.position.x = 30
	wall.force_update_transform()
	check(query.unclipped_flat(Vector3.ZERO, 8.0), "Moving a wall is observed in the same physics frame")
	wall.free()
	query.dispose()
	old.dispose()
	terrain.free()

func compare_index(actual: WaveEnemySpatialIndex, old: RefCounted, battle: WavePrototype) -> void:
	for center in [Vector3.ZERO, Vector3(-3.2, 0.0, 1.9), Vector3(20.0, 0.0, 20.0)]:
		for radius in [0.4, 1.5, 4.0, 8.0, 16.0, 40.0]:
			var expected: Array[WaveEnemy] = old.nearby(center, radius)
			check(actual.nearby(center, radius) == expected, "Wide and ordinary queries preserve exact distance and original z/x/insertion order")
			var excluded: Dictionary[int, bool] = {}
			if not expected.is_empty(): excluded[expected[0].get_instance_id()] = true
			var found: Array[WaveEnemy] = []
			actual.nearby_into(center, radius, excluded, found)
			check(found == expected.filter(func(actor): return not excluded.has(actor.get_instance_id())), "Caller-buffer queries preserve exclusions and order")
			var view := VIEW.new(actual, battle)
			var slots: Array[int] = []
			view.nearby_slots_into(center, radius, excluded, slots)
			check(slots == found.map(func(actor): return view.slot(actor)), "Prediction and live enlarged-range queries retain identical candidates")

func spatial_checks() -> void:
	var actual := WaveEnemySpatialIndex.new()
	var old := INDEX_ORACLE.LegacyIndex.new()
	var battle := WavePrototype.new()
	var actors: Array[WaveEnemy] = []
	for index in 128:
		var actor := INDEX_ORACLE.ProbeEnemy.new() as WaveEnemy
		world.add_child(actor)
		actor.position = Vector3((index % 16) * 0.35 - 2.6, 0.0, (index / 16) * 0.35 - 1.1)
		actors.append(actor)
		actual.update(actor)
		old.update(actor)
	compare_index(actual, old, battle)
	for index in range(0, actors.size(), 3):
		actors[index].position += Vector3(10.0, 0.0, -7.0)
		actual.update(actors[index])
		old.update(actors[index])
	compare_index(actual, old, battle)
	for index in range(0, actors.size(), 2):
		actual.remove(actors[index])
		old.remove(actors[index])
	compare_index(actual, old, battle)
	actual.clear()
	old.clear()
	check(actual.nearby(Vector3.ZERO, 40.0).is_empty(), "Clearing removes every cached occupied cell")
	for actor in actors:
		actual.update(actor)
		old.update(actor)
	compare_index(actual, old, battle)
	battle.free()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	await ground_checks()
	spatial_checks()
	world.free()
	for frame in 3: await process_frame
	print("Range query work: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
