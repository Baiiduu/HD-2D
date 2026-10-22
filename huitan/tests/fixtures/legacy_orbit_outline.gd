extends PlayerCrowdDeflection

## Frozen pre-optimization outline traversal for functional equivalence.
func _view_eccentric_outline(seed_slot: int, point: Vector3, allowed: Dictionary[int, WaveEnemy], view: PreviewQueryView, obstacles: RefCounted) -> Dictionary:
	var anchor: Vector3 = view.positions[seed_slot]
	var seed_id: int = view.ids[seed_slot]
	var radius := minf(rules.eccentric_search_radius, rules.push_group_search_radius)
	view.nearby_slots_into(anchor, radius, {}, _nearby_slots)
	var samples: Array[int] = []
	var endpoints := PackedVector3Array([point + Vector3.UP * 0.45])
	for slot in _nearby_slots:
		if view.active[slot] == 0: continue
		if not allowed.is_empty() and not allowed.has(view.ids[slot]): continue
		var position: Vector3 = view.positions[slot]
		if absf(position.y - point.y) > rules.push_height_tolerance: continue
		samples.append(slot)
		endpoints.append(position + Vector3.UP * 0.45)
	_nearby_slots.clear()
	obstacles.cover(endpoints)
	var visible: Dictionary[int, int] = {}
	_ray_excluded = [session.player.get_rid()]
	for slot in samples:
		if _outline_ray_clear(point + Vector3.UP * 0.45, view.positions[slot] + Vector3.UP * 0.45, obstacles):
			visible[view.ids[slot]] = slot
	var minimum := rules.eccentric_minimum_members if allowed.is_empty() else 1
	if visible.size() < minimum or not visible.has(seed_id):
		if debug_enabled: debug_capture_reason = "可见同层成员不足 %d 只（隔墙／异层对象已排除）" % minimum
		return {}
	var connected: Array[Vector3] = [anchor]
	var visited: Dictionary[int, bool] = {seed_id:true}
	var members: Dictionary[int, WaveEnemy] = {seed_id:view.owners[seed_slot]}
	var cursor := 0
	var body_radius: float = view.bodies[seed_slot]
	var spread := 0.0
	while cursor < connected.size():
		var position := connected[cursor]
		cursor += 1
		spread = maxf(spread, TerrainPath.horizontal_distance(position, anchor))
		view.nearby_slots_into(position, rules.push_group_link_distance, visited, _nearby_slots)
		for slot in _nearby_slots:
			var id: int = view.ids[slot]
			if not visible.has(id): continue
			var candidate: Vector3 = view.positions[visible[id]]
			if not _outline_ray_clear(position + Vector3.UP * 0.45, candidate + Vector3.UP * 0.45, obstacles): continue
			visited[id] = true
			members[id] = view.owners[slot]
			body_radius = maxf(body_radius, view.bodies[slot])
			connected.append(candidate)
	_nearby_slots.clear()
	if connected.size() < minimum or (allowed.is_empty() and connected.size() > 1 and spread < 0.3):
		if debug_enabled: debug_capture_reason = "相连成员不足 %d 只" % minimum if connected.size() < minimum else "群体重叠，分布不足 0.3 米"
		return {}
	if debug_enabled: debug_capture_reason = "相连 %d 只，分布 %.2f 米" % [connected.size(), spread]
	var player_radius := 0.0
	for child in session.player.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape is CapsuleShape3D:
			player_radius = maxf(player_radius, child.shape.radius * maxf(child.global_basis.x.length(), child.global_basis.z.length()))
	return {"positions":PackedVector3Array(connected), "body_radius":body_radius, "player_radius":player_radius, "members":members}
