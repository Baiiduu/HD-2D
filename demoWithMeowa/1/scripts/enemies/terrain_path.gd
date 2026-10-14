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
var _pursuit_next: Dictionary = {}
var _pursuit_goal_id := -1
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

func _clear_surface_cache() -> void:
	_surface_cache.clear()
	_height_frame = -1

func build(source: Terrain, radius: float, exclude: Array[RID], world_bounds := Rect2()) -> void:
	terrain = source
	data = source.data
	_size = data.size*SUBDIVISIONS
	graph.clear()
	_pursuit_next.clear()
	_pursuit_goal_id = -1
	_goal_frame = -1
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	_query.shape = sphere
	_query.collision_mask = 1
	var obstacles: Array[RID] = exclude.duplicate()
	# Terrain edges are validated from their corner heights below. Sweeping a
	# straight line at a slope transition otherwise mistakes the floor for a wall.
	if source._generated:
		for body in source._generated.get_children():
			if body is StaticBody3D: obstacles.append(body.get_rid())
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

func _surface_heights(cell: Vector2i) -> PackedFloat32Array:
	if _height_data != data:
		if _height_data and _height_data.changed.is_connected(_clear_surface_cache): _height_data.changed.disconnect(_clear_surface_cache)
		_height_data = data
		_height_data.changed.connect(_clear_surface_cache)
		_clear_surface_cache()
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
	_query.transform = Transform3D(Basis.IDENTITY,from+Vector3.UP*_clearance)
	_query.motion = to-from
	return terrain.get_world_3d().direct_space_state.cast_motion(_query)[0] >= 0.999

func route(from: Vector3,to: Vector3) -> PackedVector3Array:
	if graph.get_point_count() == 0: return PackedVector3Array()
	var local := terrain.to_local(to)
	var coord := (Vector2(local.x,local.z)/data.cell_size-Vector2(data.origin)+Vector2.ONE*0.5)*SUBDIVISIONS
	var grid := Vector2i(floori(coord.x),floori(coord.y))
	if grid.x < 0 or grid.y < 0 or grid.x >= _size.x or grid.y >= _size.y or not graph.has_point(_id(grid)): return PackedVector3Array()
	var start := graph.get_closest_point(from)
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
	var start := graph.get_closest_point(from)
	var end := graph.get_closest_point(goal)
	var path := graph.get_point_path(start, end, allow_partial_path)
	if path.is_empty() or not _segment_clear(from, path[0]) or _point_blocked(path[-1]): return PackedVector3Array()
	return path

func _point_blocked(point: Vector3) -> bool:
	_query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * _clearance)
	_query.motion = Vector3.ZERO
	return not terrain.get_world_3d().direct_space_state.intersect_shape(_query, 1).is_empty()

## 身体贴墙时可能只碰到较大的导航留白，允许首段退开或沿边离开。
## cast_motion 忽略初始重叠，另查接触方向，不能借此向墙内或穿墙移动。
func _pursuit_start_clear(from: Vector3, to: Vector3) -> bool:
	if not _segment_clear(from, to): return false
	if not _point_blocked(from): return true
	var space := terrain.get_world_3d().direct_space_state
	var contacts := space.collide_shape(_query)
	var motion := to - from
	for index in range(0, contacts.size(), 2):
		var outward := contacts[index + 1] - contacts[index]
		if motion.dot(outward) < -0.000001: return false
	# 首段必须离开留白接触，且导航点不能被新障碍覆盖。
	return not _point_blocked(to)

## 同一个地面目标共用反向广度树，等距地形网格只遍历一次连通分量。
## 目标导航点变化或 build 重建时失效；动态终点遮挡每物理帧重新检查。
func _prepare_pursuit_field(target: Vector3) -> bool:
	if graph.get_point_count() == 0 or not target.is_finite(): return false
	var cell := data.world_to_cell(terrain.to_local(target))
	if not data.has_cell(cell) or (data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)): return false
	var goal := ground_position(target)
	var frame := Engine.get_physics_frames()
	if _goal_frame == frame and goal.is_equal_approx(_goal_position): return true
	_goal_frame = frame
	_goal_position = goal
	_goal_blocked = _point_blocked(goal)
	var end: int
	if _goal_blocked:
		end = graph.get_closest_point(goal)
	else:
		var local := terrain.to_local(goal)
		var coord := (Vector2(local.x, local.z) / data.cell_size - Vector2(data.origin) + Vector2.ONE * 0.5) * SUBDIVISIONS
		var grid := Vector2i(floori(coord.x), floori(coord.y))
		if grid.x < 0 or grid.y < 0 or grid.x >= _size.x or grid.y >= _size.y or not graph.has_point(_id(grid)):
			_goal_frame = -1
			return false
		end = _id(grid)
	if end == _pursuit_goal_id: return true
	_pursuit_goal_id = end
	_pursuit_next.clear()
	_pursuit_next[end] = end
	var open := PackedInt64Array([end])
	var cursor := 0
	while cursor < open.size():
		var point := open[cursor]
		cursor += 1
		for neighbor in graph.get_point_connections(point):
			if _pursuit_next.has(neighbor) or graph.is_point_disabled(neighbor): continue
			_pursuit_next[neighbor] = point
			open.append(neighbor)
	shared_field_builds += 1
	return true

## 只构造路径点，不对每只追击怪物重新执行 A*。物理移动仍逐帧保留真实碰撞。
func shared_pursuit_route(from: Vector3, target: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	if not from.is_finite() or not _prepare_pursuit_field(target): return result
	var start := graph.get_closest_point(from)
	if not _pursuit_next.has(start):
		# 保留原来的屋顶／隔断局部靠近行为，不能给刷怪和残怪判定伪造连通。
		return pursuit_route(from, target, true)
	var first := graph.get_point_position(start)
	if not _pursuit_start_clear(from, first): return result
	result.append(first)
	var point := start
	while point != _pursuit_goal_id:
		point = _pursuit_next[point]
		result.append(graph.get_point_position(point))
	if _goal_blocked:
		if _point_blocked(result[-1]): return PackedVector3Array()
	else:
		if not _segment_clear(result[-1], _goal_position): return PackedVector3Array()
		result.append(_goal_position)
	return result

## 刷怪／残怪仅检查共享连通性和实时首尾碰撞，不创建整条路线数组。
func shared_reachable(from: Vector3, target: Vector3) -> bool:
	if not from.is_finite() or not _prepare_pursuit_field(target): return false
	var start := graph.get_closest_point(from)
	if not _pursuit_next.has(start) or not _pursuit_start_clear(from, graph.get_point_position(start)): return false
	var end := graph.get_point_position(_pursuit_goal_id)
	return not _point_blocked(end) if _goal_blocked else _segment_clear(end, _goal_position)

static func horizontal_distance(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()
