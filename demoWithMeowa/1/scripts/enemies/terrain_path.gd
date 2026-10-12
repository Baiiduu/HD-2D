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

func build(source: Terrain, radius: float, exclude: Array[RID]) -> void:
	terrain = source
	data = source.data
	_size = data.size*SUBDIVISIONS
	graph.clear()
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
	for z in _size.y:
		for x in _size.x:
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
	var heights := terrain._corner_heights(cell)
	if data.has_overlay(cell,TerrainData.OVERLAY_BRIDGE):
		for i in heights.size(): heights[i] += data.layer_height
	return heights

func grid_position(grid: Vector2i) -> Vector3:
	var cell := _cell(grid)
	var fraction := (Vector2(Vector2i(grid.x % SUBDIVISIONS,grid.y % SUBDIVISIONS))+Vector2.ONE*0.5)/SUBDIVISIONS
	var corners := _surface_heights(cell)
	var height := lerpf(lerpf(corners[0],corners[1],fraction.x),lerpf(corners[3],corners[2],fraction.x),fraction.y)
	var xz := (Vector2(cell)+fraction-Vector2.ONE*0.5)*data.cell_size
	return terrain.to_global(Vector3(xz.x,height,xz.y))

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
	if path.is_empty() or not _segment_clear(path[-1],to): return PackedVector3Array()
	path.append(to)
	return path

static func horizontal_distance(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()
