class_name TerrainPath
extends RefCounted

# Half-cell spacing preserves narrow ramps and free space beside building steps.
const SUBDIVISIONS := 2
var terrain: Terrain
var graph := AStar3D.new()
var data: TerrainData
var _size := Vector2i.ZERO
var _query := PhysicsShapeQueryParameters3D.new()
var _clearance := 0.0
var _segment_certified := false
var _building_graph := false
# Query shape/configuration is owned by build(); only transform/motion change
# between lookahead calls. Copy native exclusions once per physics step.
var _query_config_frame := -1
var _query_shape: Shape3D
var _query_local_bounds := AABB(Vector3.INF, Vector3.ZERO)
var _query_excluded: Array[RID] = []
var _query_mask := 0
var _query_config_valid := false
var _pursuit_next: Dictionary = {}
var _dense_pursuit := false
var _pursuit_dense := PackedInt32Array()
var _field_distances := PackedFloat64Array()
var _field_enabled := PackedByteArray()
var _frontier_points := PackedInt32Array()
var _frontier_costs := PackedFloat64Array()
var _frontier_size := 0
var _pursuit_goal_id := -1
var _selected_goal_id := -1
var _goal_frame := -1
var _goal_position := Vector3.INF
var _goal_blocked := false
var shared_field_builds := 0
# Corner samples share one physics frame; terrain edits invalidate them immediately.
# Resource signals remove bound callbacks automatically when this path is released.
var _height_data: TerrainData
var _height_frame := -1
var _height_layer := -1.0
var _surface_cache: Dictionary[Vector2i, PackedFloat32Array] = {}
# Static surface chunks contain no obstacle results. Physics sweeps stay live.
const FLAT_CHUNK_SIZE := 8
var _flat_chunks: Dictionary[Vector2i, float] = {}
var _flat_rect := Rect2()
var _flat_cells := Rect2i()
var _flat_rect_height := NAN
var _flat_data: TerrainData
var _flat_transform := Transform3D.IDENTITY
var _flat_origin := Vector2i.ZERO
var _flat_size := Vector2i.ZERO
var _flat_cell_size := -1.0
var _flat_layer_height := -1.0
# These describe the graph built below, not moving entities or current blockers.
# Topology/point edits go through build; replaced/manual graphs use native lookup.
var _cached_graph: AStar3D
var _cached_point_count := 0
var _cached_point_ids := PackedInt64Array()
var _point_positions := PackedVector3Array()
var _point_neighbors: Array[PackedInt64Array] = []
var _point_lengths: Array[PackedFloat64Array] = []
var _nearest_cells: Dictionary[Vector2i, PackedInt64Array] = {}
var _nearest_cell_size := 1.0

## 普通追击可用原生点到点寻路；共享路线、连通资格与特殊移动仍保留原流程。
var native_chase_enabled := false
var _native_standard_costs := false
## Single-thread data backend for ordinary direct-walk planning only.
var chase_batch_enabled := true
var _chase_batch := PursuitQueryBatch.new()
var _chase_field: StaticObstacleField
var _chase_status := PackedByteArray()
var _chase_frame := -1
var _chase_revision := -1
var _chase_surface_ready := false
var _chase_transform := Transform3D.IDENTITY
var _chase_origin := Vector2i.ZERO
var _chase_size := Vector2i.ZERO
var _chase_layer_height := -1.0

# Prediction only. A missing or unfinished exact result never delays gameplay.
var prefetch_enabled := true
var prefetch_hits := 0
var prefetch_misses := 0
var prefetch_queued := 0
var _prefetch_owner := 0
var _prefetch_epoch := 0
var _prefetch_valid := false
var _prefetch_transform := Transform3D.IDENTITY
var _prefetch_origin := Vector2i.ZERO
var _prefetch_size := Vector2i.ZERO
var _prefetch_cell_size := 0.0
var _prefetch_layer_height := 0.0
var _prefetch_mask := PackedByteArray()
var _prefetch_last_position := Vector3.INF
var _prefetch_offsets := PackedInt32Array()
var _prefetch_edges := PackedInt32Array()
var _prefetch_lengths := PackedFloat64Array()

const PREFETCH_QUEUE_LIMIT := 4
const PREFETCH_RESULT_LIMIT := 12
static var _prefetch_owners: Dictionary[int, int] = {}
static var _prefetch_pending: Array[TreeJob] = []
static var _prefetch_results: Array[TreeJob] = []
static var _prefetch_running: TreeJob
static var _prefetch_task := -1
static var _prefetch_loop: WeakRef
static var _prefetch_kernel: GDScript
static var _prefetch_source := ""
static var _prefetch_kernel_version := 0

## A worker owns all mutable arrays. Input buffers are frozen copies created on
## the main thread; this object contains no TerrainPath, Node, AStar or physics.
class TreeJob extends RefCounted:
	var owner := 0
	var epoch := 0
	var goal := -1
	var offsets := PackedInt32Array()
	var edges := PackedInt32Array()
	var lengths := PackedFloat64Array()
	var enabled := PackedByteArray()
	var next := PackedInt32Array()
	var distances := PackedFloat64Array()
	# Production executes a separate, immutable in-memory copy of this kernel.
	# Saving/reloading TerrainPath cannot rewrite a running worker's functions.
	var kernel: RefCounted
	var kernel_version := 0
	var _points := PackedInt32Array()
	var _costs := PackedFloat64Array()
	var _count := 0
	func run() -> void:
		next.resize(enabled.size())
		next.fill(-1)
		distances.resize(enabled.size())
		distances.fill(INF)
		next[goal] = goal
		distances[goal] = 0.0
		_push(goal, 0.0)
		while _count > 0:
			var point := _points[0]
			var cost := _costs[0]
			_pop()
			if cost > distances[point]: continue
			var first := offsets[point * 2]
			for index in range(first, first + offsets[point * 2 + 1]):
				var neighbor := edges[index]
				if enabled[neighbor] == 0: continue
				var distance := cost + lengths[index]
				if distance >= distances[neighbor] - 0.000001: continue
				distances[neighbor] = distance
				next[neighbor] = point
				_push(neighbor, distance)
		# Finished results retain no heap workspace in the bounded result cache.
		_points = PackedInt32Array()
		_costs = PackedFloat64Array()
	func _push(point: int, cost: float) -> void:
		var index := _count
		if index == _points.size():
			var capacity := maxi(64, index * 2)
			_points.resize(capacity)
			_costs.resize(capacity)
		_count += 1
		while index > 0:
			var parent := (index - 1) / 2
			if _costs[parent] <= cost: break
			_points[index] = _points[parent]
			_costs[index] = _costs[parent]
			index = parent
		_points[index] = point
		_costs[index] = cost
	func _pop() -> void:
		_count -= 1
		var point := _points[_count]
		var cost := _costs[_count]
		if _count == 0: return
		var index := 0
		while index * 2 + 1 < _count:
			var child := index * 2 + 1
			if child + 1 < _count and _costs[child + 1] < _costs[child]: child += 1
			if _costs[child] >= cost: break
			_points[index] = _points[child]
			_costs[index] = _costs[child]
			index = child
		_points[index] = point
		_costs[index] = cost

func _init() -> void:
	_prefetch_owner = get_instance_id()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		TerrainPath._forget_prefetch(_prefetch_owner, true)

static func _forget_prefetch(owner: int, release: bool) -> void:
	if release: _prefetch_owners.erase(owner)
	for index in range(_prefetch_pending.size() - 1, -1, -1):
		if _prefetch_pending[index].owner == owner: _prefetch_pending.remove_at(index)
	for index in range(_prefetch_results.size() - 1, -1, -1):
		if _prefetch_results[index].owner == owner: _prefetch_results.remove_at(index)
	# A running job owns only its frozen inputs and may finish after its path dies.
	# The epoch/owner check below discards it, without waiting during scene changes.

static func _poll_prefetch() -> void:
	if _prefetch_task >= 0:
		if not WorkerThreadPool.is_task_completed(_prefetch_task): return
		_refresh_prefetch_kernel()
		WorkerThreadPool.wait_for_task_completion(_prefetch_task)
		if _prefetch_running.kernel:
			_prefetch_running.next = _prefetch_running.kernel.next
			_prefetch_running.distances = _prefetch_running.kernel.distances
			_prefetch_running.kernel = null
		if _prefetch_owners.get(_prefetch_running.owner, -1) == _prefetch_running.epoch and _prefetch_running.kernel_version == _prefetch_kernel_version:
			_prefetch_results.append(_prefetch_running)
			if _prefetch_results.size() > PREFETCH_RESULT_LIMIT: _prefetch_results.pop_front()
		_prefetch_running = null
		_prefetch_task = -1
	while not _prefetch_pending.is_empty():
		var job := _prefetch_pending.pop_front() as TreeJob
		if _prefetch_owners.get(job.owner, -1) != job.epoch: continue
		_prefetch_running = job
		_prefetch_task = WorkerThreadPool.add_task(job.kernel.run if job.kernel else job.run, false, "Terrain pursuit prediction")
		return
	_disconnect_prefetch_poll()

static func _connect_prefetch_poll() -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if not loop: return
	_prefetch_loop = weakref(loop)
	if not loop.process_frame.is_connected(_poll_prefetch): loop.process_frame.connect(_poll_prefetch)
	if not loop.root.tree_exiting.is_connected(_shutdown_prefetch): loop.root.tree_exiting.connect(_shutdown_prefetch)

static func _disconnect_prefetch_poll() -> void:
	var loop := _prefetch_loop.get_ref() as SceneTree if _prefetch_loop else null
	if loop and loop.process_frame.is_connected(_poll_prefetch): loop.process_frame.disconnect(_poll_prefetch)

static func _shutdown_prefetch() -> void:
	_prefetch_pending.clear()
	_prefetch_results.clear()
	_prefetch_owners.clear()
	# Only application teardown joins an unfinished task. Normal queries never do.
	if _prefetch_task >= 0: WorkerThreadPool.wait_for_task_completion(_prefetch_task)
	_prefetch_task = -1
	_prefetch_running = null
	_disconnect_prefetch_poll()
	_prefetch_loop = null

static func _refresh_prefetch_kernel() -> bool:
	# Called only for new goals/queued predictions, not per-monster physics ticks.
	# A source change also invalidates ready results from an older algorithm.
	var script: GDScript = load("res://scripts/enemies/terrain_path.gd")
	var source := script.source_code
	if _prefetch_kernel and source == _prefetch_source: return true
	var first := source.find("\nclass TreeJob extends RefCounted:\n")
	var last := source.find("\nfunc _init()", first)
	if first < 0 or last < 0: return false
	var lines := source.substr(first + 1, last - first - 1).split("\n")
	lines[0] = "extends RefCounted"
	for index in range(1, lines.size()): lines[index] = lines[index].trim_prefix("\t")
	var kernel := GDScript.new()
	kernel.source_code = "\n".join(lines)
	if kernel.reload() != OK: return false
	_prefetch_kernel = kernel
	_prefetch_source = source
	_prefetch_kernel_version += 1
	_prefetch_pending.clear()
	_prefetch_results.clear()
	return true

func _invalidate_prefetch() -> void:
	_prefetch_epoch += 1
	_prefetch_valid = false
	_prefetch_mask = PackedByteArray()
	_prefetch_last_position = Vector3.INF
	if _prefetch_owners.has(_prefetch_owner): _prefetch_owners[_prefetch_owner] = _prefetch_epoch
	TerrainPath._forget_prefetch(_prefetch_owner, false)

func _clear_surface_cache() -> void:
	_surface_cache.clear()
	_height_frame = -1

func _surface_changed() -> void:
	_chase_frame = -1
	_chase_surface_ready = false
	_chase_batch.valid = false
	_clear_surface_cache()
	_flat_chunks.clear()
	_flat_rect = Rect2()
	_flat_cells = Rect2i()
	_invalidate_prefetch()

func build(source: Terrain, radius: float, exclude: Array[RID], world_bounds := Rect2()) -> void:
	_building_graph = true
	invalidate_query_certificate()
	terrain = source
	data = source.data
	_surface_changed()
	_cached_graph = null
	_cached_point_count = 0
	_size = data.size*SUBDIVISIONS
	graph.clear()
	_pursuit_next.clear()
	_dense_pursuit = false
	_pursuit_goal_id = -1
	_selected_goal_id = -1
	_goal_frame = -1
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	_query.shape = sphere
	_query.collision_mask = 1
	var obstacles: Array[RID] = exclude.duplicate()
	# Terrain edges are validated from their corner heights below. Sweeping a
	# straight line at a slope transition otherwise mistakes the floor for a wall.
	if is_instance_valid(source._collision_body):
		obstacles.append(source._collision_body.get_rid())
	# Water blockers remain in every sweep, including shallow water and shores.
	_query.exclude = obstacles
	_query.motion = Vector3.ZERO
	_clearance = radius+0.08
	var space := source.get_world_3d().direct_space_state
	var first := Vector2i.ZERO
	var last := _size
	if world_bounds.has_area():
		var local_start := source.to_local(Vector3(world_bounds.position.x, 0, world_bounds.position.y))
		var local_end := source.to_local(Vector3(world_bounds.end.x, 0, world_bounds.end.y))
		first = Vector2i(((Vector2(local_start.x, local_start.z) / data.cell_size - Vector2(data.origin) + Vector2.ONE * 0.5) * SUBDIVISIONS).floor()).clamp(Vector2i.ZERO, _size)
		last = Vector2i(((Vector2(local_end.x, local_end.z) / data.cell_size - Vector2(data.origin) + Vector2.ONE * 0.5) * SUBDIVISIONS).ceil()).clamp(Vector2i.ZERO, _size)
	for z in range(first.y, last.y):
		for x in range(first.x, last.x):
			var grid := Vector2i(x,z)
			var cell := _cell(grid)
			if data.has_overlay(cell,TerrainData.OVERLAY_WATER) and not data.has_overlay(cell,TerrainData.OVERLAY_BRIDGE): continue
			var point := grid_position(grid)
			_query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*_clearance)
			if not space.intersect_shape(_query,1).is_empty(): continue
			graph.add_point(_id(grid),point)
	for id: int in graph.get_point_ids():
		var grid := Vector2i(id % _size.x,id / _size.x)
		for offset in [Vector2i.RIGHT,Vector2i.DOWN]:
			var next: Vector2i = grid+offset
			if next.x >= _size.x or next.y >= _size.y or not graph.has_point(_id(next)): continue
			if not _edges_meet(_cell(grid),_cell(next)): continue
			# Sweep the body clearance: thin walls can lie between free grid points.
			if not _segment_clear(graph.get_point_position(id),graph.get_point_position(_id(next))): continue
			graph.connect_points(id,_id(next))
	# 先完成正交连接，再检查斜向的两条绕角通路；水、断层与建筑夹角不能抄近路。
	for id: int in graph.get_point_ids():
		var grid := Vector2i(id % _size.x, id / _size.x)
		for offset in [Vector2i(1, -1), Vector2i(1, 1)]:
			var next: Vector2i = grid + offset
			if next.x >= _size.x or next.y < 0 or next.y >= _size.y: continue
			var end := _id(next)
			var side_x := _id(Vector2i(next.x, grid.y))
			var side_z := _id(Vector2i(grid.x, next.y))
			if not graph.has_point(end) or not graph.has_point(side_x) or not graph.has_point(side_z): continue
			if not graph.are_points_connected(id, side_x) or not graph.are_points_connected(side_x, end): continue
			if not graph.are_points_connected(id, side_z) or not graph.are_points_connected(side_z, end): continue
			if not _segment_clear(graph.get_point_position(id), graph.get_point_position(end)): continue
			graph.connect_points(id, end)
	_cache_graph()
	_building_graph = false

func _cache_graph() -> void:
	_invalidate_prefetch()
	_point_positions.resize(_size.x * _size.y)
	_point_neighbors.resize(_point_positions.size())
	_point_lengths.resize(_point_positions.size())
	_nearest_cells.clear()
	_nearest_cell_size = data.cell_size / SUBDIVISIONS
	var ids := graph.get_point_ids()
	_cached_point_ids = ids
	_pursuit_dense.resize(_point_positions.size())
	_field_distances.resize(_point_positions.size())
	_field_enabled.resize(_point_positions.size())
	for id in ids:
		var point := graph.get_point_position(id)
		_point_positions[id] = point
		var cell := Vector2i(floori(point.x / _nearest_cell_size), floori(point.z / _nearest_cell_size))
		var members: PackedInt64Array = _nearest_cells.get(cell, PackedInt64Array())
		members.append(id)
		_nearest_cells[cell] = members
	for id in ids:
		var neighbors := graph.get_point_connections(id)
		_point_neighbors[id] = neighbors
		var lengths := PackedFloat64Array()
		for neighbor in neighbors: lengths.append(_point_positions[id].distance_to(_point_positions[neighbor]))
		_point_lengths[id] = lengths
	_cached_graph = graph
	_cached_point_count = ids.size()
	# Publish fresh immutable buffers; never resize inputs held by an older job.
	var offsets := PackedInt32Array()
	var edges := PackedInt32Array()
	var lengths := PackedFloat64Array()
	offsets.resize(_point_positions.size() * 2)
	for id in ids:
		offsets[id * 2] = edges.size()
		offsets[id * 2 + 1] = _point_neighbors[id].size()
		for neighbor in _point_neighbors[id]: edges.append(neighbor)
		lengths.append_array(_point_lengths[id])
	_prefetch_offsets = offsets
	_prefetch_edges = edges
	_prefetch_lengths = lengths
	_prefetch_origin = data.origin
	_prefetch_size = data.size
	_prefetch_cell_size = data.cell_size
	_prefetch_layer_height = data.layer_height
	if is_instance_valid(terrain) and terrain.is_inside_tree():
		_prefetch_transform = terrain.global_transform
		_prefetch_valid = terrain.data == data
	_native_standard_costs = graph.get_script() == null
	for id in _cached_point_ids:
		if graph.get_point_weight_scale(id) != 1.0:
			_native_standard_costs = false
			break

func _can_prefetch() -> bool:
	if not prefetch_enabled or not _prefetch_valid: return false
	if not is_instance_valid(terrain) or terrain.data != data or terrain.global_transform != _prefetch_transform or data.origin != _prefetch_origin or data.size != _prefetch_size or data.cell_size != _prefetch_cell_size or data.layer_height != _prefetch_layer_height:
		_invalidate_prefetch()
		return false
	return true

func _refresh_prefetch_mask() -> void:
	if _prefetch_mask == _field_enabled: return
	_prefetch_epoch += 1
	TerrainPath._forget_prefetch(_prefetch_owner, false)
	_prefetch_mask = _field_enabled.duplicate()
	_prefetch_owners[_prefetch_owner] = _prefetch_epoch
	_prefetch_last_position = Vector3.INF

func _prefetched_tree(goal: int) -> TreeJob:
	if not TerrainPath._refresh_prefetch_kernel(): return null
	TerrainPath._poll_prefetch()
	for job in _prefetch_results:
		if job.owner == _prefetch_owner and job.epoch == _prefetch_epoch and job.goal == goal and job.enabled == _field_enabled:
			_prefetch_results.erase(job)
			_prefetch_results.append(job)
			return job
	return null

func _queue_tree(goal: int) -> void:
	if goal < 0 or _prefetch_pending.size() >= PREFETCH_QUEUE_LIMIT: return
	if not TerrainPath._refresh_prefetch_kernel(): return
	if _prefetch_running and _prefetch_running.owner == _prefetch_owner and _prefetch_running.epoch == _prefetch_epoch and _prefetch_running.goal == goal: return
	for job in _prefetch_pending:
		if job.owner == _prefetch_owner and job.epoch == _prefetch_epoch and job.goal == goal: return
	for job in _prefetch_results:
		if job.owner == _prefetch_owner and job.epoch == _prefetch_epoch and job.goal == goal: return
	var job := TreeJob.new()
	job.owner = _prefetch_owner
	job.epoch = _prefetch_epoch
	job.goal = goal
	job.offsets = _prefetch_offsets
	job.edges = _prefetch_edges
	job.lengths = _prefetch_lengths
	job.enabled = _prefetch_mask
	job.kernel_version = _prefetch_kernel_version
	job.kernel = _prefetch_kernel.new()
	job.kernel.goal = goal
	job.kernel.offsets = job.offsets
	job.kernel.edges = job.edges
	job.kernel.lengths = job.lengths
	job.kernel.enabled = job.enabled
	_prefetch_pending.append(job)
	_prefetch_owners[_prefetch_owner] = _prefetch_epoch
	prefetch_queued += 1
	TerrainPath._connect_prefetch_poll()
	TerrainPath._poll_prefetch()

func _predict_trees(goal: int) -> void:
	var previous := _prefetch_last_position
	_prefetch_last_position = _goal_position
	if not previous.is_finite() or not _goal_position.is_finite(): return
	var heading := _goal_position - previous
	heading.y = 0.0
	if heading.is_zero_approx(): return
	heading = heading.normalized()
	var first := -1
	var second := -1
	var first_score := 0.25
	var second_score := 0.25
	for neighbor in _point_neighbors[goal]:
		if _prefetch_mask[neighbor] == 0: continue
		var offset := _point_positions[neighbor] - _point_positions[goal]
		offset.y = 0.0
		var score := offset.normalized().dot(heading)
		if score > first_score:
			second = first
			second_score = first_score
			first = neighbor
			first_score = score
		elif score > second_score:
			second = neighbor
			second_score = score
	# Old queued predictions lose priority when the actual target turns.
	for index in range(_prefetch_pending.size() - 1, -1, -1):
		var job := _prefetch_pending[index]
		if job.owner == _prefetch_owner and job.goal != first and job.goal != second: _prefetch_pending.remove_at(index)
	_queue_tree(first)
	_queue_tree(second)

## Only return a local result when its distance proves every unvisited bucket
## farther away. Elevated/outside endpoints retain the exact full-graph fallback.
func closest_point(point: Vector3) -> int:
	if graph != _cached_graph or _cached_point_count == 0 or graph.get_point_count() != _cached_point_count or not point.is_finite():
		return graph.get_closest_point(point)
	var cell := Vector2i(floori(point.x / _nearest_cell_size), floori(point.z / _nearest_cell_size))
	var closest := -1
	var distance := 1e20
	for z in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			for id: int in _nearest_cells.get(Vector2i(x, z), PackedInt64Array()):
				if graph.is_point_disabled(id): continue
				var squared := point.distance_squared_to(_point_positions[id])
				if squared < distance or (squared == distance and (closest < 0 or id < closest)):
					closest = id
					distance = squared
	var boundary := minf(minf(point.x - (cell.x - 1) * _nearest_cell_size, (cell.x + 2) * _nearest_cell_size - point.x),
		minf(point.z - (cell.y - 1) * _nearest_cell_size, (cell.y + 2) * _nearest_cell_size - point.z))
	if closest >= 0 and distance < boundary * boundary * 0.999999: return closest
	return graph.get_closest_point(point)

func _id(grid: Vector2i) -> int:
	return grid.y*_size.x+grid.x

func _cell(grid: Vector2i) -> Vector2i:
	return data.origin+Vector2i(grid.x/SUBDIVISIONS,grid.y/SUBDIVISIONS)

func _edges_meet(cell: Vector2i,next: Vector2i) -> bool:
	if cell == next: return true
	var a := _surface_heights(cell)
	var b := _surface_heights(next)
	if next.x > cell.x:
		return is_equal_approx(a[1],b[0]) and is_equal_approx(a[2],b[3])
	return is_equal_approx(a[2],b[1]) and is_equal_approx(a[3],b[0])

func _bind_surface_data() -> void:
	if _height_data == data: return
	if _height_data and _height_data.changed.is_connected(_surface_changed): _height_data.changed.disconnect(_surface_changed)
	_height_data = data
	_height_data.changed.connect(_surface_changed)
	_surface_changed()

func _surface_heights(cell: Vector2i) -> PackedFloat32Array:
	_bind_surface_data()
	var frame := Engine.get_physics_frames()
	if frame != _height_frame or _height_layer != data.layer_height:
		_clear_surface_cache()
		_height_frame = frame
		_height_layer = data.layer_height
	if _surface_cache.has(cell): return _surface_cache[cell]
	var heights := terrain._corner_heights(cell)
	if data.has_overlay(cell,TerrainData.OVERLAY_BRIDGE):
		for i in heights.size(): heights[i] += data.layer_height
	_surface_cache[cell] = heights
	return heights

func grid_position(grid: Vector2i) -> Vector3:
	var cell := _cell(grid)
	var fraction := (Vector2(Vector2i(grid.x % SUBDIVISIONS,grid.y % SUBDIVISIONS))+Vector2.ONE*0.5)/SUBDIVISIONS
	var corners := _surface_heights(cell)
	var height := lerpf(lerpf(corners[0],corners[1],fraction.x),lerpf(corners[3],corners[2],fraction.x),fraction.y)
	var xz := (Vector2(cell)+fraction-Vector2.ONE*0.5)*data.cell_size
	return terrain.to_global(Vector3(xz.x,height,xz.y))

## 将跳跃中的目标投影回实际坡面；不能只取台地格子的基础高度。
func ground_position(world: Vector3) -> Vector3:
	var local := terrain.to_local(world)
	var cell := data.world_to_cell(local)
	var fraction := Vector2(local.x, local.z) / data.cell_size - Vector2(cell) + Vector2.ONE * 0.5
	var corners := _surface_heights(cell)
	local.y = lerpf(lerpf(corners[0], corners[1], fraction.x), lerpf(corners[3], corners[2], fraction.x), fraction.y)
	return terrain.to_global(local)

func _segment_clear(from: Vector3,to: Vector3) -> bool:
	_segment_certified = false
	if _query_certified_clear(from, to):
		_segment_certified = true
		return true
	_query.transform = Transform3D(Basis.IDENTITY,from+Vector3.UP*_clearance)
	_query.motion = to-from
	return terrain.get_world_3d().direct_space_state.cast_motion(_query)[0] >= 0.999

## Needed before direct edits to the private native query's configuration within
## an already queried physics step. build() and Shape resource edits do this too.
func invalidate_query_certificate() -> void:
	_query_config_frame = -1
	_chase_frame = -1
	_chase_batch.valid = false

func _prepare_query_config() -> bool:
	var frame := Engine.get_physics_frames()
	if _query_config_frame == frame: return _query_config_valid
	_query_config_frame = frame
	_query_config_valid = false
	if _query.collide_with_areas or not _query.collide_with_bodies: return false
	var shape := _query.shape
	if shape != _query_shape:
		if _query_shape and _query_shape.changed.is_connected(invalidate_query_certificate):
			_query_shape.changed.disconnect(invalidate_query_certificate)
		_query_shape = shape
		if shape: shape.changed.connect(invalidate_query_certificate)
	_query_local_bounds = StaticObstacleField.transformed_bounds(shape, Transform3D.IDENTITY).grow(_query.margin)
	if not _query_local_bounds.position.is_finite(): return false
	_query_excluded = _query.exclude
	_query_mask = _query.collision_mask
	_query_config_valid = true
	return true

func _query_certified_clear(from: Vector3, to: Vector3) -> bool:
	# Custom paths can override collision semantics; retain their original calls.
	if _building_graph or get_script() != TerrainPath or not is_instance_valid(terrain) or not terrain.obstacle_certificates_enabled or terrain.obstacle_query_backend == Terrain.ObstacleQueryBackend.NATIVE_QUERIES: return false
	if not from.is_finite() or not to.is_finite() or not _prepare_query_config(): return false
	var start := AABB(_query_local_bounds.position + from + Vector3.UP * _clearance, _query_local_bounds.size)
	var swept := start.merge(AABB(start.position + to - from, start.size))
	return terrain.obstacle_field().clear_query_bounds(swept, _query_mask, _query_excluded)

func route(from: Vector3,to: Vector3) -> PackedVector3Array:
	if graph.get_point_count() == 0: return PackedVector3Array()
	var local := terrain.to_local(to)
	var coord := (Vector2(local.x,local.z)/data.cell_size-Vector2(data.origin)+Vector2.ONE*0.5)*SUBDIVISIONS
	var grid := Vector2i(floori(coord.x),floori(coord.y))
	if grid.x < 0 or grid.y < 0 or grid.x >= _size.x or grid.y >= _size.y or not graph.has_point(_id(grid)): return PackedVector3Array()
	var start := closest_point(from)
	var end := _id(grid)
	var path := graph.get_point_path(start,end)
	if path.is_empty() or not _segment_clear(from,path[0]) or not _segment_clear(path[-1],to): return PackedVector3Array()
	path.append(to)
	return path

## 追击仍沿地面行走；建筑遮住目标落点时，走到附近可达的导航点。
## 普通 route 保持严格，用于通行、击退等必须到达原终点的判断。
## 刷怪与残怪保护要求连通；实际追击可允许局部路线先靠近建筑。
func pursuit_route(from: Vector3, target: Vector3, allow_partial_path := false) -> PackedVector3Array:
	if graph.get_point_count() == 0 or not from.is_finite() or not target.is_finite(): return PackedVector3Array()
	var cell := data.world_to_cell(terrain.to_local(target))
	if not data.has_cell(cell): return PackedVector3Array()
	if data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE): return PackedVector3Array()
	var goal := ground_position(target)
	if not _point_blocked(goal): return route(from, goal)
	var start := closest_point(from)
	var end := closest_point(goal)
	var path := graph.get_point_path(start, end, allow_partial_path)
	if path.is_empty() or not _segment_clear(from, path[0]) or _point_blocked(path[-1]): return PackedVector3Array()
	return path

func _point_blocked(point: Vector3) -> bool:
	if _query_certified_clear(point, point): return false
	_query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * _clearance)
	_query.motion = Vector3.ZERO
	return not terrain.get_world_3d().direct_space_state.intersect_shape(_query, 1).is_empty()

func _start_contact_points(from: Vector3) -> PackedVector3Array:
	# A previous candidate's sweep/end query may have changed these parameters.
	_query.transform = Transform3D(Basis.IDENTITY, from + Vector3.UP * _clearance)
	_query.motion = Vector3.ZERO
	return terrain.get_world_3d().direct_space_state.collide_shape(_query)

func _pursuit_start_clear_local(from: Vector3, to: Vector3, start: Array) -> bool:
	# Each direction keeps live obstacle checks. A full-volume empty proof also
	# proves the origin empty, so it needs neither a sweep nor an overlap query.
	# Local state: empty = unchecked, [0] = blocked, [1] = blocked-origin contacts.
	_segment_certified = false
	if not _segment_clear(from, to): return false
	if _segment_certified: return true
	if start.is_empty():
		start.append(_point_blocked(from))
		if start[0]: start.append(_start_contact_points(from))
	if not start[0]: return true
	return _pursuit_contacts_clear(from, to, start[1])

## 身体贴墙时可能只碰到较大的导航留白，允许首段退开或沿边离开。
## cast_motion 忽略初始重叠，另查接触方向，不能借此向墙内或穿墙移动。
func _pursuit_start_clear(from: Vector3, to: Vector3) -> bool:
	_segment_certified = false
	if not _segment_clear(from, to): return false
	if _segment_certified: return true
	if not _point_blocked(from): return true
	return _pursuit_contacts_clear(from, to, _start_contact_points(from))

func _pursuit_contacts_clear(from: Vector3, to: Vector3, contacts: PackedVector3Array) -> bool:
	var motion := to - from
	for index in range(0, contacts.size(), 2):
		var outward := contacts[index + 1] - contacts[index]
		# 球心已在实体内部时不是轻微留白接触，不能借邻点补选脱出新墙。
		if outward.length_squared() >= _query.shape.radius * _query.shape.radius: return false
		if motion.dot(outward) < -0.000001: return false
	# 首段必须离开留白接触，且导航点不能被新障碍覆盖。
	return not _point_blocked(to)

## 端点落在被障碍裁掉的半格或墙角时，只检查邻近九格，不能跨墙选全图最近点。
func _nearby_endpoint_ids(point: Vector3) -> Array[int]:
	var local := terrain.to_local(point)
	var coord := (Vector2(local.x, local.z) / data.cell_size - Vector2(data.origin) + Vector2.ONE * 0.5) * SUBDIVISIONS
	var center := Vector2i(floori(coord.x), floori(coord.y))
	var ids: Array[int] = []
	for z in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			if x < 0 or z < 0 or x >= _size.x or z >= _size.y: continue
			var id := _id(Vector2i(x, z))
			if graph.has_point(id) and not graph.is_point_disabled(id): ids.append(id)
	ids.sort_custom(func(a: int, b: int): return graph.get_point_position(a).distance_squared_to(point) < graph.get_point_position(b).distance_squared_to(point))
	return ids

## 邻点连接仍须跨过相接地表；球形碰撞排除了地形，不能借补选跨水或跨断层。
func _endpoint_surface_clear(from: Vector3, to: Vector3) -> bool:
	var local_from := terrain.to_local(from)
	var local_to := terrain.to_local(to)
	var first := data.world_to_cell(local_from)
	var last := data.world_to_cell(local_to)
	var offset := last - first
	if absi(offset.x) > 1 or absi(offset.y) > 1: return false
	var cells: Array[Vector2i] = [first]
	if offset.x != 0 and offset.y != 0:
		var x_cross := ((first.x + signi(offset.x) * 0.5) * data.cell_size - local_from.x) / (local_to.x - local_from.x)
		var z_cross := ((first.y + signi(offset.y) * 0.5) * data.cell_size - local_from.z) / (local_to.z - local_from.z)
		var middle := first + (Vector2i(offset.x, 0) if x_cross <= z_cross else Vector2i(0, offset.y))
		cells.append(middle)
		if is_equal_approx(x_cross, z_cross):
			# 恰穿格角时两侧都必须相接，避免从水格或断层角上抄近路。
			cells.append(last)
			cells.append(first + last - middle)
			cells.append(first)
	if not cells.has(last): cells.append(last)
	for index in cells.size():
		var cell := cells[index]
		if not data.has_cell(cell) or (data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)): return false
		if index == 0: continue
		var before := cells[index - 1]
		if cell == before: continue
		if not (_edges_meet(cell, before) if cell.x < before.x or cell.y < before.y else _edges_meet(before, cell)): return false
	return true

func _field_has(id: int) -> bool:
	return id >= 0 and id < _pursuit_dense.size() and _pursuit_dense[id] >= 0 if _dense_pursuit else _pursuit_next.has(id)

func _pursuit_start_id(from: Vector3, closest: int, start: Array = []) -> int:
	var cell := data.world_to_cell(terrain.to_local(from))
	if not data.has_cell(cell) or (data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)): return -1
	if _field_has(closest) and _pursuit_start_clear_local(from, graph.get_point_position(closest), start): return closest
	for id in _nearby_endpoint_ids(from):
		if id == closest or not _field_has(id): continue
		var point := graph.get_point_position(id)
		if _endpoint_surface_clear(from, point) and _pursuit_start_clear_local(from, point, start): return id
	return -1

## Resolve the same safe endpoint for AI, spawning and residual checks, without
## forcing the latter two to build an entire pursuit tree when the target moves.
func _prepare_pursuit_goal(target: Vector3) -> int:
	if graph.get_point_count() == 0 or not target.is_finite(): return -1
	var cell := data.world_to_cell(terrain.to_local(target))
	if not data.has_cell(cell) or (data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)): return -1
	var goal := ground_position(target)
	var frame := Engine.get_physics_frames()
	if _goal_frame == frame and goal.is_equal_approx(_goal_position): return _selected_goal_id
	_goal_frame = frame
	_goal_position = goal
	_goal_blocked = _point_blocked(goal)
	var end: int
	if _goal_blocked:
		end = closest_point(goal)
	else:
		var local := terrain.to_local(goal)
		var coord := (Vector2(local.x, local.z) / data.cell_size - Vector2(data.origin) + Vector2.ONE * 0.5) * SUBDIVISIONS
		var grid := Vector2i(floori(coord.x), floori(coord.y))
		end = _id(grid) if grid.x >= 0 and grid.y >= 0 and grid.x < _size.x and grid.y < _size.y and graph.has_point(_id(grid)) else -1
		if end < 0 or not _segment_clear(graph.get_point_position(end), goal):
			end = -1
			for id in _nearby_endpoint_ids(goal):
				var point := graph.get_point_position(id)
				if _endpoint_surface_clear(point, goal) and _segment_clear(point, goal):
					end = id
					break
			if end < 0:
				_goal_frame = -1
				_selected_goal_id = -1
				return -1
	_selected_goal_id = end
	return end

## 同一个地面目标共用反向最短路树；斜线与坡面的边长不同，使用真实距离。
## 目标导航点变化或 build 重建时失效；动态终点遮挡每物理帧重新检查。
func _prepare_pursuit_field(target: Vector3) -> bool:
	var end := _prepare_pursuit_goal(target)
	if end < 0: return false
	var cached := graph == _cached_graph and _cached_point_count > 0 and graph.get_point_count() == _cached_point_count
	var predict := cached and _can_prefetch()
	if end == _pursuit_goal_id: return true
	if cached:
		# Re-read current native flags before every new goal, including cache hits.
		for id in _cached_point_ids: _field_enabled[id] = int(not graph.is_point_disabled(id))
	if predict:
		predict = TerrainPath._refresh_prefetch_kernel()
	if predict:
		_refresh_prefetch_mask()
		var result := _prefetched_tree(end)
		if result:
			_pursuit_goal_id = end
			_pursuit_next.clear()
			_dense_pursuit = true
			# Packed buffers are references: active workspaces must not alias cache.
			_pursuit_dense = result.next.duplicate()
			_field_distances = result.distances.duplicate()
			prefetch_hits += 1
			_predict_trees(end)
			return true
		prefetch_misses += 1
	_pursuit_goal_id = end
	_pursuit_next.clear()
	_dense_pursuit = cached
	_field_distances.resize(_size.x * _size.y)
	_field_distances.fill(INF)
	_field_distances[end] = 0.0
	if cached:
		_pursuit_dense.fill(-1)
		_pursuit_dense[end] = end
	else:
		_pursuit_next[end] = end
	_frontier_size = 0
	_push_frontier(end, 0.0)
	while _frontier_size > 0:
		var point := _frontier_points[0]
		var cost := _frontier_costs[0]
		_pop_frontier()
		if cost > _field_distances[point]: continue
		var position := _point_positions[point] if cached else graph.get_point_position(point)
		var neighbors := _point_neighbors[point] if cached else graph.get_point_connections(point)
		var lengths := _point_lengths[point] if cached else PackedFloat64Array()
		for index in neighbors.size():
			var neighbor := neighbors[index]
			var disabled := _field_enabled[neighbor] == 0 if cached else graph.is_point_disabled(neighbor)
			if disabled: continue
			var distance := cost + (lengths[index] if cached else position.distance_to(graph.get_point_position(neighbor)))
			if distance >= _field_distances[neighbor] - 0.000001: continue
			_field_distances[neighbor] = distance
			if cached: _pursuit_dense[neighbor] = point
			else: _pursuit_next[neighbor] = point
			_push_frontier(neighbor, distance)
	shared_field_builds += 1
	if predict: _predict_trees(end)
	return true

## The heap keeps its storage between targets. Equal costs use the same parent/
## child comparisons and insertion order as the original parallel-array heap.
func _push_frontier(point: int, cost: float) -> void:
	var index := _frontier_size
	if index == _frontier_points.size():
		var capacity := maxi(64, index * 2)
		_frontier_points.resize(capacity)
		_frontier_costs.resize(capacity)
	_frontier_size += 1
	while index > 0:
		var parent := (index - 1) / 2
		if _frontier_costs[parent] <= cost: break
		_frontier_points[index] = _frontier_points[parent]
		_frontier_costs[index] = _frontier_costs[parent]
		index = parent
	_frontier_points[index] = point
	_frontier_costs[index] = cost

func _pop_frontier() -> void:
	_frontier_size -= 1
	var point := _frontier_points[_frontier_size]
	var cost := _frontier_costs[_frontier_size]
	if _frontier_size == 0: return
	var index := 0
	while index * 2 + 1 < _frontier_size:
		var child := index * 2 + 1
		if child + 1 < _frontier_size and _frontier_costs[child + 1] < _frontier_costs[child]: child += 1
		if _frontier_costs[child] >= cost: break
		_frontier_points[index] = _frontier_points[child]
		_frontier_costs[index] = _frontier_costs[child]
		index = child
	_frontier_points[index] = point
	_frontier_costs[index] = cost

## 只构造路径点，不对每只追击怪物重新执行 A*。物理移动仍逐帧保留真实碰撞。
func shared_pursuit_route(from: Vector3, target: Vector3) -> PackedVector3Array:
	return _build_pursuit_route(from, target, 0.0)

func _build_pursuit_route(from: Vector3, target: Vector3, lookahead: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	if not from.is_finite() or not _prepare_pursuit_field(target): return result
	var closest := closest_point(from)
	# Only this synchronous query owns these origin overlap/contact results.
	# Every direction still sweeps the current world and tests its endpoint.
	var origin_checks: Array = []
	var start := _pursuit_start_id(from, closest, origin_checks)
	if start < 0:
		# 保留原来的屋顶／隔断局部靠近行为，不能给刷怪和残怪判定伪造连通。
		if not _field_has(closest): return _smooth_chase_route(from, pursuit_route(from, target, true), lookahead)
		return result
	# Resolve and validate the same endpoint before materialising the field chain.
	# A clear short chase needs only two points; start eligibility, connectivity,
	# wall escape and the live final segment are still checked above/below.
	var end := graph.get_point_position(_pursuit_goal_id)
	if _goal_blocked:
		if _point_blocked(end): return result
	else:
		if not _segment_clear(end, _goal_position): return result
		end = _goal_position
	var at_least_two := start != closest or start != _pursuit_goal_id or not _goal_blocked
	if lookahead > 0.0 and at_least_two and horizontal_distance(from, end) <= lookahead * 2.0 and can_walk_direct(from, end, origin_checks):
		return PackedVector3Array([from, end])
	var first := graph.get_point_position(start)
	# 怪物从索引 1 开始行走；补选时保留首段，避免跳过转角连接而切墙。
	if start != closest: result.append(from)
	result.append(first)
	var point := start
	while point != _pursuit_goal_id:
		point = _pursuit_dense[point] if _dense_pursuit else _pursuit_next[point]
		result.append(graph.get_point_position(point))
	if not _goal_blocked: result.append(_goal_position)
	return _lookahead_route(from, result, lookahead, origin_checks)

## 实际追击在共享路线内前视，跳过空地上的格心；严格路线与连通判定保持独立。
func _legacy_chase_route(from: Vector3, target: Vector3, lookahead := 4.0) -> PackedVector3Array:
	# Unbuilt/custom paths retain the raw-route override used by standalone actors.
	if not data or lookahead <= 0.0: return shared_pursuit_route(from, target)
	return _build_pursuit_route(from, target, lookahead)

func _smooth_chase_route(from: Vector3, route: PackedVector3Array, lookahead: float) -> PackedVector3Array:
	if lookahead <= 0.0 or route.size() < 2 or not data: return route
	var origin_checks: Array = []
	if horizontal_distance(from, route[-1]) <= lookahead * 2.0 and can_walk_direct(from, route[-1], origin_checks):
		return PackedVector3Array([from, route[-1]])
	return _lookahead_route(from, route, lookahead, origin_checks)

func _lookahead_route(from: Vector3, route: PackedVector3Array, lookahead: float, origin_checks: Array) -> PackedVector3Array:
	if lookahead <= 0.0 or route.size() < 2 or not data: return route
	for index in range(route.size() - 2, 1, -1):
		if horizontal_distance(from, route[index]) > lookahead: continue
		if not can_walk_direct(from, route[index], origin_checks): continue
		var result := PackedVector3Array([from])
		result.append_array(route.slice(index))
		return result
	return route

## 静态通路可前视，身体扫掠仍检查当前墙体；地表沿中心和身体两侧逐段检查。
## origin_checks may only be reused inside one synchronous search at this origin.
func can_walk_direct(from: Vector3, to: Vector3, origin_checks: Array = []) -> bool:
	if _prepare_chase_batch():
		var status := _chase_batch.classify(from, to)
		if status == PursuitQueryBatch.CLEAR:
			_segment_certified = true
			return true
		# Near walls retain the original live overlap/sweep. The numeric terrain
		# qualification still applies, so do not repeat the same surface query.
		if status == 1: return _pursuit_start_clear_local(from, to, origin_checks)
	return _legacy_can_walk_direct(from, to, origin_checks)

## Numeric candidates share configuration, terrain and obstacle inputs. Native
## fallbacks remain ordered: the second candidate is not swept if the first wins.
func first_walkable_ground(from: Vector3, targets: PackedVector3Array) -> int:
	if not from.is_finite(): return -1
	var prepared := _prepare_chase_batch()
	if prepared: _chase_batch.plan_ground_candidates(from, targets, _chase_status)
	var origin_checks: Array = []
	for index in targets.size():
		if prepared and _chase_status[index] == PursuitQueryBatch.CLEAR: return index
		var to := targets[index]
		if not to.is_finite(): continue
		if prepared and _chase_status[index] == 1:
			if _pursuit_start_clear_local(from, to, origin_checks): return index
			continue
		if not prepared or _chase_status[index] == 0: to = ground_position(to)
		if _legacy_can_walk_direct(from, to, origin_checks): return index
	return -1

func _prepare_chase_batch() -> bool:
	if not chase_batch_enabled: return false
	var frame := Engine.get_physics_frames()
	if frame == _chase_frame and is_instance_valid(_chase_field) and _chase_revision == _chase_field.pursuit_revision and terrain.global_transform == _chase_transform and terrain.data == data:
		return _chase_batch.valid and _chase_field.enabled and terrain.obstacle_certificates_enabled
	if _building_graph or get_script() != TerrainPath or not is_instance_valid(terrain) or not data or terrain.data != data or not terrain.obstacle_certificates_enabled: return false
	var field := terrain.obstacle_field()
	if not field.enabled: return false
	_chase_field = field
	var transform := terrain.global_transform
	if transform != _chase_transform or data.origin != _chase_origin or data.size != _chase_size or data.cell_size != _chase_batch.cell_size or data.layer_height != _chase_layer_height:
		_chase_surface_ready = false
		_chase_frame = -1
	if frame == _chase_frame and _chase_revision == field.pursuit_revision: return _chase_batch.valid
	_chase_frame = frame
	_chase_revision = field.pursuit_revision
	_chase_batch.valid = false
	if transform.basis != Basis.IDENTITY or data.size.x <= 0 or data.size.y <= 0 or data.size.x * data.size.y > StaticObstacleField.MAX_DENSE_CELLS or not _prepare_query_config() or not _query.shape is SphereShape3D: return false
	_bind_surface_data()
	if not field.prepare_pursuit_batch(_chase_batch, _query_mask, _query_excluded):
		_chase_revision = field.pursuit_revision
		return false
	if not _chase_surface_ready:
		_chase_transform = transform
		_chase_origin = data.origin
		_chase_size = data.size
		_chase_layer_height = data.layer_height
		_chase_batch.origin = transform.origin
		_chase_batch.cell_size = data.cell_size
		_chase_batch.cells = Rect2i(data.origin, data.size)
		# Per-cell coplanar support, independent of the old eight-cell chunks.
		# A pond must not force every dry cell in its chunk through sampled walks.
		var stride := data.size.x + 1
		_chase_batch.terrain_prefix.resize(stride * (data.size.y + 1))
		_chase_batch.terrain_prefix.fill(0)
		_chase_batch.terrain_height = NAN
		for z in data.size.y:
			var row := 0
			for x in data.size.x:
				var cell := data.origin + Vector2i(x,z)
				var clear := not data.has_overlay(cell, TerrainData.OVERLAY_WATER | TerrainData.OVERLAY_BRIDGE | TerrainData.OVERLAY_RAMP)
				if clear:
					var heights := _surface_heights(cell)
					if is_nan(_chase_batch.terrain_height): _chase_batch.terrain_height = heights[0]
					for height in heights:
						if height != _chase_batch.terrain_height: clear = false
				if not clear: row += 1
				_chase_batch.terrain_prefix[(z + 1) * stride + x + 1] = _chase_batch.terrain_prefix[z * stride + x + 1] + row
		_chase_surface_ready = true
	_chase_batch.radius = _query.shape.radius
	_chase_batch.query_bounds = AABB(_query_local_bounds.position + Vector3.UP * _clearance, _query_local_bounds.size)
	_chase_batch.valid = true
	_chase_revision = field.pursuit_revision
	_chase_frame = frame
	return _chase_batch.valid

func _legacy_can_walk_direct(from: Vector3, to: Vector3, origin_checks: Array = []) -> bool:
	if not data or not from.is_finite() or not to.is_finite(): return false
	if not _pursuit_start_clear_local(from, to, origin_checks): return false
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
			# 地表折坡不以空中直线跨越，交回原路线逐点跟随。
			if absf(ground_position(point).y - lerpf(first_y, last_y, fraction)) > 0.05: return false
			previous = point
	return true

func _flat_chunk_height(chunk: Vector2i) -> float:
	if _flat_chunks.has(chunk): return _flat_chunks[chunk]
	var first := (chunk * FLAT_CHUNK_SIZE).max(data.origin)
	var last := ((chunk + Vector2i.ONE) * FLAT_CHUNK_SIZE).min(data.origin + data.size)
	var height := NAN
	for z in range(first.y, last.y):
		for x in range(first.x, last.x):
			var cell := Vector2i(x, z)
			if data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE):
				_flat_chunks[chunk] = NAN
				return NAN
			var corners := _surface_heights(cell)
			if is_nan(height): height = corners[0]
			for corner in corners:
				if corner != height:
					_flat_chunks[chunk] = NAN
					return NAN
	_flat_chunks[chunk] = height
	return height

## A conservative rectangle includes all three sampled lines. A chunk is only
## accepted when every corner is exactly coplanar and every cell walkable.
func _flat_surface_between(from: Vector3, to: Vector3) -> bool:
	return not is_nan(flat_ground_height(from, to))

## Only certifies terrain, never obstacles. Callers must still sweep their real body.
## NAN means water, slope, boundary or changed/unavailable terrain: use normal physics.
func flat_ground_height(from: Vector3, to: Vector3, body_radius := 0.0) -> float:
	# Existing navigation/body callers retain their conservative body width.
	if not _query.shape: return NAN
	if from.is_finite() and to.is_finite() and _prepare_chase_batch():
		var height := _chase_batch.ground_height(from, to, body_radius)
		if not is_nan(height): return height
	return _certified_ground_height(from, to, maxf(_query.shape.radius, body_radius))

## Terrain-only centerline certificate for flight's original center samples.
## Does not require a built AStar/query shape and never certifies live obstacles.
func flat_center_ground_height(from: Vector3, to: Vector3) -> float:
	# A custom ground_position can define a different surface. Only the known
	# ordinary path implementation may replace its original sampled results.
	if get_script() != TerrainPath: return NAN
	return _certified_ground_height(from, to, 0.0)

func _certified_ground_height(from: Vector3, to: Vector3, radius: float) -> float:
	if not is_instance_valid(terrain) or not data: return NAN
	# Data replacement precedes the controller's deferred navigation rebuild.
	if terrain.data != data:
		_flat_chunks.clear()
		_flat_rect = Rect2()
		_flat_cells = Rect2i()
		return NAN
	# Bind before checking any cache, including a first all-water chunk that
	# exits before _surface_heights. Same-frame edits must invalidate failures.
	_bind_surface_data()
	var transform := terrain.global_transform
	if _flat_data != data or _flat_transform != transform or _flat_origin != data.origin or _flat_size != data.size or _flat_cell_size != data.cell_size or _flat_layer_height != data.layer_height:
		_flat_chunks.clear()
		_flat_rect = Rect2()
		_flat_cells = Rect2i()
		_flat_data = data
		_flat_transform = transform
		_flat_origin = data.origin
		_flat_size = data.size
		_flat_cell_size = data.cell_size
		_flat_layer_height = data.layer_height
	if transform.basis != Basis.IDENTITY: return NAN
	# Reuse only a fully certified terrain rectangle, expanded by this body's
	# actual radius. Use the sampler's real world_to_cell rounding: at negative
	# half-cell boundaries, a floating rectangle's inclusive low edge belongs
	# to the previous cell. No wall, cast or actor result is retained here.
	var first := data.world_to_cell(Vector3(minf(from.x, to.x) - radius, 0.0, minf(from.z, to.z) - radius) - transform.origin)
	var last := data.world_to_cell(Vector3(maxf(from.x, to.x) + radius, 0.0, maxf(from.z, to.z) + radius) - transform.origin)
	if _flat_cells.has_point(first) and _flat_cells.has_point(last): return _flat_rect_height + transform.origin.y
	if not data.has_cell(first) or not data.has_cell(last): return NAN
	first = Vector2i(floori(float(first.x) / FLAT_CHUNK_SIZE), floori(float(first.y) / FLAT_CHUNK_SIZE))
	last = Vector2i(floori(float(last.x) / FLAT_CHUNK_SIZE), floori(float(last.y) / FLAT_CHUNK_SIZE))
	var height := NAN
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var next := _flat_chunk_height(Vector2i(x, z))
			if is_nan(next): return NAN
			if is_nan(height): height = next
			elif next != height: return NAN
	var low_cell := (first * FLAT_CHUNK_SIZE).max(data.origin)
	var high_cell := ((last + Vector2i.ONE) * FLAT_CHUNK_SIZE).min(data.origin + data.size)
	_flat_rect = Rect2((Vector2(low_cell) - Vector2.ONE * 0.5) * data.cell_size + Vector2(transform.origin.x, transform.origin.z), Vector2(high_cell - low_cell) * data.cell_size)
	_flat_cells = Rect2i(low_cell, high_cell - low_cell)
	_flat_rect_height = height
	return height + transform.origin.y

func _connected_start_id(from: Vector3, end: int) -> int:
	var cell := data.world_to_cell(terrain.to_local(from))
	if not data.has_cell(cell) or (data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)): return -1
	var closest := closest_point(from)
	var start: Array = []
	# Match the pursuit tree's goal-to-start reachability even for one-way edges.
	if closest >= 0 and not graph.get_id_path(end, closest).is_empty() and _pursuit_start_clear_local(from, graph.get_point_position(closest), start): return closest
	for id in _nearby_endpoint_ids(from):
		if id == closest: continue
		var point := graph.get_point_position(id)
		if _endpoint_surface_clear(from, point) and _pursuit_start_clear_local(from, point, start) and not graph.get_id_path(end, id).is_empty(): return id
	return -1

## Native point-to-point connectivity avoids a whole GDScript pursuit-tree build
## for each moving target checked by the spread-out residual/spawn work budget.
func shared_reachable(from: Vector3, target: Vector3) -> bool:
	if not from.is_finite(): return false
	var goal := _prepare_pursuit_goal(target)
	if goal < 0: return false
	if graph == _cached_graph and graph.get_point_count() == _cached_point_count and not graph.is_point_disabled(goal) and not graph.neighbor_filter_enabled:
		if _connected_start_id(from, goal) < 0: return false
	else:
		# Hand-built graphs and disabled-goal semantics retain the original field.
		if not _prepare_pursuit_field(target) or _pursuit_start_id(from, closest_point(from)) < 0: return false
	var end := graph.get_point_position(goal)
	return not _point_blocked(end) if _goal_blocked else _segment_clear(end, _goal_position)

static func horizontal_distance(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()


func _native_graph_eligible() -> bool:
	return data != null and _native_standard_costs and graph == _cached_graph and _cached_point_count > 0 and graph.get_point_count() == _cached_point_count and not graph.neighbor_filter_enabled

func chase_route(from: Vector3, target: Vector3, lookahead := 4.0) -> PackedVector3Array:
	if not native_chase_enabled or lookahead <= 0.0 or not _native_graph_eligible():
		return _legacy_chase_route(from, target, lookahead)
	var result := PackedVector3Array()
	if not from.is_finite(): return result
	var goal := _prepare_pursuit_goal(target)
	if goal < 0: return result
	# Disabled-goal semantics and custom native filters retain the original implementation.
	if graph.is_point_disabled(goal):
		return _legacy_chase_route(from, target, lookahead)
	var closest := closest_point(from)
	var start := -1
	var closest_checked := false
	var closest_reachable := false
	var ids := PackedInt64Array()
	var origin_checks: Array = []
	var cell := data.world_to_cell(terrain.to_local(from))
	var valid_origin := data.has_cell(cell) and not (data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE))
	if valid_origin:
		# Fuse _connected_start_id's reachability proof and route acquisition: a successful
		# get_id_path is retained, never immediately repeated with get_point_path.
		if closest >= 0:
			ids = graph.get_id_path(goal, closest)
			closest_checked = true
			closest_reachable = not ids.is_empty()
			if closest_reachable and _pursuit_start_clear_local(from, graph.get_point_position(closest), origin_checks): start = closest
		if start < 0:
			for id in _nearby_endpoint_ids(from):
				if id == closest: continue
				var point := graph.get_point_position(id)
				if not _endpoint_surface_clear(from, point) or not _pursuit_start_clear_local(from, point, origin_checks): continue
				var connected := graph.get_id_path(goal, id)
				if connected.is_empty(): continue
				start = id
				ids = connected
				break
	if start < 0:
		if not closest_checked and closest >= 0:
			closest_reachable = not graph.get_id_path(goal, closest).is_empty()
		# Preserve rooftop/disconnected local partial pursuit; no reachability is fabricated.
		if not closest_reachable:
			return _smooth_chase_route(from, pursuit_route(from, target, true), lookahead)
		return result
	var end := graph.get_point_position(goal)
	if _goal_blocked:
		if _point_blocked(end): return result
	else:
		if not _segment_clear(end, _goal_position): return result
		end = _goal_position
	var at_least_two := start != closest or start != goal or not _goal_blocked
	if at_least_two and horizontal_distance(from, end) <= lookahead * 2.0 and can_walk_direct(from, end, origin_checks):
		return PackedVector3Array([from, end])
	if start != closest: result.append(from)
	# Native path is goal -> start. Reverse only when materialising the chase route.
	for index in range(ids.size() - 1, -1, -1): result.append(graph.get_point_position(ids[index]))
	if not _goal_blocked: result.append(_goal_position)
	return _lookahead_route(from, result, lookahead, origin_checks)
