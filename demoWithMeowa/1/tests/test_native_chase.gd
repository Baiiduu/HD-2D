extends SceneTree

## Ordinary chase keeps eligibility, shortest distance and live geometry; ties may differ.
class OraclePath extends TerrainPath:
	func legacy_chase(from: Vector3, target: Vector3, lookahead: float) -> PackedVector3Array:
		return _legacy_chase_route(from, target, lookahead)

	func shared_chase(from: Vector3, target: Vector3, lookahead: float) -> PackedVector3Array:
		return _smooth_chase_route(from, shared_pursuit_route(from, target), lookahead)

var path: OraclePath
var base: TerrainPath
var world: Node3D
var terrain: Terrain
var checks := 0
var failures: Array[String] = []
var formal := false
var output_path := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--formal": formal = true
		elif argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func settle(count := 3) -> void:
	for frame in count: await physics_frame

func fresh() -> void:
	path._goal_frame = -1
	path._pursuit_goal_id = -1

func old_route(from: Vector3, target: Vector3, lookahead: float) -> PackedVector3Array:
	path.native_chase_enabled = false
	fresh()
	var result := path.legacy_chase(from, target, lookahead)
	fresh()
	check(path.shared_chase(from, target, lookahead) == result, "Legacy chase matches a route rebuilt from shared pursuit")
	return result

func new_route(from: Vector3, target: Vector3, lookahead: float) -> PackedVector3Array:
	path.native_chase_enabled = true
	fresh()
	return path.chase_route(from, target, lookahead)

func route_length(route: PackedVector3Array) -> float:
	var length := 0.0
	for index in range(1, route.size()): length += route[index - 1].distance_to(route[index])
	return length

func rebuild() -> void:
	path.build(terrain, 0.32, [])
	path.prefetch_enabled = false

func wall(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.global_position = point + Vector3.UP * 0.5
	return body

func compare(label: String, from: Vector3, target: Vector3) -> void:
	# Positive but tiny lookahead exposes the full shortest route, allowing equal-cost ties.
	var raw_old := old_route(from, target, 0.000001)
	var builds: int = path.shared_field_builds
	var raw_new := new_route(from, target, 0.000001)
	check(raw_old.is_empty() == raw_new.is_empty(), label + ": same qualification/availability")
	check(path.shared_field_builds == builds, label + ": normal native chase never builds a GDScript whole-map field")
	if not raw_old.is_empty() and not raw_new.is_empty():
		check(raw_old[0] == raw_new[0] and raw_old[-1] == raw_new[-1], label + ": same selected origin connector and real/blocked endpoint")
		check(absf(route_length(raw_old) - route_length(raw_new)) <= 0.0001, label + ": actual 3D shortest route length retained; equal-cost ties allowed")
	for lookahead in [0.1, 1.0, 4.0, 8.0]:
		var expected := old_route(from, target, lookahead)
		var actual := new_route(from, target, lookahead)
		check(expected.is_empty() == actual.is_empty(), label + ": smoothed qualification")
		if not actual.is_empty() and not expected.is_empty():
			check(actual[-1] == expected[-1], label + ": smooth endpoint stays exact")
			if expected.size() > 1 and path._pursuit_start_clear(from, expected[1]):
				check(actual.size() > 1 and path._pursuit_start_clear(from, actual[1]), label + ": first movement connector keeps live wall/overlap safety")
	for lookahead in [0.0, -1.0]:
		check(old_route(from, target, lookahead) == new_route(from, target, lookahead), label + ": zero/negative lookahead preserves exact old route")
	path.native_chase_enabled = false
	fresh()
	var shared_before: PackedVector3Array = path.shared_pursuit_route(from, target)
	path.native_chase_enabled = true
	fresh()
	check(path.shared_pursuit_route(from, target) == shared_before, label + ": shared_pursuit_route stays exact")

func compare_matrix(label: String) -> void:
	compare(label, Vector3(-5.7, 0.02, 5.1), Vector3.ZERO)
	compare(label, Vector3(1.52, 0.02, 0), Vector3(3.7, 0.02, -4.1))

func custom_and_direction_checks() -> void:
	var saved: AStar3D = path.graph
	path.graph = AStar3D.new()
	var ids: Array[int] = []
	for grid in [Vector2i(20, 20), Vector2i(21, 20), Vector2i(22, 20)]:
		var id: int = path._id(grid)
		ids.append(id)
		path.graph.add_point(id, path.grid_position(grid))
	path.graph.connect_points(ids[2], ids[1], false)
	path.graph.connect_points(ids[1], ids[0], false)
	var from: Vector3 = path.graph.get_point_position(ids[0])
	var target: Vector3 = path.graph.get_point_position(ids[2])
	for pair in [[from, target], [target, from]]:
		var expected := old_route(pair[0], pair[1], 4.0)
		check(new_route(pair[0], pair[1], 4.0) == expected, "Custom directed graph retains exact old chase")
		check(not path._native_graph_eligible(), "Custom graph explicitly bypasses native candidate")
	# White-box cached one-way fixture checks the native query's goal -> start direction.
	path._cache_graph()
	var expected_forward := old_route(from, target, 0.000001)
	var native_forward := new_route(from, target, 0.000001)
	check(not expected_forward.is_empty() and not native_forward.is_empty(), "Native qualification uses goal-outward connectivity on one-way edges")
	check(absf(route_length(expected_forward) - route_length(native_forward)) < 0.0001, "One-way native route keeps the goal-outward weighted distance")
	check(old_route(target, from, 0.000001).is_empty() == new_route(target, from, 0.000001).is_empty(), "Reverse one-way rejection/partial fallback matches legacy")
	path.graph = saved
	path._cache_graph()
	fresh()

func boundaries() -> void:
	compare_matrix("Flat ground and exact goal")
	for invalid in [Vector3.INF, Vector3(NAN, 0, 0)]:
		check(new_route(invalid, Vector3.ZERO, 4.0).is_empty(), "Invalid origin rejected")
		check(new_route(Vector3.ZERO, invalid, 4.0).is_empty(), "Invalid target rejected")
	var blocker := wall(Vector3.ZERO, Vector3(2.4, 2, 1.6))
	await settle()
	compare_matrix("New live wall before graph rebuild")
	rebuild()
	compare_matrix("Built wall and blocked/roof target")
	blocker.position.x = 4.0
	await settle()
	compare_matrix("Moved dynamic wall without cached cast")
	blocker.free()
	await settle()
	# Explicitly cover a fully new wall over an origin used in a previous call.
	var from := Vector3(-3.3, 0.02, 4.9)
	var old: PackedVector3Array = new_route(from, Vector3.ZERO, 4.0)
	var cover := wall(from, Vector3(0.8, 2, 0.8))
	await settle()
	check(new_route(from, Vector3.ZERO, 4.0).is_empty(), "Fresh overlapping wall invalidates the same origin immediately")
	cover.free()
	await settle()
	check(new_route(from, Vector3.ZERO, 4.0).is_empty() == old.is_empty(), "Origin recovers when dynamic covering wall is removed")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, true)
	await settle()
	rebuild()
	compare_matrix("Water body-edge rejection")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_BRIDGE, true)
	await settle()
	rebuild()
	compare_matrix("Bridge remains walkable")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, false)
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_BRIDGE, false)
	terrain.data.set_level(Vector2i.ZERO, 2)
	await settle()
	rebuild()
	compare_matrix("Disconnected raised target preserves partial fallback")
	terrain.data.set_level(Vector2i.ZERO, 0)
	await settle()
	rebuild()
	custom_and_direction_checks()
	path.native_chase_enabled = true
	fresh()
	var goal: int = path._prepare_pursuit_goal(Vector3(2, 0.02, -2))
	if goal >= 0:
		path.graph.set_point_disabled(goal, true)
		var expected := old_route(Vector3(-4, 0.02, 4), Vector3(2, 0.02, -2), 4.0)
		check(new_route(Vector3(-4, 0.02, 4), Vector3(2, 0.02, -2), 4.0) == expected, "Disabled goal falls back to exact original field semantics")
		path.graph.set_point_disabled(goal, false)

func write_result() -> void:
	if output_path.is_empty(): return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "formal_map": formal}, "	"))

func run() -> void:
	if formal:
		world = load("res://scenes/world/world.tscn").instantiate()
		world.get_node("LoadoutUI").save_enabled = false
		world.get_node("WavePrototype/RunGrowth").enabled = false
		root.add_child(world)
		current_scene = world
		var wave: WavePrototype = world.get_node("WavePrototype")
		while not wave._path_ready: await physics_frame
		await settle(16)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		base = wave._path
		terrain = base.terrain
	else:
		world = Node3D.new()
		terrain = Terrain.new()
		terrain.data = TerrainData.new()
		terrain.data.size = Vector2i.ZERO
		terrain.data.resize(Vector2i(-12, -12), Vector2i(25, 25))
		world.add_child(terrain)
		root.add_child(world)
		current_scene = world
		await settle()
	path = OraclePath.new()
	path.prefetch_enabled = false
	if formal:
		var wave: WavePrototype = world.get_node("WavePrototype")
		path.build(terrain, 0.32, [wave.player.get_rid()], wave.battle_area.grow(terrain.data.cell_size))
	else:
		path.build(terrain, 0.32, [])
	switch_checks()
	if not formal:
		await boundaries()
	else:
		for from: Vector3 in [Vector3(7.3, 0, 32.2), Vector3(8.7, 0, 33.4), Vector3(-3.3, 0, 42.3), Vector3(9.4, 0, 46.5), Vector3(-12.7, 0, 47)]:
			compare("Formal map actual wall-corner fixtures", from, Vector3(-5, 0, 42))
	write_result()
	world.queue_free()
	await settle()
	print("Native chase routes: %d checks, %d failures; %s" % [checks, failures.size(), output_path])
	quit(1 if not failures.is_empty() else 0)

func switch_checks() -> void:
	var controller := WavePrototype.new()
	var extra := TerrainPath.new()
	controller._paths_by_radius[0.4] = extra
	check(not controller.native_chase_enabled and not controller._path.native_chase_enabled and not extra.native_chase_enabled, "Generic controller/path defaults retain the old chase")
	controller.native_chase_enabled = true
	check(controller._path.native_chase_enabled and extra.native_chase_enabled, "Enabling the controller immediately updates all existing body radii")
	controller.native_chase_enabled = false
	check(not controller._path.native_chase_enabled and not extra.native_chase_enabled, "Disabling the controller immediately restores all existing body radii")
	controller.free()
