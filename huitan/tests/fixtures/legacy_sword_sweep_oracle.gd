extends "res://scripts/player/player_sword.gd"

## Frozen pre-optimization sweep and reach rules; independent regression oracle.

func _can_reach(origin: Vector3, enemy: WaveEnemy) -> bool:
	var height := _settings.height_tolerance if swinging else rules.height_tolerance
	if not _eligible(enemy) or absf(_path.ground_position(origin).y - _path.ground_position(enemy.global_position).y) > height: return false
	var point := _path.ground_position(origin)
	if absf(enemy.global_position.y - point.y) > height: return false
	var target := _path.ground_position(enemy.global_position)
	var length := TerrainPath.horizontal_distance(point, target)
	var direction := (target - point).normalized()
	if _collision.ground_limit(_path, point, direction, length, point.y, height) < length - 0.00001: return false
	return _path.terrain.ray_clear(point + Vector3.UP * 0.45, target + Vector3.UP * 0.45, 1, [player.get_rid()])

func _collect_hits(start: Vector3, end: Vector3, first: float, last: float, moving_flight: bool, start_time: float, seconds: float, speed := 0.0, deceleration := 0.0) -> void:
	if not _combat_active(): return
	var basis := Basis(Vector3.UP, atan2(-_heading.x, -_heading.z))
	var angle: float = deg_to_rad(_stats.angle)
	var steps := maxi(1, maxi(ceili(TerrainPath.horizontal_distance(start, end) / 0.03), ceili(absf(last - first) * angle / deg_to_rad(2.0))))
	var candidates := session.get_nearby_enemies((start + end) * 0.5, _stats.range + TerrainPath.horizontal_distance(start, end) * 0.5)
	for index in steps:
		var a := start.lerp(end, float(index) / steps)
		var b := start.lerp(end, float(index + 1) / steps)
		var p := lerpf(first, last, float(index) / steps)
		var q := lerpf(first, last, float(index + 1) / steps)
		var left := lerpf(-angle * 0.5, angle * 0.5, 1.0 - p if _reverse else p)
		var right := lerpf(-angle * 0.5, angle * 0.5, 1.0 - q if _reverse else q)
		var tip_a: Vector3 = a + basis * Vector3(sin(left), 0, -cos(left)) * float(_stats.range)
		var tip_b: Vector3 = b + basis * Vector3(sin(right), 0, -cos(right)) * float(_stats.range)
		for enemy in candidates:
			if not _eligible(enemy) or _hits.has(enemy.get_instance_id()): continue
			var entry := PlayerRicochet.circle_entry(a, b, enemy.global_position, _stats.range)
			if entry < 0.0 or not swept_blade(enemy.global_position, a, tip_a, tip_b, b): continue
			var origin := a.lerp(b, entry)
			if not _can_reach(origin, enemy): continue
			_hits[enemy.get_instance_id()] = true
			var time := PlayerRicochetRules.segment_time((index + entry) / steps, seconds, speed, deceleration)
			var motion := (end - start).normalized() * maxf(0.0, speed - deceleration * time) if speed > 0.0 else (end - start) / maxf(seconds, 0.000001)
			_pending_hits.append({"enemy": enemy, "damage": _stats.damage, "origin": origin, "heading": _heading, "flying": _flight_swing and moving_flight, "flight_id": player.body_ricochet.flight_serial if _flight_swing and moving_flight else 0, "time":start_time + seconds * (index + entry) / steps,
				"motion_velocity": motion, "contact_distance": TerrainPath.horizontal_distance(origin, enemy.global_position), "slash_direction": (tip_b - tip_a).normalized()})
