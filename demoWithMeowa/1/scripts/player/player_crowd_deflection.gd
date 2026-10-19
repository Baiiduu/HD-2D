class_name PlayerCrowdDeflection
extends RefCounted

const PreviewQueryView = preload("res://scripts/combat/preview_spatial_query_view.gd")
const ObstacleBatch = preload("res://scripts/combat/preview_obstacle_batch.gd")
const EccentricPath = preload("res://scripts/player/player_eccentric_ricochet.gd")
var _query_view: PreviewQueryView
## Only the prediction producer can provide this synchronous empty-volume proof.
var _preview_obstacles: RefCounted
var _nearby_slots: Array[int] = []
var _eccentric: EccentricPath
var _orbit_members: Dictionary[int, WaveEnemy] = {}
var _orbit_seed: WaveEnemy
var orbiting: bool:
	get: return _eccentric != null and _eccentric.turning and not _orbit_members.is_empty()
var presentation_center: Vector3:
	get: return _eccentric.presentation_center if orbiting else Vector3.ZERO

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
var _ray_excluded: Array[RID] = []
var _nearby: Array[WaveEnemy] = []
var _candidates: Array[Dictionary] = []
## 只在实机调试开启时记录；不增加碰撞、轮廓或导航查询。
var debug_enabled := false
var debug_events: Array[String] = []
var debug_reason := "等待接群"
var debug_capture_reason := "尚未判群"
var debug_revision := 0
var debug_replans := 0

func _debug_event(message: String) -> void:
	if not debug_enabled: return
	debug_reason = message
	debug_revision += 1
	if debug_events.is_empty() or debug_events[-1] != message:
		debug_events.append(message)
		if debug_events.size() > 8: debug_events.pop_front()

## 诊断快照仅复制现有结果，不预测未来环绕或重新寻找怪物。
func debug_snapshot() -> Dictionary:
	var members: Array[Dictionary] = []
	for actor in _orbit_members.values():
		if is_instance_valid(actor) and not actor.dead:
			members.append({"point": actor.global_position, "radius": actor.get_crowd_body_radius(), "seed": actor == _orbit_seed})
	var outline := PackedVector3Array()
	if _eccentric:
		var height := session.player.global_position.y if is_instance_valid(session) and is_instance_valid(session.player) else 0.0
		for point in _eccentric._outline: outline.append(Vector3(point.x, height, point.y))
	return {"orbiting": orbiting, "planned": _points.slice(_cursor), "outline": outline,
		"members": members, "outgoing": target_heading, "reason": debug_reason,
		"capture_reason": debug_capture_reason, "revision": debug_revision, "replans": debug_replans, "events": debug_events.duplicate(),
		"locks": _locks.size(), "ignored": _ignored.size(), "detached": _eccentric != null and _eccentric.detached}

func _init(settings: PlayerRicochetRules, battle: WavePrototype, shared: EnemyPushWave = null, view: PreviewQueryView = null) -> void:
	_query_view = view
	rules = settings
	session = battle
	regions = shared if shared else EnemyPushWave.new(settings, view)
	if rules.eccentric_enabled: _eccentric = EccentricPath.new(rules)

func _ray_clear(from: Vector3, to: Vector3) -> bool:
	# Existing mirrors still interrupt capture/continuation before crowd turning.
	if _preview_obstacles and _preview_obstacles.proves(from, to): return true
	return session.terrain.ray_clear(from, to, ProjectileCollision.REFLECTION_MASK, _ray_excluded)

func step(position: Vector3, heading: Vector3, distance: float) -> Dictionary:
	# 支点死亡时立即改用存活成员；正常只在走完一小段后重读轮廓。
	if orbiting and (not is_instance_valid(_orbit_seed) or _orbit_seed.dead):
		if not _continue_orbit(position, heading):
			heading = departure_heading(position, heading)
			cancel_turn(&"支点丢失，无法安全续接")
	while _cursor < _points.size() and TerrainPath.horizontal_distance(position, _points[_cursor]) < 0.0001:
		_cursor += 1
	if _cursor >= _points.size() and not _points.is_empty():
		heading = target_heading
		if not orbiting or not _continue_orbit(position, heading):
			if orbiting: heading = departure_heading(position, heading)
			cancel_turn(&"环绕无法续接" if orbiting else &"短弧完成")
	if _cursor < _points.size():
		var offset := _points[_cursor] - position
		offset.y = 0.0
		# 实际运动已离开旧弧线时顺势脱离，不把人物拉回路径上的旧点。
		if offset.dot(heading) < -0.00001:
			cancel_turn(&"实际来向已离开旧路线")
			return {"heading": heading, "distance": distance}
		return {"heading": offset.normalized(), "distance": minf(distance, offset.length())}
	return {"heading": heading, "distance": distance}

func cancel_turn(reason: StringName = &"路线被中断") -> void:
	_debug_event(String(reason))
	_points.clear()
	_turn_region = {}
	_orbit_members.clear()
	_orbit_seed = null
	if _eccentric: _eccentric.interrupt()

## 续段不是一次新碰撞，不补速、不扣碰撞费用，也不重发伤害或接群事件。
func _continue_orbit(position: Vector3, heading: Vector3) -> bool:
	if not is_instance_valid(session) or not session.combat_active():
		_debug_event("战斗结束，停止续接")
		return false
	var seed: WaveEnemy
	var nearest := rules.crowd_contact_radius + rules.eccentric_step_distance
	for actor in _orbit_members.values():
		if not is_instance_valid(actor) or actor.dead or actor.spawn_delay > 0.0: continue
		var distance := TerrainPath.horizontal_distance(position, actor.global_position)
		if distance < nearest:
			nearest = distance
			seed = actor
	if not seed:
		_debug_event("存活成员已清空或离人物过远")
		return false
	var surface := _eccentric_outline(seed, position, _orbit_members)
	if surface.is_empty():
		_debug_event("续接失败：" + debug_capture_reason)
		return false
	var points := _eccentric.build(position, heading, surface)
	if points.is_empty():
		_debug_event("新轮廓侵入当前位置，停止环绕")
		return false
	_points = points
	_cursor = 0
	_orbit_members = surface.members
	_orbit_seed = seed
	target_heading = _eccentric.outgoing
	if debug_enabled:
		debug_replans += 1
		_debug_event("续接外沿：%d 只" % _orbit_members.size())
	return true

## 主动脱离只撤销当前与后续贴边路线；来向、余速和真实碰撞由人物继续处理。
func detach() -> bool:
	if not _eccentric or _eccentric.detached: return false
	_eccentric.detach()
	cancel_turn(&"右键主动脱离，本次不再接群")
	return true

func departure_heading(point: Vector3, heading: Vector3) -> Vector3:
	return _eccentric.departure_heading(point, heading) if _eccentric else heading

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
	if _eccentric and (_eccentric.detached or _eccentric.turning): return {}
	_release_locks(start)
	if not is_instance_valid(session) or not session.combat_active(): return {}
	# Check after the single combat predicate, which a custom session may override.
	if _query_view and _query_view.is_current(session._spatial_index): return _view_contact(start, end, heading)
	return _legacy_contact(start, end, heading)

func _legacy_contact(start: Vector3, end: Vector3, heading: Vector3) -> Dictionary:
	var radius := rules.crowd_contact_radius + (rules.eccentric_capture_margin if _eccentric else 0.0)
	var length := TerrainPath.horizontal_distance(start, end)
	session.get_nearby_enemies_into((start + end) * 0.5, radius + length * 0.5, _ignored, _nearby)
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
	_ray_excluded = [session.player.get_rid()]
	var hit: Dictionary = {}
	for candidate in _candidates:
		if not hit.is_empty() and float(candidate.entry) >= float(hit.entry): break
		var contact := _resolve_contact(candidate, start, end, heading)
		if contact.is_empty() or (not hit.is_empty() and float(contact.entry) >= float(hit.entry)): continue
		if _ray_clear(start.lerp(end, contact.entry) + Vector3.UP * 0.45, contact.enemy.global_position + Vector3.UP * 0.45):
			hit = contact
	_candidates.clear()
	return hit


func _view_contact(start: Vector3, end: Vector3, heading: Vector3) -> Dictionary:
	var radius := rules.crowd_contact_radius + (rules.eccentric_capture_margin if _eccentric else 0.0)
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
	_ray_excluded = [session.player.get_rid()]
	var hit: Dictionary = {}
	for candidate in _candidates:
		if not hit.is_empty() and float(candidate.entry) >= float(hit.entry): break
		var contact := _resolve_contact(candidate, start, end, heading)
		if contact.is_empty() or (not hit.is_empty() and float(contact.entry) >= float(hit.entry)): continue
		if _ray_clear(start.lerp(end, contact.entry) + Vector3.UP * 0.45, _query_view.positions[contact.slot] + Vector3.UP * 0.45):
			hit = contact
	_candidates.clear()
	if not hit.is_empty(): hit.erase("slot")
	return hit

## 提前识别只服务于持续环绕，不能把单怪短弧也推到近身技能射程之外。
func _resolve_contact(candidate: Dictionary, start: Vector3, end: Vector3, heading: Vector3) -> Dictionary:
	if not _eccentric or rules.eccentric_capture_margin <= 0.0: return candidate
	var point := start.lerp(end, candidate.entry)
	var focus := _eccentric_outline(candidate.enemy, point)
	if not focus.is_empty():
		candidate.focus = focus
		return candidate
	var position: Vector3 = _query_view.positions[candidate.slot] if candidate.has("slot") else candidate.enemy.global_position
	var entry := PlayerRicochet.circle_entry(start, end, position, rules.crowd_contact_radius)
	if entry < 0.0: return {}
	var radial := start.lerp(end, entry) - position
	radial.y = 0.0
	if not radial.is_zero_approx() and radial.dot(heading) >= -0.00001: return {}
	# 保留宽查询的原始排序键；普通接触的位置可能比下一只可环绕目标更晚。
	var contact := candidate.duplicate()
	contact.entry = entry
	contact.focus = focus
	return contact

func begin_contact(hit: Dictionary, point: Vector3, incoming: Vector3) -> bool:
	var enemy := hit.enemy as WaveEnemy
	if not is_instance_valid(enemy) or enemy.dead or enemy.spawn_delay > 0.0: return false
	if _eccentric:
		var focus: Dictionary = hit.focus if hit.has("focus") else _eccentric_outline(enemy, point)
		if not focus.is_empty():
			var points := _eccentric.build(point, incoming, focus)
			if not points.is_empty():
				_points = points
				_cursor = 0
				_turn_region = {}
				_orbit_members = focus.members
				_orbit_seed = enemy
				target_heading = _eccentric.outgoing
				if debug_enabled:
					debug_replans += 1
					_debug_event("接入持续环绕：%d 只" % _orbit_members.size())
				return true
			# 群体外沿不适合接入时仍走原有短弧，并按原规则锁住这群。
			_debug_event("接入点已在外包线内，回退短弧")
		elif debug_enabled: _debug_event("回退短弧：" + debug_capture_reason)
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
	if debug_enabled: debug_revision += 1
	return true

## 首次捕获或续段时读取外沿；续段只读取已捕获群的存活相连成员。
func _eccentric_outline(seed: WaveEnemy, point: Vector3, allowed: Dictionary[int, WaveEnemy] = {}) -> Dictionary:
	# 实际接群也只在本次同步函数内读取已提交的索引；不能存入飞行状态。
	var view := _query_view
	var obstacles := _preview_obstacles
	if view == null and is_instance_valid(session.terrain):
		view = PreviewQueryView.new(session._spatial_index, session)
		if view.eligible: obstacles = ObstacleBatch.new(session.terrain, [session.player.get_rid()])
	if obstacles and view and view.is_current(session._spatial_index):
		var slot := view.slot(seed)
		if slot >= 0: return _view_eccentric_outline(slot, point, allowed, view, obstacles)
	return _legacy_eccentric_outline(seed, point, allowed)

func _legacy_eccentric_outline(seed: WaveEnemy, point: Vector3, allowed: Dictionary[int, WaveEnemy]) -> Dictionary:
	var anchor := seed.global_position
	var radius := minf(rules.eccentric_search_radius, rules.push_group_search_radius)
	session.get_nearby_enemies_into(anchor, radius, {}, _nearby)
	var visible: Dictionary[int, Vector3] = {}
	var bodies: Dictionary[int, float] = {}
	var members: Dictionary[int, WaveEnemy] = {}
	_ray_excluded = [session.player.get_rid()]
	if _preview_obstacles:
		var endpoints := PackedVector3Array([point + Vector3.UP * 0.45])
		for actor in _nearby:
			if actor.spawn_delay > 0.0: continue
			if not allowed.is_empty() and not allowed.has(actor.get_instance_id()): continue
			var position := actor.global_position
			if absf(position.y - point.y) <= rules.push_height_tolerance: endpoints.append(position + Vector3.UP * 0.45)
		_preview_obstacles.cover(endpoints)
	for actor in _nearby:
		if actor.spawn_delay > 0.0: continue
		if not allowed.is_empty() and not allowed.has(actor.get_instance_id()): continue
		var position := actor.global_position
		if absf(position.y - point.y) > rules.push_height_tolerance: continue
		if not _ray_clear(point + Vector3.UP * 0.45, position + Vector3.UP * 0.45): continue
		visible[actor.get_instance_id()] = position
		bodies[actor.get_instance_id()] = actor.get_crowd_body_radius()
	_nearby.clear()
	var minimum := rules.eccentric_minimum_members if allowed.is_empty() else 1
	if visible.size() < minimum or not visible.has(seed.get_instance_id()):
		if debug_enabled: debug_capture_reason = "可见同层成员不足 %d 只（隔墙／异层对象已排除）" % minimum
		return {}
	# 段间死亡或移动可能拆开旧群；只纳入本次仍与接触怪物相连的可见样本。
	var connected: Array[Vector3] = [anchor]
	var visited: Dictionary[int, bool] = {seed.get_instance_id(): true}
	members[seed.get_instance_id()] = seed
	var cursor := 0
	var body_radius := bodies[seed.get_instance_id()]
	var spread := 0.0
	while cursor < connected.size():
		var position := connected[cursor]
		cursor += 1
		var distance := TerrainPath.horizontal_distance(position, anchor)
		spread = maxf(spread, distance)
		session.get_nearby_enemies_into(position, rules.push_group_link_distance, visited, _nearby)
		for actor in _nearby:
			var id := actor.get_instance_id()
			if not visible.has(id): continue
			if not _ray_clear(position + Vector3.UP * 0.45, visible[id] + Vector3.UP * 0.45): continue
			visited[id] = true
			members[id] = actor
			body_radius = maxf(body_radius, bodies[id])
			connected.append(visible[id])
	_nearby.clear()
	if connected.size() < minimum or (allowed.is_empty() and connected.size() > 1 and spread < 0.3):
		if debug_enabled: debug_capture_reason = "相连成员不足 %d 只" % minimum if connected.size() < minimum else "群体重叠，分布不足 0.3 米"
		return {}
	if debug_enabled: debug_capture_reason = "相连 %d 只，分布 %.2f 米" % [connected.size(), spread]
	var player_radius := 0.0
	for child in session.player.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape is CapsuleShape3D:
			var capsule := child.shape as CapsuleShape3D
			player_radius = maxf(player_radius, capsule.radius * maxf(child.global_basis.x.length(), child.global_basis.z.length()))
	return {"positions": PackedVector3Array(connected), "body_radius": body_radius, "player_radius": player_radius, "members": members}

## Same candidate/BFS order and float64 radii as the live-node path. One
## synchronous prediction reuses the authoritative post-move packed index.
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
		# 同步只读视图中已收齐所有可见成员；余下队列只需统计原有分布。
		if visited.size() == visible.size(): continue
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

func _outline_ray_clear(from: Vector3, to: Vector3, obstacles: RefCounted) -> bool:
	return obstacles.proves(from, to) or _ray_clear(from, to)

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
