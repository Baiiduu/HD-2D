extends SceneTree

var checks := 0
var failures: Array[String] = []

class FixedPath extends TerrainPath:
	var fixed_goal := -1
	func _prepare_pursuit_goal(_target: Vector3) -> int:
		return fixed_goal

class ReferencePath extends FixedPath:
	var reference_distances := PackedFloat64Array()
	# The previous field builder is retained here as an exact tie/route oracle.
	func _prepare_pursuit_field(target: Vector3) -> bool:
		var end := _prepare_pursuit_goal(target)
		if end < 0: return false
		if end == _pursuit_goal_id: return true
		_pursuit_goal_id = end
		_dense_pursuit = false
		_pursuit_next.clear()
		_pursuit_next[end] = end
		reference_distances.resize(_size.x * _size.y)
		reference_distances.fill(INF)
		reference_distances[end] = 0.0
		var open: Array[int] = [end]
		var costs: Array[float] = [0.0]
		var cached := graph == _cached_graph and _cached_point_count > 0 and graph.get_point_count() == _cached_point_count
		while not open.is_empty():
			var point := open[0]
			var cost := costs[0]
			_reference_pop(open, costs)
			if cost > reference_distances[point]: continue
			var position := _point_positions[point] if cached else graph.get_point_position(point)
			var neighbors := _point_neighbors[point] if cached else graph.get_point_connections(point)
			for index in neighbors.size():
				var neighbor := neighbors[index]
				if graph.is_point_disabled(neighbor): continue
				var distance := cost + (_point_lengths[point][index] if cached else position.distance_to(graph.get_point_position(neighbor)))
				if distance >= reference_distances[neighbor] - 0.000001: continue
				reference_distances[neighbor] = distance
				_pursuit_next[neighbor] = point
				_reference_push(open, costs, neighbor, distance)
		shared_field_builds += 1
		return true
	func _reference_push(points: Array[int], costs: Array[float], point: int, cost: float) -> void:
		var index := points.size()
		points.append(point)
		costs.append(cost)
		while index > 0:
			var parent := (index - 1) / 2
			if costs[parent] <= cost: break
			points[index] = points[parent]
			costs[index] = costs[parent]
			index = parent
		points[index] = point
		costs[index] = cost
	func _reference_pop(points: Array[int], costs: Array[float]) -> void:
		var point: int = points.pop_back()
		var cost: float = costs.pop_back()
		if points.is_empty(): return
		var index := 0
		while index * 2 + 1 < points.size():
			var child := index * 2 + 1
			if child + 1 < points.size() and costs[child + 1] < costs[child]: child += 1
			if costs[child] >= cost: break
			points[index] = points[child]
			costs[index] = costs[child]
			index = child
		points[index] = point
		costs[index] = cost

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		if failures.size() < 12: push_error(message)
		failures.append(message)

func make_graph(side: int) -> AStar3D:
	var graph := AStar3D.new()
	for z in side:
		for x in side:
			# Two sparse walls leave different turns and disconnected pockets.
			if (x == side / 3 and z != side / 2) or (x == side * 2 / 3 and z != side / 3): continue
			graph.add_point(z * side + x, Vector3(x * 0.8, floorf(float(x) / 7.0) * 0.2, z * 0.8))
	for id in graph.get_point_ids():
		var x := id % side
		var z := id / side
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(1, -1)]:
			var next := Vector2i(x, z) + offset
			var next_id := next.y * side + next.x
			if next.x >= side or next.y < 0 or next.y >= side or not graph.has_point(next_id): continue
			graph.connect_points(id, next_id)
	return graph

func configure(path: FixedPath, graph: AStar3D, side: int) -> void:
	path.graph = graph
	path.data = TerrainData.new()
	path.data.size = Vector2i(side / 2, side / 2)
	path._size = Vector2i(side, side)
	path._cache_graph()

func route_ids(path: FixedPath, start: int) -> PackedInt64Array:
	var result := PackedInt64Array()
	if not path._field_has(start): return result
	var point := start
	result.append(point)
	while point != path._pursuit_goal_id and result.size() <= path.graph.get_point_count():
		point = path._pursuit_dense[point] if path._dense_pursuit else path._pursuit_next[point]
		result.append(point)
	return result

func compare_fields(actual: FixedPath, expected: ReferencePath, goals: PackedInt64Array, label: String) -> void:
	for goal in goals:
		actual.fixed_goal = goal
		expected.fixed_goal = goal
		actual._pursuit_goal_id = -1
		expected._pursuit_goal_id = -1
		check(actual._prepare_pursuit_field(Vector3.ZERO) and expected._prepare_pursuit_field(Vector3.ZERO), label + " builds both fields")
		var sampled := 0
		for id in actual.graph.get_point_ids():
			check(actual._field_has(id) == expected._field_has(id), label + " membership %d" % id)
			check(actual._field_distances[id] == expected.reference_distances[id], label + " exact distance %d" % id)
			if expected._field_has(id):
				var next: int = actual._pursuit_dense[id] if actual._dense_pursuit else actual._pursuit_next[id]
				check(next == expected._pursuit_next[id], label + " identical predecessor/tie %d" % id)
			if sampled % 13 == 0:
				check(route_ids(actual, id).to_byte_array() == route_ids(expected, id).to_byte_array(), label + " complete route %d" % id)
			sampled += 1

func benchmark(actual: FixedPath, expected: ReferencePath, goals: PackedInt64Array) -> void:
	var samples := {"before": [], "after": []}
	for round in 8:
		var order: Array[FixedPath] = [expected, actual]
		if round % 2 != 0: order.reverse()
		for path in order:
			var started := Time.get_ticks_usec()
			for goal in goals:
				path.fixed_goal = goal
				path._pursuit_goal_id = -1
				path._prepare_pursuit_field(Vector3.ZERO)
			samples["before" if path == expected else "after"].append(float(Time.get_ticks_usec() - started) / goals.size() / 1000.0)
	print("FIELD_BENCHMARK ", JSON.stringify({"points":actual.graph.get_point_count(),"ms_per_build":samples}))

func run() -> void:
	var graph := make_graph(24)
	var actual := FixedPath.new()
	var expected := ReferencePath.new()
	configure(actual, graph, 24)
	configure(expected, graph, 24)
	var ids := graph.get_point_ids()
	var goals := PackedInt64Array([ids[0], ids[ids.size() / 3], ids[ids.size() / 2], ids[-1]])
	compare_fields(actual, expected, goals, "weighted/ties")
	var capacity := actual._frontier_points.size()
	compare_fields(actual, expected, goals, "workspace reuse")
	check(actual._frontier_points.size() == capacity and actual._frontier_size == 0, "Repeated targets reuse the settled heap capacity")
	for id in ids:
		if id % 17 == 0: graph.set_point_disabled(id, true)
	compare_fields(actual, expected, goals, "live disabled nodes")
	for id in ids: graph.set_point_disabled(id, false)
	# A hand-built graph still takes the dictionary/native-adjacency fallback.
	var custom := AStar3D.new()
	for id in [1, 3, 8, 15]: custom.add_point(id, Vector3(id, id % 3, 0))
	for edge in [[15, 8], [8, 3], [3, 1]]: custom.connect_points(edge[0], edge[1], false)
	actual.graph = custom
	expected.graph = custom
	compare_fields(actual, expected, PackedInt64Array([15, 1]), "manual directed fallback")
	actual.graph = graph
	expected.graph = graph
	if "--benchmark" in OS.get_cmdline_user_args(): benchmark(actual, expected, goals)
	print("Pursuit tree workspace: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
