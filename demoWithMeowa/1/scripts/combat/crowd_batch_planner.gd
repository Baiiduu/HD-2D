class_name CrowdBatchPlanner
extends RefCounted

## Pure current-snapshot planner. No actor, wall, damage, or previous-step state.
## Each active unordered pair contributes the original force exactly once.
const OriginalIndex = preload("res://scripts/combat/wave_enemy_spatial_index.gd")
const EMPTY: Array = []
## Opt-in diagnostics; production leaves counters disabled.
var diagnostics_enabled := false
var candidate_pairs := 0
var accepted_pairs := 0
var cell_pairs := 0

func plan(cells: Dictionary, positions: PackedVector3Array, ids: PackedInt64Array,
		active: PackedByteArray, spacing: PackedFloat64Array,
		bodies: PackedFloat64Array, cell_size: float) -> PackedVector3Array:
	candidate_pairs = 0
	accepted_pairs = 0
	cell_pairs = 0
	var count_metrics := diagnostics_enabled
	var forces := PackedVector3Array()
	forces.resize(positions.size())
	var maximum := 0.0
	for slot in positions.size():
		if active[slot] != 0: maximum = maxf(maximum, spacing[slot])
	if maximum <= 0.0: return forces
	var reach := ceili(maximum / cell_size)
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
					var body_a := bodies[a]
					var id_a := ids[a]
					for index_b in range(index_a + 1 if same_cell else 0, other.size()):
						var b: int = other[index_b]
						if active[b] == 0: continue
						if count_metrics: candidate_pairs += 1
						var pair_spacing := (space_a + spacing[b]) * 0.5
						var offset := point_a - positions[b]
						if offset.x * offset.x + offset.z * offset.z >= pair_spacing * pair_spacing: continue
						var force := OriginalIndex.crowd_pair_force(offset, pair_spacing, body_a + bodies[b], id_a, ids[b])
						forces[a] += force
						forces[b] -= force
						if count_metrics: accepted_pairs += 1
	return forces
