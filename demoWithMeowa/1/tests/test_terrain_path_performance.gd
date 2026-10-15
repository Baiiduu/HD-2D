extends SceneTree

var checks := 0
var failures: Array[String] = []
var world: Node3D
var terrain: Terrain
var path: CountingPath

class CountingPath extends TerrainPath:
	var surface_checks := 0
	var body_checks := 0
	func _endpoint_surface_clear(from: Vector3, to: Vector3) -> bool:
		surface_checks += 1
		return super._endpoint_surface_clear(from, to)
	func _segment_clear(from: Vector3, to: Vector3) -> bool:
		body_checks += 1
		return super._segment_clear(from, to)
	func legacy_reachable(from: Vector3, target: Vector3) -> bool:
		if not from.is_finite() or not _prepare_pursuit_field(target): return false
		if _pursuit_start_id(from, graph.get_closest_point(from)) < 0: return false
		var end := graph.get_point_position(_pursuit_goal_id)
		return not _point_blocked(end) if _goal_blocked else _segment_clear(end, _goal_position)
	# The pre-optimization surface walk is the oracle for ramps and edge cases.
	func precise_walk(from: Vector3, to: Vector3) -> bool:
		if not data or not from.is_finite() or not to.is_finite(): return false
		if not _pursuit_start_clear(from, to): return false
		var offset := to - from
		offset.y = 0.0
		var side: Vector3 = Vector3.UP.cross(offset.normalized()) * _query.shape.radius
		var steps := maxi(1, ceili(offset.length() / (data.cell_size * 0.5)))
		for edge in [-1.0, 0.0, 1.0]:
			var first: Vector3 = from + side * edge
			var last: Vector3 = to + side * edge
			if not _endpoint_surface_clear(first, first): return false
			var first_y := ground_position(first).y
			var last_y := ground_position(last).y
			var previous := first
			for index in range(1, steps + 1):
				var fraction := float(index) / steps
				var point := first.lerp(last, fraction)
				if not _endpoint_surface_clear(previous, point): return false
				if absf(ground_position(point).y - lerpf(first_y, last_y, fraction)) > 0.05: return false
				previous = point
		return true

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func compare_walk(from: Vector3, to: Vector3, label: String) -> void:
	check(path.can_walk_direct(from, to) == path.precise_walk(from, to), label)

func compare_reachable(from: Vector3, to: Vector3, label: String) -> void:
	path._goal_frame = -1
	path._pursuit_goal_id = -1
	var actual := path.shared_reachable(from, to)
	# Force the oracle to rebuild from current disabled nodes/topology.
	path._goal_frame = -1
	path._pursuit_goal_id = -1
	check(actual == path.legacy_reachable(from, to), label)

func nearest_checks() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 15102026
	for index in 160:
		var point := Vector3(random.randf_range(-8, 20), random.randf_range(-2, 2), random.randf_range(-8, 20))
		check(path.closest_point(point) == path.graph.get_closest_point(point), "Exact closest point %d" % index)
	var ids := path.graph.get_point_ids()
	var first := ids[0]
	var second := path.graph.get_point_connections(first)[0]
	var midpoint := (path.graph.get_point_position(first) + path.graph.get_point_position(second)) * 0.5
	check(path.closest_point(midpoint) == path.graph.get_closest_point(midpoint), "Equal distances retain the lowest graph ID")
	path.graph.set_point_disabled(first, true)
	check(path.closest_point(path.graph.get_point_position(first)) == path.graph.get_closest_point(path.graph.get_point_position(first)), "Disabled nearest point is excluded")
	path.graph.set_point_disabled(first, false)
	check(path.closest_point(Vector3(0, 100, 0)) == path.graph.get_closest_point(Vector3(0, 100, 0)), "Elevated endpoint retains exact global fallback")
	var original := path.graph
	path.graph = AStar3D.new()
	for id in ids: path.graph.add_point(id, original.get_point_position(id) + Vector3(100, 5, -100))
	check(path.closest_point(Vector3(101, 0, -99)) == path.graph.get_closest_point(Vector3(101, 0, -99)), "Replacing a graph with the same point count invalidates its static index")
	path.graph = original
	# Existing navigation tests also replace the generated graph with hand-built fixtures.
	path.graph.clear()
	path.graph.add_point(901, Vector3(-5, 0, 3))
	path.graph.add_point(902, Vector3(8, 0, 3))
	check(path.closest_point(Vector3(1, 0, 3)) == path.graph.get_closest_point(Vector3(1, 0, 3)), "Hand-built graph falls back to its current points")
	path.build(terrain, 0.28, [])

func flat_checks() -> void:
	var from := Vector3(1.6, 0, 1.6)
	var to := Vector3(5.0, 0, 3.0)
	check(path.can_walk_direct(from, to), "Open flat surface is walkable")
	path.surface_checks = 0
	path.body_checks = 0
	for index in 20:
		compare_walk(from + Vector3.RIGHT * index * 0.01, to, "Flat precision %d" % index)
	path.surface_checks = 0
	var before := path.body_checks
	for index in 20: path.can_walk_direct(from, to)
	check(path.surface_checks == 0 and path.body_checks == before + 20, "Flat reuse skips only surface sampling, retains every live body query")
	var chunks := path._flat_chunks.duplicate()
	await settle()
	path.can_walk_direct(from, to)
	check(path._flat_chunks == chunks, "Static certification survives physics frames")
	compare_walk(from, from, "Zero-length walk preserves the precise result")
	compare_walk(Vector3(-4, 0, 0), from, "Outside-map edge remains rejected")
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.1, 1.2, 3.0)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(3, 0.6, 2)
	world.add_child(wall)
	await settle()
	check(not path.can_walk_direct(from, to), "A new wall blocks an already certified flat chunk")
	compare_walk(from, to, "Dynamic wall result matches precise sweep")
	wall.free()
	await settle()
	check(path.can_walk_direct(from, to), "Removing the wall restores travel without rebuilding surface data")

func reachability_checks() -> void:
	var from := Vector3(0, 0, 0)
	var target := Vector3(4.8, 0, 0)
	var builds := path.shared_field_builds
	for index in 12:
		check(path.shared_reachable(from, target + Vector3.BACK * index * 0.8), "Moving-target connectivity %d" % index)
	check(path.shared_field_builds == builds, "Moving residual/spawn checks do not build AI pursuit trees")
	check(not path.shared_pursuit_route(from, target).is_empty() and path.shared_field_builds > builds, "AI still builds its full exact pursuit tree when needed")
	compare_reachable(from, target, "Native connectivity matches the original full field")
	var disabled: Array[int] = []
	for id in path.graph.get_point_ids():
		var point := path.graph.get_point_position(id)
		if point.x > 1.0 and point.x < 2.1:
			path.graph.set_point_disabled(id, true)
			disabled.append(id)
	path._goal_frame = -1
	check(not path.shared_reachable(from, target), "A disabled strip is checked against the live graph")
	compare_reachable(from, target, "Disabled intermediate points match a freshly built original field")
	for id in disabled: path.graph.set_point_disabled(id, false)
	path._goal_frame = -1
	check(path.shared_reachable(from, target), "Re-enabling intermediate points restores connectivity immediately")
	var goal_id := path._prepare_pursuit_goal(target)
	path.graph.set_point_disabled(goal_id, true)
	compare_reachable(from, target, "Disabled goal retains the original full-field semantics")
	path.graph.set_point_disabled(goal_id, false)
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.2, 1.0)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = from + Vector3.UP * 0.6
	world.add_child(wall)
	await settle()
	check(not path.shared_reachable(from, target), "A dynamic wall covering the start still rejects residual connectivity")
	compare_reachable(from, target, "Dynamic start obstruction matches original wall-corner fallback")
	wall.position = target + Vector3.UP * 0.6
	await settle()
	compare_reachable(from, target, "Building-covered target preserves the original nearest safe endpoint")
	wall.free()
	for z in range(terrain.data.origin.y, terrain.data.origin.y + terrain.data.size.y):
		terrain.data.set_overlay(Vector2i(1, z), TerrainData.OVERLAY_WATER, true)
	await settle()
	path.build(terrain, 0.28, [])
	check(not path.shared_reachable(from, target), "A complete water strip remains disconnected")
	compare_reachable(from, target, "Water disconnection matches the original field")
	for z in range(terrain.data.origin.y, terrain.data.origin.y + terrain.data.size.y):
		terrain.data.set_level(Vector2i(1, z), -1)
		terrain.data.set_overlay(Vector2i(1, z), TerrainData.OVERLAY_BRIDGE, true)
	await settle()
	path.build(terrain, 0.28, [])
	check(path.shared_reachable(from, target), "Same-height bridges restore connectivity")
	compare_reachable(from, target, "Bridge connectivity matches the original field")
	for z in range(terrain.data.origin.y, terrain.data.origin.y + terrain.data.size.y):
		terrain.data.set_level(Vector2i(1, z), 0)
		terrain.data.set_overlay(Vector2i(1, z), TerrainData.OVERLAY_WATER, false)
		terrain.data.set_overlay(Vector2i(1, z), TerrainData.OVERLAY_BRIDGE, false)
	await settle()
	path.build(terrain, 0.28, [])
	# An intentionally one-way hand-built fixture retains the old goal-outward tree.
	var original := path.graph
	path.graph = AStar3D.new()
	var ids: Array[int] = []
	for grid in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]:
		var id := path._id(grid)
		ids.append(id)
		path.graph.add_point(id, path.grid_position(grid))
	path.graph.connect_points(ids[2], ids[1], false)
	path.graph.connect_points(ids[1], ids[0], false)
	compare_reachable(path.graph.get_point_position(ids[0]), path.graph.get_point_position(ids[2]), "One-way hand graph preserves goal-to-start reachability")
	compare_reachable(path.graph.get_point_position(ids[2]), path.graph.get_point_position(ids[0]), "One-way reverse query preserves the original rejection")
	path.graph = original
	path.build(terrain, 0.28, [])

func invalidation_checks() -> void:
	var from := Vector3(0, 0, 0)
	var to := Vector3(4.8, 0, 0)
	var cell := Vector2i(1, 0)
	terrain.data.set_overlay(cell, TerrainData.OVERLAY_WATER, true)
	check(path._flat_chunks.is_empty(), "Terrain change immediately invalidates flat certification")
	check(not path.can_walk_direct(from, to), "Water edited in the same frame cannot reuse old flat data")
	compare_walk(from, to, "Water edge matches precise sampling")
	terrain.data.set_level(cell, -1)
	terrain.data.set_overlay(cell, TerrainData.OVERLAY_BRIDGE, true)
	compare_walk(from, to, "Same-height bridge preserves walkability")
	terrain.data.set_overlay(cell, TerrainData.OVERLAY_BRIDGE, false)
	terrain.data.set_overlay(cell, TerrainData.OVERLAY_WATER, false)
	terrain.data.set_level(cell, 1)
	compare_walk(from, to, "Cliff does not become a flat shortcut")
	terrain.data.set_level(cell, 0)
	terrain.data.set_level(Vector2i(2, 0), 1)
	terrain.data.set_overlay(cell, TerrainData.OVERLAY_RAMP, true)
	for endpoint in [Vector3(1.3, 0, 0), Vector3(3.2, 0.8, 0), Vector3(2, 0, 0.4)]:
		compare_walk(from, endpoint, "Ramp and slope transition preserve exact interpolation")
	terrain.data.set_overlay(cell, TerrainData.OVERLAY_RAMP, false)
	terrain.data.set_level(Vector2i(2, 0), 0)
	path.can_walk_direct(from, to)
	var previous_layer := path._flat_layer_height
	terrain.data.layer_height *= 1.25
	compare_walk(from, to, "Direct layer-height changes keep exact surface result")
	check(path._flat_layer_height != previous_layer, "Layer-height metadata is refreshed without needing an emitted signal")
	var previous_cell_size := path._flat_cell_size
	terrain.data.cell_size += 0.1
	compare_walk(from, to, "Direct cell-size changes preserve precise surface results")
	check(path._flat_cell_size != previous_cell_size, "Cell-size changes refresh qualification metadata")
	terrain.position = Vector3(17, 2, -9)
	compare_walk(from + terrain.position, to + terrain.position, "Translated terrain refreshes the qualification context")
	check(path._flat_transform == terrain.global_transform, "Transform changes invalidate qualification metadata")
	terrain.rotation.y = 0.15
	path.surface_checks = 0
	compare_walk(terrain.to_global(from), terrain.to_global(to), "Rotated terrain uses precise fallback")
	check(path.surface_checks > 0, "Non-identity terrain basis cannot use the axis-aligned flat shortcut")
	terrain.rotation = Vector3.ZERO
	terrain.position = Vector3.ZERO
	var replacement := terrain.data.duplicate() as TerrainData
	replacement.set_overlay(cell, TerrainData.OVERLAY_WATER, true)
	terrain.data = replacement
	check(not path._flat_surface_between(from, to), "Terrain replacement cannot reuse certification while navigation rebuild is pending")
	path.data = replacement
	check(not path.can_walk_direct(from, to), "Replacing data does not reuse prior flat chunks")
	await settle()
	path.build(terrain, 0.28, [])
	check(path.closest_point(Vector3(0, 0, 0)) == path.graph.get_closest_point(Vector3(0, 0, 0)), "Rebuild refreshes nearest-point cache after geometry changes")

func run() -> void:
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-2, -2), Vector2i(15, 15))
	world.add_child(terrain)
	root.add_child(world)
	current_scene = world
	await settle()
	path = CountingPath.new()
	path.build(terrain, 0.28, [])
	nearest_checks()
	await flat_checks()
	await reachability_checks()
	await invalidation_checks()
	world.queue_free()
	await settle()
	path = null
	print("Terrain path performance: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
