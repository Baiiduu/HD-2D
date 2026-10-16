class_name BodyPathPrediction
extends RefCounted

## 复用真实 CharacterBody 的碰撞形状和安全边距，只查询运动，不移动节点或结算玩法。
var _parameters := PhysicsTestMotionParameters3D.new()
var _result := PhysicsTestMotionResult3D.new()
var _collision := ProjectileCollision.new()

func trace(body: CharacterBody3D, heading: Vector3, speed: float, seconds: float,
		bounce_limit: int, retention: float, path: TerrainPath, bounds: Rect2,
		tolerance: float, output: AimPathData, max_distance := 12.0, crowd: PlayerCrowdDeflection = null, speed_rules: PlayerRicochetRules = null, followup_distance := -1.0) -> void:
	_collision.center_certificate_enabled = speed_rules != null and speed_rules.flat_ground_certificate_enabled
	# body_test_motion 沿用身体的查询层；同步查询结束后还原，早退也不影响正常走路。
	var mask := PhysicsServer3D.body_get_collision_mask(body.get_rid())
	PhysicsServer3D.body_set_collision_mask(body.get_rid(), mask | ProjectileCollision.MIRROR_SURFACE.COLLISION_LAYER)
	_trace(body, heading, speed, seconds, bounce_limit, retention, path, bounds, tolerance, output, max_distance, crowd, speed_rules, followup_distance)
	PhysicsServer3D.body_set_collision_mask(body.get_rid(), mask)

func _trace(body: CharacterBody3D, heading: Vector3, speed: float, seconds: float,
		bounce_limit: int, retention: float, path: TerrainPath, bounds: Rect2,
		tolerance: float, output: AimPathData, max_distance: float, crowd: PlayerCrowdDeflection, speed_rules: PlayerRicochetRules, followup_distance: float) -> void:
	output.clear()
	if not heading.is_finite() or not is_finite(followup_distance): return
	heading.y = 0.0
	heading = heading.normalized()
	if heading.is_zero_approx() or not is_finite(speed) or not is_finite(seconds) or not is_finite(retention) or not is_finite(max_distance) or speed <= 0.0 or seconds <= 0.0 or retention <= 0.0 or retention > 1.0 or max_distance <= 0.0 or bounce_limit < 0: return
	var transform := body.global_transform
	var plane := path.ground_position(transform.origin).y if path and path.data else transform.origin.y
	var foot_offset := maxf(0.02, transform.origin.y - plane)
	_parameters.margin = body.safe_margin
	_parameters.recovery_as_collision = false
	_parameters.max_collisions = 1
	var bounces := 0
	# 非负值仅推演首次响应及短尾段；负值保留完整路线供只读诊断使用。
	var single_response := followup_distance >= 0.0
	var responded := false
	for iteration in 256:
		var available_seconds := speed_rules.coast_seconds(speed) if speed_rules else seconds
		var available_distance := speed_rules.coast_distance(speed, available_seconds) if speed_rules else speed * available_seconds
		var distance := minf(available_distance, max_distance - output.total_distance)
		if distance <= 0.00001:
			if single_response and responded and output.total_distance >= max_distance - 0.00001:
				output.end_reason = &"preview_limit"
				return
			output.end_reason = (&"speed_depleted" if speed_rules else &"duration") if available_seconds < 0.00001 else &"distance"
			return
		var start := transform.origin
		var curved := false
		if crowd:
			var step := crowd.step(start, heading, distance)
			heading = step.heading
			curved = step.distance < distance - 0.00001
			distance = step.distance
		var allowed := ground_limit(_collision, path, bounds, start, heading, distance, plane, tolerance)
		var reached_edge := allowed < distance - 0.00001
		if allowed <= 0.00001:
			output.end_reason = &"ground_edge" if reached_edge else (&"speed_depleted" if speed_rules else &"duration")
			return
		var group := crowd.contact(start, start + heading * allowed, heading) if crowd else {}
		if not group.is_empty(): allowed *= float(group.entry)
		var displacement := heading * allowed
		if path and path.data: displacement.y = path.ground_position(start + displacement).y + foot_offset - start.y
		var hit := false
		if allowed > 0.00001:
			_parameters.from = transform
			_parameters.motion = displacement
			hit = PhysicsServer3D.body_test_motion(body.get_rid(), _parameters, _result)
			transform.origin += _result.get_travel() if hit else displacement
		var travel := TerrainPath.horizontal_distance(transform.origin, start)
		var used := minf(available_seconds, speed_rules.coast_time_for_distance(speed, travel) if speed_rules else travel / speed)
		output.append(start, transform.origin, heading, used, crowd != null and crowd.orbiting)
		if speed_rules: speed = speed_rules.speed_after_coast(speed, used)
		else: seconds = maxf(0.0, seconds - used)
		if not hit:
			if not group.is_empty() and travel >= allowed - 0.0001:
				if single_response and (responded or followup_distance <= 0.0):
					if not responded: output.crowd_contacts.append(transform.origin)
					output.end_reason = &"preview_limit"
					return
				if speed_rules and not speed_rules.can_rebound(speed, crowd.rules.crowd_speed_retention):
					output.end_reason = &"speed_depleted"
					return
				if crowd.begin_contact(group, transform.origin, heading):
					output.crowd_contacts.append(transform.origin)
					speed = speed_rules.rebound_speed(speed, crowd.rules.crowd_speed_retention) if speed_rules else speed * crowd.rules.crowd_speed_retention
					if single_response:
						responded = true
						# 不走完首段，避免 step() 续建怪群轮廓或推演后续绕圈。
						var tail := minf(followup_distance, crowd.rules.eccentric_step_distance * 0.5) if crowd.orbiting else followup_distance
						max_distance = minf(max_distance, output.total_distance + tail)
				elif single_response:
					output.end_reason = &"preview_limit"
					return
				continue
			if reached_edge:
				output.end_reason = &"ground_edge"
				return
			if single_response and responded and output.total_distance >= max_distance - 0.00001:
				output.end_reason = &"preview_limit"
				return
			if curved: continue
			output.end_reason = (&"speed_depleted" if speed_rules else &"duration") if (speed_rules.coast_seconds(speed) if speed_rules else seconds) < 0.00001 else &"distance"
			return
		if crowd: crowd.cancel_turn()
		var normal := ProjectileCollision.reflection_normal(_result.get_collider(), _result.get_collision_normal(), heading)
		if normal.y > 0.65:
			if travel <= 0.00001:
				output.end_reason = &"ground_contact"
				return
			continue
		var collider := _result.get_collider()
		var terrain_contact := path and is_instance_valid(path.terrain) and collider is Node and path.terrain.is_ancestor_of(collider)
		normal.y = 0.0
		normal = normal.normalized()
		if terrain_contact:
			output.end_reason = &"ground_edge"
			return
		if single_response and responded:
			output.end_reason = &"preview_limit"
			return
		output.contacts.append(transform.origin)
		if normal.is_zero_approx() or heading.dot(normal) >= -0.00001:
			output.end_reason = &"blocked_surface"
			return
		if speed_rules and not speed_rules.can_rebound(speed, retention):
			output.end_reason = &"speed_depleted"
			return
		# 仅限制画面展示长度，实际人物不受这个反弹预览次数约束。
		if bounces >= bounce_limit:
			output.end_reason = &"preview_limit" if speed_rules else &"wall_limit"
			return
		heading = heading.bounce(normal).normalized()
		speed = speed_rules.rebound_speed(speed, retention) if speed_rules else speed * retention
		bounces += 1
		if single_response:
			responded = true
			max_distance = minf(max_distance, output.total_distance + followup_distance)
			if followup_distance <= 0.0:
				output.end_reason = &"preview_limit"
				return
		_parameters.from = transform
		_parameters.motion = normal * 0.003
		var blocked := PhysicsServer3D.body_test_motion(body.get_rid(), _parameters, _result)
		transform.origin += _result.get_travel() if blocked else _parameters.motion
	output.end_reason = &"contact_limit"

## 真实弹射和预览共享地图边界、水面、断层资格，动态障碍不缓存。
static func ground_limit(collision: ProjectileCollision, path: TerrainPath, bounds: Rect2,
		start: Vector3, heading: Vector3, distance: float, plane: float, tolerance: float) -> float:
	var limit := distance
	for axis in [0, 2]:
		var component := heading[axis]
		if absf(component) < 0.00001: continue
		var edge: float = (bounds.end.x if component > 0.0 else bounds.position.x) if axis == 0 else (bounds.end.y if component > 0.0 else bounds.position.y)
		if is_finite(edge): limit = minf(limit, maxf(0.0, (edge - start[axis]) / component))
	return collision.ground_limit(path, start, heading, limit, plane, tolerance) if path and path.data else limit
