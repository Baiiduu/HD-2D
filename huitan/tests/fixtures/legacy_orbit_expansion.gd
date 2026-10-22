extends "res://scripts/player/player_eccentric_ricochet.gd"

## Frozen pre-optimization circumscribed body expansion.
func _expanded_outline(positions: PackedVector3Array, radius: float) -> PackedVector2Array:
	var flat := PackedVector2Array()
	for point in positions: flat.append(Vector2(point.x, point.z))
	var hull := Geometry2D.convex_hull(flat)
	var expanded := PackedVector2Array()
	# 外接十六边形包住圆形体型；不以中心点连线当作怪物的实际边缘。
	var reach := radius / cos(PI / 16.0)
	for point in hull:
		for index in 16:
			var angle := TAU * index / 16.0
			expanded.append(point + Vector2(cos(angle), sin(angle)) * reach)
	var result := Geometry2D.convex_hull(expanded)
	if result[0].is_equal_approx(result[-1]): result.remove_at(result.size() - 1)
	var area := 0.0
	for index in result.size(): area += result[index].cross(result[(index + 1) % result.size()])
	if area < 0.0: result.reverse()
	return result
