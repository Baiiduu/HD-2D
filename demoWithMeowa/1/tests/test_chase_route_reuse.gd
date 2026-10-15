extends SceneTree

var checks := 0
var failures: Array[String] = []
var world: Node3D
var terrain: Terrain
var path: Oracle

func _initialize() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for frame in 3: await physics_frame

func rebuild() -> void:
	path.build(terrain, 0.32, [])

func wall(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = point + Vector3.UP * 0.5
	return body

## Freeze the pre-optimisation route builder as an exact oracle on the same
## graph, endpoints and live physics world; timings never decide test success.
class Oracle extends TerrainPath:
	var watched_origin := Vector3.INF
	var origin_overlaps := 0
	var origin_sweeps := PackedVector3Array()
	func _point_blocked(point: Vector3) -> bool:
		if point == watched_origin: origin_overlaps += 1
		return super._point_blocked(point)
	func _segment_clear(from: Vector3, to: Vector3) -> bool:
		if from == watched_origin: origin_sweeps.append(to)
		return super._segment_clear(from, to)
	func watch(point: Vector3) -> void:
		watched_origin = point
		origin_overlaps = 0
		origin_sweeps.clear()
		_goal_frame = -1
	func legacy_shared(from: Vector3, target: Vector3) -> PackedVector3Array:
		var result := PackedVector3Array()
		if not from.is_finite() or not _prepare_pursuit_field(target): return result
		var closest := closest_point(from)
		var start := _pursuit_start_id(from, closest)
		if start < 0:
			# 保留原来的屋顶／隔断局部靠近行为，不能给刷怪和残怪判定伪造连通。
			if not _field_has(closest): return pursuit_route(from, target, true)
			return result
		var first := graph.get_point_position(start)
		# 怪物从索引 1 开始行走；补选时保留首段，避免跳过转角连接而切墙。
		if start != closest: result.append(from)
		result.append(first)
		var point := start
		while point != _pursuit_goal_id:
			point = _pursuit_dense[point] if _dense_pursuit else _pursuit_next[point]
			result.append(graph.get_point_position(point))
		if _goal_blocked:
			if _point_blocked(result[-1]): return PackedVector3Array()
		else:
			if not _segment_clear(result[-1], _goal_position): return PackedVector3Array()
			result.append(_goal_position)
		return result

	## 实际追击在共享路线内前视，跳过空地上的格心；严格路线与连通判定保持独立。
	func legacy_chase(from: Vector3, target: Vector3, lookahead := 4.0) -> PackedVector3Array:
		var route := legacy_shared(from, target)
		if lookahead <= 0.0 or route.size() < 2 or not data: return route
		if horizontal_distance(from, route[-1]) <= lookahead * 2.0 and legacy_direct(from, route[-1]):
			return PackedVector3Array([from, route[-1]])
		for index in range(route.size() - 2, 1, -1):
			if horizontal_distance(from, route[index]) > lookahead: continue
			if not legacy_direct(from, route[index]): continue
			var result := PackedVector3Array([from])
			result.append_array(route.slice(index))
			return result
		return route

	func legacy_direct(from: Vector3, to: Vector3) -> bool:
		if not data or not from.is_finite() or not to.is_finite(): return false
		if not _pursuit_start_clear(from, to): return false
		if _flat_surface_between(from, to): return true
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

func compare_routes(label: String) -> void:
	var oracle := path as Oracle
	for from: Vector3 in [Vector3(-5, 0.02, 5), Vector3(0, 0.02, 5), Vector3(4, 0.02, 4), Vector3(0.99, 0.02, 0.99), Vector3(1.52, 0.02, 0), Vector3.ZERO, Vector3(0, 0.02, -0.81)]:
		for target: Vector3 in [Vector3.ZERO, Vector3(0, 2.0, 0), Vector3(3.7, 0.02, -4.1), from, Vector3(30, 0, 30)]:
			for lookahead in [0.0, 0.1, 1.0, 4.0, 8.0]:
				var expected := oracle.legacy_chase(from, target, lookahead)
				var actual := path.chase_route(from, target, lookahead)
				check(actual == expected, "%s: exact route from %s to %s ahead %.1f" % [label, from, target, lookahead])
			check(path.shared_pursuit_route(from, target) == oracle.legacy_shared(from, target), label + ": raw route stays exact")
	for invalid in [Vector3.INF, Vector3(NAN, 0, 0)]:
		check(path.chase_route(invalid, Vector3.ZERO).is_empty(), label + ": invalid origin")
		check(path.chase_route(Vector3.ZERO, invalid).is_empty(), label + ": invalid target")

func module_sample(legacy: bool, repetitions: int) -> float:
	var oracle := path as Oracle
	var start := Time.get_ticks_usec()
	for repeat in repetitions:
		for number in 128:
			var from := Vector3((number % 16 - 7.5) * 0.65, 0.02, (number / 16 - 3.5) * 0.65)
			if legacy: oracle.legacy_chase(from, Vector3.ZERO, 4.0)
			else: path.chase_route(from, Vector3.ZERO, 4.0)
	return float(Time.get_ticks_usec() - start) / repetitions / 1000.0

func collision_reuse_checks() -> void:
	var from := Vector3(-3.3, 0.02, 4.9)
	path.watch(from)
	var before := path.legacy_chase(from, Vector3.ZERO)
	var overlaps := path.origin_overlaps
	var sweeps := path.origin_sweeps.duplicate()
	path.watch(from)
	var after := path.chase_route(from, Vector3.ZERO)
	check(after == before and after.size() == 2, "direct route keeps the exact two endpoints")
	check(path.origin_sweeps == sweeps, "origin reuse retains every live directional sweep")
	check(overlaps == 2 and path.origin_overlaps == 1, "one search checks the unchanged origin once instead of twice")
	# The workspace must not survive the synchronous call: a new wall is live.
	var blocker := wall(from, Vector3(0.8, 2, 0.8))
	await settle()
	check(path.chase_route(from, Vector3.ZERO).is_empty(), "new wall at the same origin is not hidden by reused overlap results")
	blocker.free()
	await settle()
	check(path.chase_route(from, Vector3.ZERO) == before, "removing that wall restores the exact route")
	path.watched_origin = Vector3.INF

func run() -> void:
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-6, -6), Vector2i(13, 13))
	world.add_child(terrain)
	root.add_child(world)
	current_scene = world
	path = Oracle.new()
	path.prefetch_enabled = false
	await settle()
	rebuild()
	compare_routes("flat ground")
	await collision_reuse_checks()
	if "--benchmark" in OS.get_cmdline_user_args():
		module_sample(true, 5)
		module_sample(false, 5)
		var samples: Array = [[], []]
		for round_number in 3:
			for version in [0, 1, 1, 0]: samples[version].append(module_sample(version == 0, 30))
		print("Chase module ABBA ms / 128 routes: ", JSON.stringify(samples))
	var blocker := wall(Vector3.ZERO, Vector3(2.4, 2, 1.6))
	await settle()
	compare_routes("wall inserted after build")
	rebuild()
	compare_routes("built wall, blocked targets and padding contact")
	blocker.position.x = 4
	await settle()
	compare_routes("wall moved without build")
	blocker.free()
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, true)
	await settle()
	rebuild()
	compare_routes("water and body edges")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, false)
	terrain.data.set_level(Vector2i.ZERO, 2)
	await settle()
	rebuild()
	compare_routes("raised disconnected cell and roof fallback")
	world.queue_free()
	await settle()
	print("Chase route reuse: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
