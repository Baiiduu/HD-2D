extends RefCounted

## 一次发射或只读预览的局部路线状态；不操作人物、伤害或速度。
var rules: PlayerRicochetRules
var turning := false
var detached := false
var outgoing := Vector3.ZERO
var _spin := 0.0
var _outline := PackedVector2Array()

func _init(settings: PlayerRicochetRules) -> void:
	rules = settings

func departure_heading(point: Vector3, heading: Vector3) -> Vector3:
	if _outline.is_empty(): return heading
	var nearest := _nearest(Vector2(point.x, point.z))
	var edge := int(nearest.edge)
	var flat := (_outline[(edge + 1) % _outline.size()] - _outline[edge]).normalized()
	var normal := Vector3(flat.y, 0.0, -flat.x)
	var offset: Vector2 = Vector2(point.x, point.z) - nearest.point
	if offset.length_squared() > 0.00000001 and not Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), _outline):
		offset = offset.normalized()
		normal = Vector3(offset.x, 0.0, offset.y)
	var tangent := heading - normal * minf(0.0, heading.dot(normal))
	if tangent.length_squared() < 0.000001: tangent = Vector3(-normal.z, 0.0, normal.x) * (_spin if _spin != 0.0 else 1.0)
	return (tangent + normal * 0.06).normalized()

## 实际体型外扩后的凸轮廓；所有控制点留在边线外侧，不再缩径或指向群心。
func build(point: Vector3, incoming: Vector3, surface: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	if detached: return points
	_outline = _expanded_outline(surface.positions, surface.body_radius + surface.player_radius + rules.eccentric_edge_clearance)
	var flat := Vector2(point.x, point.z)
	var nearest := _nearest(flat)
	# 起点已经在怪群内部时不把人物吸到外包线的另一处。
	# 续段允许正在靠近的怪物占用少量额外留白，但不能侵入真实身体。
	var tolerance := rules.eccentric_edge_clearance * 0.8 if turning else 0.015
	if Geometry2D.is_point_in_polygon(flat, _outline) and float(nearest.distance) > tolerance:
		# 首次接入失败交回基础短弧，不能当作玩家主动脱离并禁用整次飞行。
		if turning: detach()
		else: interrupt()
		return points
	var edge := int(nearest.edge)
	var direction := (_outline[(edge + 1) % _outline.size()] - _outline[edge]).normalized()
	if _spin == 0.0:
		var side := incoming.dot(Vector3(direction.x, 0.0, direction.y))
		_spin = signf(side) if absf(side) > 0.12 else (1.0 if rules.clockwise else -1.0)
	var cursor: Vector2 = nearest.point
	var remaining := rules.eccentric_step_distance
	var first_leg := true
	while remaining > 0.00001:
		var vertex := (edge + 1) % _outline.size() if _spin > 0.0 else edge
		var delta := _outline[vertex] - cursor
		if delta.length_squared() < 0.00000001:
			edge = posmod(edge + int(_spin), _outline.size())
			continue
		var tangent := Vector3(delta.x, 0.0, delta.y).normalized()
		var normal := Vector3(tangent.z, 0.0, -tangent.x) * _spin
		var length := minf(remaining, delta.length())
		if first_leg: length = minf(length, rules.crowd_turn_distance)
		var end_flat := cursor + delta.normalized() * length
		var end := Vector3(end_flat.x, point.y, end_flat.y)
		var start := point if first_leg else Vector3(cursor.x, point.y, cursor.y)
		var handle := length / 3.0
		var first := start + tangent * handle
		var second := end - tangent * handle
		if first_leg:
			var outside := maxf(0.0, (point - Vector3(cursor.x, point.y, cursor.y)).dot(normal))
			var approach := maxf(0.0001, -incoming.dot(normal))
			first = point + incoming * minf(handle, outside / approach * 0.75)
		else:
			var bow := minf(rules.eccentric_outward_sway, length * 0.15)
			first += normal * bow
			second += normal * bow
		_append_curve(points, start, first, second, end)
		remaining -= length
		cursor = end_flat
		first_leg = false
		outgoing = tangent
	turning = true
	return points

func interrupt() -> void:
	turning = false
	_spin = 0.0

func detach() -> void:
	interrupt()
	detached = true

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

func _nearest(point: Vector2) -> Dictionary:
	var result := {"edge": 0, "point": point, "distance": INF}
	for index in _outline.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, _outline[index], _outline[(index + 1) % _outline.size()])
		var distance := point.distance_to(closest)
		if distance < float(result.distance): result = {"edge": index, "point": closest, "distance": distance}
	return result

static func _append_curve(points: PackedVector3Array, start: Vector3, first: Vector3, second: Vector3, end: Vector3) -> void:
	var steps := maxi(2, ceili((start.distance_to(first) + first.distance_to(second) + second.distance_to(end)) / 0.075))
	for index in range(1, steps + 1): points.append(start.bezier_interpolate(first, second, end, float(index) / steps))

