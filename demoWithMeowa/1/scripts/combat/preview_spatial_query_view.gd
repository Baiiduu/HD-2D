extends RefCounted

## One synchronous prediction or crowd-outline query owns this read-only view.
## Never retain it in flight/attack state or across an await/callback.
## Packed buffers remain the authoritative post-move index; no Node scan/copy.
const EMPTY_CELL: Array = []
const BASE_INDEX = preload("res://scripts/combat/wave_enemy_spatial_index.gd")
const BATCH_INDEX = preload("res://scripts/combat/crowd_batch_enemy_spatial_index.gd")
var eligible := false
var source: WaveEnemySpatialIndex
var cells: Dictionary
var entries: Dictionary[WaveEnemy, int]
var owners: Array[WaveEnemy]
var positions: PackedVector3Array
var ids: PackedInt64Array
var active: PackedByteArray
var bodies: PackedFloat64Array
var cell_size: float
var physics_frame: int
## Candidate lists only: each traversal still applies its own current visited set.
## Lifetime is this synchronous prediction, with no scene callbacks or awaits.
var memoize_neighbors := false
var _neighbor_candidates: Dictionary[float, Dictionary] = {}

func _init(index: WaveEnemySpatialIndex, battle: WavePrototype) -> void:
	source = index
	var script: Script = index.get_script()
	eligible = (script == BASE_INDEX or script == BATCH_INDEX) and battle.get_script() == load("res://scripts/combat/wave_prototype.gd")
	cells = index._cells
	entries = index._entries
	owners = index._owners
	positions = index._positions
	ids = index._ids
	active = index._active
	bodies = index._bodies
	cell_size = WaveEnemySpatialIndex.CELL_SIZE
	physics_frame = Engine.get_physics_frames()

func slot(enemy: WaveEnemy) -> int:
	return entries.get(enemy, -1)

## Same z/x/cell insertion order and exact Vector2 distance as nearby_into.
## Caller-owned typed slots replace temporary Nodes and repeated global getters.
func nearby_slots_into(point: Vector3, radius: float,
		excluded: Dictionary[int, bool], result: Array[int]) -> void:
	if not memoize_neighbors:
		_scan_neighbors(point, radius, excluded, result)
		return
	if not _neighbor_candidates.has(radius): _neighbor_candidates[radius] = {}
	var points: Dictionary = _neighbor_candidates[radius]
	if not points.has(point):
		var candidates: Array[int] = []
		_scan_neighbors(point, radius, {}, candidates)
		points[point] = candidates
	result.clear()
	for candidate: int in points[point]:
		if not excluded.has(ids[candidate]): result.append(candidate)

func _scan_neighbors(point: Vector3, radius: float,
		excluded: Dictionary[int, bool], result: Array[int]) -> void:
	result.clear()
	var first_point := point - Vector3(radius, 0.0, radius)
	var last_point := point + Vector3(radius, 0.0, radius)
	var first := Vector2i(floori(first_point.x / cell_size), floori(first_point.z / cell_size))
	var last := Vector2i(floori(last_point.x / cell_size), floori(last_point.z / cell_size))
	var squared := radius * radius
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for candidate: int in cells.get(Vector2i(x, z), EMPTY_CELL):
				if excluded.has(ids[candidate]): continue
				var position := positions[candidate]
				var offset := Vector2(position.x - point.x, position.z - point.z)
				if offset.length_squared() <= squared: result.append(candidate)

## Eligibility is exact known session/index code. Standard combat_active is pure,
## the prediction never awaits, and live physics queries invoke no user callback.
## Custom sessions/indices retain legacy; this constant-time guard also rejects
## an index replacement or accidental use outside this one physics-frame scope.
func is_current(index: WaveEnemySpatialIndex) -> bool:
	return eligible and index == source and physics_frame == Engine.get_physics_frames()
