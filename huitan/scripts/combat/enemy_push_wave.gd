class_name EnemyPushWave
extends RefCounted

const PreviewQueryView = preload("res://scripts/combat/preview_spatial_query_view.gd")
var _query_view: PreviewQueryView
var _nearby_slots: Array[int] = []

## 一次发射共用去重与怪群轮廓；只保存 ID 和几何数据，不持有怪物／人物。
var rules: PlayerRicochetRules
var affected_count := 0
var _seen: Dictionary[int, bool] = {}
var _regions: Dictionary[int, Dictionary] = {}
var _ray := PhysicsRayQueryParameters3D.new()
var _nearby: Array[WaveEnemy] = []

func _init(settings: PlayerRicochetRules, view: PreviewQueryView = null) -> void:
	_query_view = view
	rules = settings
	_ray.collision_mask = 1

func push(enemy: WaveEnemy, heading: Vector3, speed: float, seconds: float, stun: float, layer := 0, region: Dictionary = {}) -> bool:
	if not is_instance_valid(enemy): return false
	var id := enemy.get_instance_id()
	if _seen.has(id) or enemy.dead or enemy.spawn_delay > 0.0: return false
	if enemy.combat_active.is_valid() and not enemy.combat_active.call(): return false
	_seen[id] = true
	var outline := region if not region.is_empty() else _region_for(enemy, heading)
	outline["arrival_span"] = deg_to_rad(rules.push_arrival_arc_degrees)
	var applied := enemy.receive_push_wave(self, outline, heading, speed, seconds, stun, layer)
	if applied: affected_count += 1
	return applied

func has_target(id: int) -> bool:
	return _seen.has(id)

## 人物偏转和只读预览复用相同轮廓；读取不施加外力、眩晕或伤害。
func region_for(seed: WaveEnemy, heading: Vector3) -> Dictionary:
	return _region_for(seed, heading)

func _region_for(seed: WaveEnemy, heading: Vector3) -> Dictionary:
	if _query_view and _query_view.is_current(seed.spatial_index):
		var seed_slot := _query_view.slot(seed)
		if seed_slot >= 0: return _view_region_for(seed, heading, seed_slot)
	return _legacy_region_for(seed, heading)

func _legacy_region_for(seed: WaveEnemy, heading: Vector3) -> Dictionary:
	var id := seed.get_instance_id()
	if _regions.has(id): return _regions[id]
	var members: Array[WaveEnemy] = [seed]
	var visited: Dictionary[int, bool] = {id: true}
	var position := seed.global_position
	var cursor := 0
	var space: PhysicsDirectSpaceState3D
	# 仅首次命中时，通过局部空间索引找相连怪群；断开的远处怪不拉长椭圆。
	while seed.spatial_index and cursor < members.size():
		var current := members[cursor]
		cursor += 1
		var current_position := current.global_position
		seed.spatial_index.nearby_into(current_position, rules.push_group_link_distance, visited, _nearby)
		for other in _nearby:
			var other_id := other.get_instance_id()
			if other.spawn_delay > 0.0: continue
			var other_position := other.global_position
			if absf(other_position.y - position.y) > rules.push_height_tolerance: continue
			if TerrainPath.horizontal_distance(other_position, position) > rules.push_group_search_radius: continue
			_ray.from = current_position + Vector3.UP * 0.45
			_ray.to = other_position + Vector3.UP * 0.45
			if not space: space = seed.get_world_3d().direct_space_state
			if not space.intersect_ray(_ray).is_empty(): continue
			visited[other_id] = true
			members.append(other)
	_nearby.clear()
	# 仅在本次同步计算内读取一遍位置、体型；各遍几何运算共用同一快照。
	var positions: Array[Vector3] = []
	var margins: Array[float] = []
	var ids := PackedInt64Array()
	var center := Vector3.ZERO
	var arrival_spacing := 0.0
	for member in members:
		var point := member.global_position
		var body := member.get_crowd_body_radius()
		positions.append(point)
		margins.append(body + rules.push_group_edge_margin)
		ids.append(member.get_instance_id())
		center += point
		arrival_spacing = maxf(arrival_spacing, body * 2.1)
	center /= members.size()
	var xx := 0.0
	var zz := 0.0
	var xz := 0.0
	for point in positions:
		var offset := point - center
		xx += offset.x * offset.x
		zz += offset.z * offset.z
		xz += offset.x * offset.z
	var angle := 0.5 * atan2(2.0 * xz, xx - zz)
	var u := Vector3(cos(angle), 0.0, sin(angle))
	var v := Vector3(-u.z, 0.0, u.x)
	var radii := Vector2(0.8, 0.8)
	if xx + zz < 0.0001:
		var radial := Vector3(heading.z, 0.0, -heading.x).normalized() * (1.0 if rules.clockwise else -1.0)
		if radial.is_zero_approx(): radial = Vector3.RIGHT
		center -= radial * radii.x
	for index in positions.size():
		var offset := positions[index] - center
		var margin := margins[index]
		radii.x = maxf(radii.x, absf(offset.dot(u)) + margin)
		radii.y = maxf(radii.y, absf(offset.dot(v)) + margin)
	var scale := 1.0
	for index in positions.size():
		var offset := positions[index] - center
		var margin := margins[index]
		scale = maxf(scale, Vector2((absf(offset.dot(u)) + margin) / radii.x, (absf(offset.dot(v)) + margin) / radii.y).length())
	var region := {"center": center, "u": u, "v": v, "radii": radii * scale, "members": ids, "arrival_spacing": arrival_spacing}
	for member_id in ids: _regions[member_id] = region
	return region


func _view_region_for(seed: WaveEnemy, heading: Vector3, seed_slot: int) -> Dictionary:
	var id := seed.get_instance_id()
	if _regions.has(id): return _regions[id]
	var members: Array[int] = [seed_slot]
	var visited: Dictionary[int, bool] = {id: true}
	var position: Vector3 = _query_view.positions[seed_slot]
	var cursor := 0
	var space: PhysicsDirectSpaceState3D
	while cursor < members.size():
		var current: int = members[cursor]
		cursor += 1
		var current_position: Vector3 = _query_view.positions[current]
		_query_view.nearby_slots_into(current_position, rules.push_group_link_distance, visited, _nearby_slots)
		for other in _nearby_slots:
			var other_id: int = _query_view.ids[other]
			if _query_view.active[other] == 0: continue
			var other_position: Vector3 = _query_view.positions[other]
			if absf(other_position.y - position.y) > rules.push_height_tolerance: continue
			if TerrainPath.horizontal_distance(other_position, position) > rules.push_group_search_radius: continue
			_ray.from = current_position + Vector3.UP * 0.45
			_ray.to = other_position + Vector3.UP * 0.45
			if not space: space = seed.get_world_3d().direct_space_state
			if not space.intersect_ray(_ray).is_empty(): continue
			visited[other_id] = true
			members.append(other)
	_nearby_slots.clear()
	# 仅在本次同步计算内读取一遍位置、体型；各遍几何运算共用同一快照。
	var positions: Array[Vector3] = []
	var margins: Array[float] = []
	var ids := PackedInt64Array()
	var center := Vector3.ZERO
	var arrival_spacing := 0.0
	for member in members:
		var point: Vector3 = _query_view.positions[member]
		var body: float = _query_view.bodies[member]
		positions.append(point)
		margins.append(body + rules.push_group_edge_margin)
		ids.append(_query_view.ids[member])
		center += point
		arrival_spacing = maxf(arrival_spacing, body * 2.1)
	center /= members.size()
	var xx := 0.0
	var zz := 0.0
	var xz := 0.0
	for point in positions:
		var offset := point - center
		xx += offset.x * offset.x
		zz += offset.z * offset.z
		xz += offset.x * offset.z
	var angle := 0.5 * atan2(2.0 * xz, xx - zz)
	var u := Vector3(cos(angle), 0.0, sin(angle))
	var v := Vector3(-u.z, 0.0, u.x)
	var radii := Vector2(0.8, 0.8)
	if xx + zz < 0.0001:
		var radial := Vector3(heading.z, 0.0, -heading.x).normalized() * (1.0 if rules.clockwise else -1.0)
		if radial.is_zero_approx(): radial = Vector3.RIGHT
		center -= radial * radii.x
	for index in positions.size():
		var offset := positions[index] - center
		var margin := margins[index]
		radii.x = maxf(radii.x, absf(offset.dot(u)) + margin)
		radii.y = maxf(radii.y, absf(offset.dot(v)) + margin)
	var scale := 1.0
	for index in positions.size():
		var offset := positions[index] - center
		var margin := margins[index]
		scale = maxf(scale, Vector2((absf(offset.dot(u)) + margin) / radii.x, (absf(offset.dot(v)) + margin) / radii.y).length())
	var region := {"center": center, "u": u, "v": v, "radii": radii * scale, "members": ids, "arrival_spacing": arrival_spacing}
	for member_id in ids: _regions[member_id] = region
	return region

func spread(source: WaveEnemy, start: Vector3, end: Vector3, path: EnemyOrbitPath, start_distance: float, layer: int) -> void:
	if layer >= rules.push_chain_layers or rules.push_chain_speed_retention <= 0.0 or not source.spatial_index: return
	if path.speed_at(start_distance) * rules.push_chain_speed_retention < rules.push_chain_min_speed: return
	var motion := end - start
	motion.y = 0.0
	var length := motion.length()
	if length <= 0.000001: return
	var heading := motion / length
	var contacts: Array[Dictionary] = []
	for target in source.spatial_index.swept_bodies(start, end, source.get_crowd_body_radius()):
		if target == source or target.dead or target.spawn_delay > 0.0 or _seen.has(target.get_instance_id()): continue
		var offset := target.global_position - start
		if absf(offset.y) > rules.push_height_tolerance: continue
		offset.y = 0.0
		if offset.dot(heading) < -0.001: continue
		var entry := PlayerRicochet.circle_entry(start, end, target.global_position, source.get_crowd_body_radius() + target.get_crowd_body_radius())
		if entry >= 0.0: contacts.append({"enemy": target, "entry": entry})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.enemy.get_instance_id() < b.enemy.get_instance_id() if is_equal_approx(a.entry, b.entry) else a.entry < b.entry)
	for contact in contacts:
		var target: WaveEnemy = contact.enemy
		if not is_instance_valid(target) or target.dead or _seen.has(target.get_instance_id()): continue
		var speed := path.speed_at(start_distance + length * contact.entry) * rules.push_chain_speed_retention
		if speed < rules.push_chain_min_speed: continue
		var point := start.lerp(end, contact.entry)
		_ray.from = point + Vector3.UP * 0.45
		_ray.to = target.global_position + Vector3.UP * 0.45
		if not source.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty(): continue
		var depth := layer + 1
		push(target, heading, speed, rules.push_seconds, rules.push_stun_seconds * pow(rules.push_chain_stun_retention, depth), depth, path.region)
