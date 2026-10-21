extends "res://scripts/player/player_sword.gd"
## Frozen pre-filter sweep, including its original blade geometry.
func _collect_hits(start: Vector3, end: Vector3, first: float, last: float, moving_flight: bool, start_time: float, seconds: float, speed := 0.0, deceleration := 0.0) -> void:
	if not _combat_active(): return
	var basis := Basis(Vector3.UP, atan2(-_heading.x, -_heading.z))
	var angle: float = deg_to_rad(_stats.angle)
	var steps := maxi(1, maxi(ceili(TerrainPath.horizontal_distance(start, end) / 0.03), ceili(absf(last - first) * angle / deg_to_rad(2.0))))
	# 公共查询的覆写可能返回共享列表；切片内只裁减本次自己的候选。
	var candidates: Array[WaveEnemy] = session.get_nearby_enemies((start + end) * 0.5, _stats.range + TerrainPath.horizontal_distance(start, end) * 0.5).duplicate()
	for index in steps:
		if candidates.is_empty(): break
		var a := start.lerp(end, float(index) / steps)
		var b := start.lerp(end, float(index + 1) / steps)
		var p := lerpf(first, last, float(index) / steps)
		var q := lerpf(first, last, float(index + 1) / steps)
		var left := lerpf(-angle * 0.5, angle * 0.5, 1.0 - p if _reverse else p)
		var right := lerpf(-angle * 0.5, angle * 0.5, 1.0 - q if _reverse else q)
		var tip_a: Vector3 = a + basis * Vector3(sin(left), 0, -cos(left)) * float(_stats.range)
		var tip_b: Vector3 = b + basis * Vector3(sin(right), 0, -cos(right)) * float(_stats.range)
		# 已处理目标不再参与剩余切片；顺序和未命中目标的精确采样保持不变。
		var candidate_index := 0
		while candidate_index < candidates.size():
			var enemy: WaveEnemy = candidates[candidate_index]
			if not _eligible(enemy) or _hits.has(enemy.get_instance_id()):
				candidates.remove_at(candidate_index)
				continue
			var entry := PlayerRicochet.circle_entry(a, b, enemy.global_position, _stats.range)
			if entry < 0.0 or not swept_blade(enemy.global_position, a, tip_a, tip_b, b):
				candidate_index += 1
				continue
			var origin := a.lerp(b, entry)
			if not _can_reach(origin, enemy):
				candidate_index += 1
				continue
			_hits[enemy.get_instance_id()] = true
			candidates.remove_at(candidate_index)
			var time := PlayerRicochetRules.segment_time((index + entry) / steps, seconds, speed, deceleration)
			var motion := (end - start).normalized() * maxf(0.0, speed - deceleration * time) if speed > 0.0 else (end - start) / maxf(seconds, 0.000001)
			var hit_heading := _heading
			if _flight_swing and _stats.angle >= 360.0:
				var outward := enemy.global_position - origin
				outward.y = 0.0
				if not outward.is_zero_approx(): hit_heading = outward.normalized()
			var damage: float = _stats.damage
			if _strike_index > 0: damage *= float(_stats.attack_snapshot.additional_strike_damage_ratio)
			_pending_hits.append({"enemy": enemy, "damage": damage, "origin": origin, "heading": hit_heading, "flying": _flight_swing and moving_flight, "flight_id": player.body_ricochet.flight_serial if _flight_swing and moving_flight else 0, "time":start_time + seconds * (index + entry) / steps,
				"motion_velocity": motion, "contact_distance": TerrainPath.horizontal_distance(origin, enemy.global_position), "slash_direction": (tip_b - tip_a).normalized(), "score_batch": _stats.get("score_batch"), "attack_snapshot": _stats.get("attack_snapshot")})

static func swept_blade(point: Vector3, a: Vector3, tip_a: Vector3, tip_b: Vector3, b: Vector3) -> bool:
	var p := Vector2(point.x, point.z)
	var root_a := Vector2(a.x, a.z)
	var root_b := Vector2(b.x, b.z)
	var edge_a := Vector2(tip_a.x, tip_a.z)
	var edge_b := Vector2(tip_b.x, tip_b.z)
	if _triangle(p, root_a, edge_a, edge_b) or _triangle(p, root_a, edge_b, root_b): return true
	# 刀锋约 0.06 米厚，连续包围两端及外缘，不依赖单帧位置抽样。
	for edge in [[root_a, edge_a], [edge_a, edge_b], [edge_b, root_b]]:
		if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, edge[0], edge[1])) <= 0.03 * 0.03: return true
	return false

static func _triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	if absf((b - a).cross(c - a)) < 0.00000001: return false
	var u := (b - a).cross(p - a)
	var v := (c - b).cross(p - b)
	var w := (a - c).cross(p - c)
	return (u >= 0.0 and v >= 0.0 and w >= 0.0) or (u <= 0.0 and v <= 0.0 and w <= 0.0)
