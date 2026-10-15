class_name PlayerCrowdDeflection
extends RefCounted

const PreviewQueryView = preload("res://scripts/combat/preview_spatial_query_view.gd")
var _query_view: PreviewQueryView
var _nearby_slots: Array[int] = []

## 一次发射／一次预览的几何状态。只查询场景，不移动、扣血或拨怪。
var rules: PlayerRicochetRules
var session: WavePrototype
var regions: EnemyPushWave
var target_heading := Vector3.ZERO
var _locks: Array[Dictionary] = []
var _ignored: Dictionary[int, bool] = {}
var _points := PackedVector3Array()
var _cursor := 0
var _turn_region: Dictionary = {}
var _ray := PhysicsRayQueryParameters3D.new()
var _nearby: Array[WaveEnemy] = []
var _candidates: Array[Dictionary] = []

func _init(settings: PlayerRicochetRules, battle: WavePrototype, shared: EnemyPushWave = null, view: PreviewQueryView = null) -> void:
	_query_view = view
	rules = settings
	session = battle
	regions = shared if shared else EnemyPushWave.new(settings, view)
	# 已有镜片优先使用真实反射碰撞，不被怪群转向提前截住。
	_ray.collision_mask = ProjectileCollision.REFLECTION_MASK

func step(position: Vector3, heading: Vector3, distance: float) -> Dictionary:
	while _cursor < _points.size() and TerrainPath.horizontal_distance(position, _points[_cursor]) < 0.0001:
		_cursor += 1
	if _cursor < _points.size():
		var offset := _points[_cursor] - position
		offset.y = 0.0
		# 实际运动已离开旧弧线时顺势脱离，不把人物拉回路径上的旧点。
		if offset.dot(heading) < -0.00001:
			cancel_turn()
			return {"heading": heading, "distance": distance}
		return {"heading": offset.normalized(), "distance": minf(distance, offset.length())}
	if not _points.is_empty():
		_points.clear()
		_turn_region = {}
		heading = target_heading
	return {"heading": heading, "distance": distance}

func cancel_turn() -> void:
	_points.clear()
	_turn_region = {}

func _release_locks(position: Vector3) -> void:
	for index in range(_locks.size() - 1, -1, -1):
		var region := _locks[index]
		if is_same(region, _turn_region): continue
		var offset: Vector3 = position - region.center
		var radii: Vector2 = region.radii + Vector2.ONE * (rules.crowd_contact_radius + rules.crowd_release_clearance)
		if Vector2(offset.dot(region.u) / radii.x, offset.dot(region.v) / radii.y).length_squared() <= 1.0: continue
		for id in region.members: _ignored.erase(id)
		_locks.remove_at(index)

func contact(start: Vector3, end: Vector3, heading: Vector3) -> Dictionary:
	_release_locks(start)
	if not is_instance_valid(session) or not session.combat_active(): return {}
	# Check after the single combat predicate, which a custom session may override.
	if _query_view and _query_view.is_current(session._spatial_index): return _view_contact(start, end, heading)
	return _legacy_contact(start, end, heading)

func _legacy_contact(start: Vector3, end: Vector3, heading: Vector3) -> Dictionary:
	var radius := rules.crowd_contact_radius
	var length := TerrainPath.horizontal_distance(start, end)
	session._spatial_index.nearby_into((start + end) * 0.5, radius + length * 0.5, _ignored, _nearby)
	for enemy in _nearby:
		if enemy.spawn_delay > 0.0: continue
		var enemy_position := enemy.global_position
		if absf(enemy_position.y - start.y) > rules.push_height_tolerance: continue
		var entry := PlayerRicochet.circle_entry(start, end, enemy_position, radius)
		if entry < 0.0: continue
		var point := start.lerp(end, entry)
		var radial := point - enemy_position
		radial.y = 0.0
		if not radial.is_zero_approx() and radial.dot(heading) >= -0.00001: continue
		_candidates.append({"enemy": enemy, "entry": entry})
	_nearby.clear()
	# 沿弧线的大多数查询没有新目标，不创建排序回调或取得物理空间。
	if _candidates.is_empty(): return {}
	if _candidates.size() > 1:
		_candidates.sort_custom(func(a: Dictionary, b: Dictionary):
			return a.enemy.get_instance_id() < b.enemy.get_instance_id() if is_equal_approx(a.entry, b.entry) else a.entry < b.entry)
	_ray.exclude = [session.player.get_rid()]
	var space := session.get_world_3d().direct_space_state
	var hit: Dictionary = {}
	for candidate in _candidates:
		_ray.from = start.lerp(end, candidate.entry) + Vector3.UP * 0.45
		_ray.to = candidate.enemy.global_position + Vector3.UP * 0.45
		if space.intersect_ray(_ray).is_empty():
			hit = candidate
			break
	_candidates.clear()
	return hit


func _view_contact(start: Vector3, end: Vector3, heading: Vector3) -> Dictionary:
	var radius := rules.crowd_contact_radius
	var length := TerrainPath.horizontal_distance(start, end)
	_query_view.nearby_slots_into((start + end) * 0.5, radius + length * 0.5, _ignored, _nearby_slots)
	for enemy_slot in _nearby_slots:
		if _query_view.active[enemy_slot] == 0: continue
		var enemy_position: Vector3 = _query_view.positions[enemy_slot]
		if absf(enemy_position.y - start.y) > rules.push_height_tolerance: continue
		var entry := PlayerRicochet.circle_entry(start, end, enemy_position, radius)
		if entry < 0.0: continue
		var point := start.lerp(end, entry)
		var radial := point - enemy_position
		radial.y = 0.0
		if not radial.is_zero_approx() and radial.dot(heading) >= -0.00001: continue
		_candidates.append({"enemy": _query_view.owners[enemy_slot], "entry": entry, "slot": enemy_slot})
	_nearby_slots.clear()
	# 沿弧线的大多数查询没有新目标，不创建排序回调或取得物理空间。
	if _candidates.is_empty(): return {}
	if _candidates.size() > 1:
		_candidates.sort_custom(func(a: Dictionary, b: Dictionary):
			return _query_view.ids[a.slot] < _query_view.ids[b.slot] if is_equal_approx(a.entry, b.entry) else a.entry < b.entry)
	_ray.exclude = [session.player.get_rid()]
	var space := session.get_world_3d().direct_space_state
	var hit: Dictionary = {}
	for candidate in _candidates:
		_ray.from = start.lerp(end, candidate.entry) + Vector3.UP * 0.45
		_ray.to = _query_view.positions[candidate.slot] + Vector3.UP * 0.45
		if space.intersect_ray(_ray).is_empty():
			hit = candidate
			break
	_candidates.clear()
	if not hit.is_empty(): hit.erase("slot")
	return hit

func begin_contact(hit: Dictionary, point: Vector3, incoming: Vector3) -> bool:
	var enemy := hit.enemy as WaveEnemy
	if not is_instance_valid(enemy) or enemy.dead or enemy.spawn_delay > 0.0: return false
	var region := regions.region_for(enemy, incoming)
	# 单怪使用自身圆心；拨怪轮廓为怪物位移保留的偏置不适用于人物绕行。
	if region.members.size() == 1:
		region = region.duplicate()
		region.center = enemy.global_position
		region.radii = Vector2.ONE * (enemy.get_crowd_body_radius() + rules.push_group_edge_margin)
	var offset: Vector3 = point - region.center
	var clearance := maxf(0.05, rules.crowd_contact_radius - enemy.get_crowd_body_radius() - rules.push_group_edge_margin)
	# 曲率留出入弧控制柄的前进量，避免接触点锚定后切进前排两侧身体。
	var radii: Vector2 = region.radii + Vector2.ONE * (clearance + rules.crowd_turn_distance / 3.0)
	var angle := atan2(offset.dot(region.v) / radii.y, offset.dot(region.u) / radii.x)
	var tangent := _tangent(region, radii, angle)
	var side := incoming.dot(tangent)
	var spin := signf(side) if absf(side) > 0.08 else (1.0 if rules.clockwise else -1.0)
	var sweep := minf(deg_to_rad(rules.crowd_arc_degrees), rules.crowd_arc_distance / maxf(radii.x, radii.y))
	var join_angle := minf(sweep * 0.25, rules.crowd_turn_distance / maxf(radii.x, radii.y))
	# 只借用怪群轮廓的曲率，以真实接触点锚定整段运动；不先吸到椭圆上。
	var anchor := point - _point(region, radii, angle, point.y)
	var join := _point(region, radii, angle + spin * join_angle, point.y) + anchor
	var join_tangent := _tangent(region, radii, angle + spin * join_angle) * spin
	var handle := minf(rules.crowd_turn_distance / 3.0, TerrainPath.horizontal_distance(point, join) * 0.5)
	# 入弧控制点沿来向有序排列，避免曲线先冲过头、后退再向前的折返。
	var forward := maxf(0.0, (join - point).dot(incoming))
	handle = minf(handle, forward / maxf(1.0 + incoming.dot(join_tangent), 0.00001) * 0.95)
	if join_tangent.dot(incoming) < 0.0: handle = 0.0
	_points.clear()
	_append_curve(point, point + incoming * handle, join - join_tangent * handle, join)
	var steps := maxi(1, ceili((sweep - join_angle) * maxf(radii.x, radii.y) / 0.075))
	for index in range(1, steps + 1):
		var theta := angle + spin * lerpf(join_angle, sweep, float(index) / steps)
		_points.append(_point(region, radii, theta, point.y) + anchor)
	angle += spin * sweep
	tangent = _tangent(region, radii, angle) * spin
	var normal: Vector3 = (region.u * cos(angle) / radii.x + region.v * sin(angle) / radii.y).normalized()
	var outward := rules.crowd_exit_outward
	target_heading = (tangent * sqrt(1.0 - outward * outward) + normal * outward).normalized()
	var last := _points[-1]
	var exit := last + target_heading * rules.crowd_turn_distance
	handle = rules.crowd_turn_distance / 3.0
	_append_curve(last, last + tangent * handle, exit - target_heading * handle, exit)
	_cursor = 0
	_turn_region = region
	if not _locks.any(func(locked): return is_same(locked, region)):
		_locks.append(region)
		for id in region.members: _ignored[id] = true
	return true

func _point(region: Dictionary, radii: Vector2, angle: float, height: float) -> Vector3:
	var point: Vector3 = region.center + region.u * (cos(angle) * radii.x) + region.v * (sin(angle) * radii.y)
	point.y = height
	return point

func _tangent(region: Dictionary, radii: Vector2, angle: float) -> Vector3:
	return (-region.u * (sin(angle) * radii.x) + region.v * (cos(angle) * radii.y)).normalized()

func _append_curve(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var steps := maxi(1, ceili((a.distance_to(b) + b.distance_to(c) + c.distance_to(d)) / 0.075))
	for index in range(1, steps + 1):
		_points.append(a.bezier_interpolate(b, c, d, float(index) / steps))
