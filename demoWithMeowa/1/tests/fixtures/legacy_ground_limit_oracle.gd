extends RefCounted

## Frozen pre-certificate sampler, used only as an independent byte oracle.
func ground_limit(path: TerrainPath, start: Vector3, direction: Vector3, distance: float, plane_height: float, tolerance: float) -> float:
	var terrain := path.terrain
	var steps := maxi(1, ceili(distance / 0.15))
	for index in steps + 1:
		var travel := distance * index / steps
		var point := start + direction * travel
		var cell := terrain.data.world_to_cell(terrain.to_local(point))
		if not terrain.data.has_cell(cell) or (terrain.data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not terrain.data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)) or absf(path.ground_position(point).y - plane_height) > tolerance:
			return distance * maxi(index - 1, 0) / steps
	return distance
