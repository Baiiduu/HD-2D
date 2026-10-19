class_name PursuitQueryBatch
extends RefCounted

## Value-only ordinary pursuit queries. The owner prepares inputs on the main
## thread; no Node, Resource, AStar or PhysicsServer is accessed by this kernel.
## Bits: terrain qualified = 1, swept obstacle volume also qualified = 2.
const CLEAR := 3
var valid := false
var cells := Rect2i()
var terrain_prefix := PackedInt32Array()
var terrain_height := NAN
var cell_size := 1.0
var origin := Vector3.ZERO
var radius := 0.0
var query_bounds := AABB()
var obstacle_cells := Rect2i()
var obstacle_prefix := PackedInt32Array()

func ground_height(from: Vector3, to: Vector3, body_width := 0.0) -> float:
	var width := maxf(radius, body_width)
	var first := Vector2i(roundi((minf(from.x, to.x) - width - origin.x) / cell_size), roundi((minf(from.z, to.z) - width - origin.z) / cell_size))
	var last := Vector2i(roundi((maxf(from.x, to.x) + width - origin.x) / cell_size), roundi((maxf(from.z, to.z) + width - origin.z) / cell_size))
	if not cells.has_point(first) or not cells.has_point(last): return NAN
	first -= cells.position
	last -= cells.position
	var stride := cells.size.x + 1
	var low := first.y * stride
	var high := (last.y + 1) * stride
	if terrain_prefix[high + last.x + 1] - terrain_prefix[low + last.x + 1] - terrain_prefix[high + first.x] + terrain_prefix[low + first.x] != 0: return NAN
	return terrain_height + origin.y

func obstacles_clear(from: Vector3, to: Vector3) -> bool:
	if obstacle_prefix.is_empty(): return true
	var start := AABB(query_bounds.position + from, query_bounds.size)
	var swept := start.merge(AABB(start.position + to - from, start.size))
	var first := Vector2i(floori(swept.position.x), floori(swept.position.z)).max(obstacle_cells.position)
	var last := Vector2i(floori(swept.end.x), floori(swept.end.z)).min(obstacle_cells.end - Vector2i.ONE)
	if first.x > last.x or first.y > last.y: return true
	first -= obstacle_cells.position
	last -= obstacle_cells.position
	var stride := obstacle_cells.size.x + 1
	var low := first.y * stride
	var high := (last.y + 1) * stride
	return obstacle_prefix[high + last.x + 1] - obstacle_prefix[low + last.x + 1] - obstacle_prefix[high + first.x] + obstacle_prefix[low + first.x] == 0

func certifies(from: Vector3, to: Vector3) -> bool:
	return classify(from, to) == CLEAR

func classify(from: Vector3, to: Vector3) -> int:
	if not valid or not from.is_finite() or not to.is_finite() or is_nan(ground_height(from, to)): return 0
	return CLEAR if obstacles_clear(from, to) else 1

## Both candidate input and status output are reusable caller-owned buffers.
## Height is resolved only for qualified terrain; uncertain cases stay explicit.
func plan_ground_candidates(from: Vector3, targets: PackedVector3Array, status: PackedByteArray) -> void:
	status.resize(targets.size())
	status.fill(0)
	if not valid or not from.is_finite(): return
	for index in targets.size():
		var to := targets[index]
		if not to.is_finite(): continue
		var height := ground_height(from, to)
		if is_nan(height): continue
		to.y = height
		targets[index] = to
		status[index] = CLEAR if obstacles_clear(from, to) else 1
