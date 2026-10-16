class_name CrowdBatchPlanner
extends RefCounted

## Each active unordered pair contributes the original current-snapshot force
## exactly once. Only candidate pairs, never forces, survive across steps.
const OriginalIndex = preload("res://scripts/combat/wave_enemy_spatial_index.gd")
const EMPTY: Array = []
## Verlet list: until every actor moves less than half this XZ buffer, no pair
## outside spacing + buffer can enter the real interaction radius. This is
## independent of the soft-contact skin in the original force formula.
const NEIGHBOR_SKIN := 0.3
## Opt-in diagnostics; production leaves counters disabled.
var diagnostics_enabled := false
var candidate_pairs := 0
var accepted_pairs := 0
var cell_pairs := 0
var search_pairs := 0
var neighbors_rebuilt := false
var _pairs := PackedInt32Array()
var _reference_positions := PackedVector3Array()
var _revision := -1
var _cell_size := 0.0

func clear() -> void:
	_pairs.clear()
	_reference_positions.clear()
	_revision = -1
	_cell_size = 0.0

func _can_reuse(positions: PackedVector3Array, active: PackedByteArray,
		revision: int, cell_size: float) -> bool:
	# Callers without a metadata revision always build a fresh candidate list.
	if revision < 0 or revision != _revision or cell_size != _cell_size or positions.size() != _reference_positions.size(): return false
	var limit_squared := NEIGHBOR_SKIN * NEIGHBOR_SKIN * 0.25
	for slot in positions.size():
		if active[slot] == 0: continue
		var moved := positions[slot] - _reference_positions[slot]
		if moved.x * moved.x + moved.z * moved.z >= limit_squared: return false
	return true

func plan(cells: Dictionary, positions: PackedVector3Array, ids: PackedInt64Array,
		active: PackedByteArray, spacing: PackedFloat64Array,
		bodies: PackedFloat64Array, cell_size: float, revision := -1) -> PackedVector3Array:
	# A nonnegative revision must change whenever membership, IDs, active flags,
	# body radii or spacing changes. WaveEnemySpatialIndex owns this contract.
	candidate_pairs = 0
	accepted_pairs = 0
	cell_pairs = 0
	search_pairs = 0
	neighbors_rebuilt = not _can_reuse(positions, active, revision, cell_size)
	if neighbors_rebuilt:
		_build_neighbors(cells, positions, active, spacing, cell_size)
		_reference_positions = positions.duplicate()
		_revision = revision
		_cell_size = cell_size
	var count_metrics := diagnostics_enabled
	var forces := PackedVector3Array()
	forces.resize(positions.size())
	for pair in range(0, _pairs.size(), 2):
		var a := _pairs[pair]
		var b := _pairs[pair + 1]
		if count_metrics: candidate_pairs += 1
		var pair_spacing := (spacing[a] + spacing[b]) * 0.5
		var offset := positions[a] - positions[b]
		if offset.x * offset.x + offset.z * offset.z >= pair_spacing * pair_spacing: continue
		var force := OriginalIndex.crowd_pair_force(offset, pair_spacing, bodies[a] + bodies[b], ids[a], ids[b])
		forces[a] += force
		forces[b] -= force
		if count_metrics: accepted_pairs += 1
	return forces

func _build_neighbors(cells: Dictionary, positions: PackedVector3Array,
		active: PackedByteArray, spacing: PackedFloat64Array, cell_size: float) -> void:
	_pairs.clear()
	var count_metrics := diagnostics_enabled
	var maximum := 0.0
	for slot in positions.size():
		if active[slot] != 0: maximum = maxf(maximum, spacing[slot])
	if maximum <= 0.0: return
	# Small numerical padding also covers float32 position subtraction at the
	# buffer boundary. Height is not pruned: jumps can return within contact.
	var buffer := NEIGHBOR_SKIN + 0.00001
	var reach := ceili((maximum + buffer) / cell_size)
	for key: Vector2i in cells:
		var own: Array = cells[key]
		# Half of the full cell neighborhood. A cell cannot be omitted merely
		# because its occupants have a small radius: spacing is pairwise.
		for dz in range(0, reach + 1):
			for dx in range(0 if dz == 0 else -reach, reach + 1):
				var other_key := key + Vector2i(dx, dz)
				var other: Array = cells.get(other_key, EMPTY)
				if other.is_empty(): continue
				if count_metrics: cell_pairs += 1
				var same_cell := dx == 0 and dz == 0
				for index_a in own.size():
					var a: int = own[index_a]
					if active[a] == 0: continue
					var point_a := positions[a]
					var space_a := spacing[a]
					for index_b in range(index_a + 1 if same_cell else 0, other.size()):
						var b: int = other[index_b]
						if active[b] == 0: continue
						if count_metrics: search_pairs += 1
						var pair_spacing := (space_a + spacing[b]) * 0.5 + buffer
						var offset := point_a - positions[b]
						if offset.x * offset.x + offset.z * offset.z >= pair_spacing * pair_spacing: continue
						_pairs.append(a)
						_pairs.append(b)
