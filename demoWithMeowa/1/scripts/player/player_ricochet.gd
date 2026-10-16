class_name PlayerRicochet
extends Node

const PreviewQueryView = preload("res://scripts/combat/preview_spatial_query_view.gd")

signal state_changed(state: State)
signal launched(direction: Vector3, speed: float, charge: float)
signal wall_bounced(point: Vector3, normal: Vector3)
## 已完成真实反弹的碰撞信息，供材质声音使用，不额外查询世界。
signal surface_bounced(collision: KinematicCollision3D)
signal enemy_pushed(enemy: WaveEnemy, tangent: Vector3)
signal crowd_deflected(point: Vector3, incoming: Vector3, outgoing: Vector3)
signal finished(reason: StringName)
## 连续位移的分段轨迹，墙前与反弹后的路段分别发送，秒数不包含瞬移。
signal flight_segment_travelled(start: Vector3, end: Vector3, heading: Vector3, seconds: float)
enum State { IDLE, CHARGING, FLYING, RECOVERY }

var state := State.IDLE
var enabled: bool:
	get: return _enabled()
var direction := Vector3.RIGHT
var flight_speed := 0.0
var bounce_count := 0
## 成功发射时递增，反弹与持续环绕不建立新的发射编号。
var flight_serial := 0
var crowd_deflection_count := 0
var charging: bool:
	get: return state == State.CHARGING
var flying: bool:
	get: return state == State.FLYING
var orbiting: bool:
	get: return flying and _crowd != null and _crowd.orbiting
var charge_fraction: float:
	get: return clampf(_charge_age / _settings.full_charge_seconds, 0.0, 1.0) if _settings else 0.0
var _player: Player
var _session: WavePrototype
var _settings: PlayerRicochetRules
var _charge_age := 0.0
## 兼容诊断读数：按当前速度估算的无碰撞余时，不再是独立倒计时。
var _flight_remaining: float:
	get: return _settings.coast_seconds(flight_speed) if flying and _settings else 0.0
var _recovery_remaining := 0.0
var _cooldown := 0.0
var _press_pending := false
var _release_pending := false
var _attack_pending := false
var _aim_pending := false
var _mouse_charge := false
## 持续采样输入边沿，发射前已按住的键不算新的移动接管。
var _movement_keys := 0
var _movement_active := false
var _pushed: Dictionary[int, bool] = {}
var _push_wave: EnemyPushWave
var _crowd: PlayerCrowdDeflection
var _sword_contacts: Dictionary[int, bool] = {}
var _travel_segments: Array[Dictionary] = []
var _path := TerrainPath.new()
var _collision := ProjectileCollision.new()
var _plane := 0.0
var _foot_offset := 0.02
var _guide: EnemyTelegraph
var _charge_effect: PlayerChargeEffect
## 由非阻塞诊断界面开启；战斗结束前保存最后实际路线，便于停留检查。
var orbit_debug_enabled := false
var orbit_debug_last: Dictionary = {}

func _ready() -> void:
	_player = get_parent() as Player
	if not _player: _player = get_parent().get_parent() as Player
	_session = _player.get_parent().get_node_or_null("WavePrototype") as WavePrototype
	if _session:
		_session.phase_changed.connect(_on_phase_changed)

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled() or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return
	if event.is_action_pressed(&"body_charge"):
		_press_pending = true
		_aim_pending = true
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"body_charge"):
		_release_pending = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"normal_attack"):
		if _player.sword: return
		_attack_pending = true
		get_viewport().set_input_as_handled()
	elif charging and event is InputEventMouseMotion:
		_aim_pending = true

func _enabled() -> bool:
	return _player.ricochet_rules != null and (_player.skill_manager.is_skill_enabled(CharacterSkillManager.BODY_RICOCHET) if is_instance_valid(_player.skill_manager) else _player.ricochet_rules.enabled)

func is_frozen() -> bool:
	return is_instance_valid(_session) and _session.combat_frozen

## 预览与实际发射共用最终数值。速度同时放大起步／满蓄，保留蓄力差异。
func get_stats(modifiers: RunCombatModifiers = null) -> Dictionary:
	var rules := _player.ricochet_rules
	if not _enabled(): return {}
	if not modifiers and is_instance_valid(_session): modifiers = _session.combat_modifiers
	var result := {}
	for attribute in GrowthBuffDefinition.RICOCHET_PROPERTIES:
		var property: StringName = GrowthBuffDefinition.RICOCHET_PROPERTIES[attribute]
		var base: float = rules.get(property)
		result[property] = modifiers.ricochet_value(attribute, base) if modifiers else base
	var base_speed := rules.minimum_launch_speed
	result[&"minimum_launch_speed"] = modifiers.ricochet_value(GrowthBuffDefinition.Attribute.RICOCHET_SPEED, base_speed) if modifiers else base_speed
	result[&"crowd_speed_retention"] = modifiers.ricochet_value(GrowthBuffDefinition.Attribute.RICOCHET_RETENTION, rules.crowd_speed_retention) if modifiers else rules.crowd_speed_retention
	result[&"minimum_bounce_speed"] = rules.minimum_bounce_speed
	return result

func begin_charge(movement: Vector3) -> bool:
	if not _enabled() or state != State.IDLE or _cooldown > 0.0 or _player._blink.active or not _player.is_on_floor() or _player.current_health <= 0.0 or is_frozen(): return false
	if get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return false
	if not _player.ricochet_rules.validation_error().is_empty(): return false
	_settings = _player.ricochet_rules.duplicate()
	var stats := get_stats()
	for property in stats: _settings.set(property, stats[property])
	_collision.center_certificate_enabled = _settings.flat_ground_certificate_enabled
	direction = movement
	direction.y = 0.0
	if direction.is_zero_approx(): direction = _player.facing_direction()
	direction = direction.normalized()
	_charge_age = 0.0
	orbit_debug_last = {}
	_pushed.clear()
	_push_wave = null
	_crowd = null
	_sword_contacts.clear()
	_player._blink.discard_buffered_input()
	_player.action_animator.cancel_attack()
	_change_state(State.CHARGING)
	return true

## 手机／外部输入直接传入世界方向；镜头旋转不会重算已经锁定的方向。
func aim(heading: Vector3) -> void:
	if not charging or not heading.is_finite(): return
	heading.y = 0.0
	if not heading.is_zero_approx(): direction = heading.normalized()

func release_charge() -> bool:
	if not charging or is_frozen(): return false
	if not _player.is_on_floor() or _player.current_health <= 0.0 or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null:
		cancel()
		return false
	var fraction := charge_fraction
	flight_speed = lerpf(_settings.minimum_launch_speed, _settings.maximum_launch_speed, fraction)
	if flight_speed <= _settings.minimum_bounce_speed:
		cancel()
		flight_speed = 0.0
		return false
	bounce_count = 0
	crowd_deflection_count = 0
	if _settings.crowd_deflection_enabled and is_instance_valid(_session):
		_push_wave = EnemyPushWave.new(_settings)
		_crowd = PlayerCrowdDeflection.new(_settings, _session, _push_wave)
		_crowd.debug_enabled = orbit_debug_enabled
	_cooldown = _settings.cooldown_seconds
	_path.terrain = _session.terrain if is_instance_valid(_session) else null
	_path.data = _path.terrain.data if is_instance_valid(_path.terrain) else null
	_plane = _path.ground_position(_player.global_position).y if _path.data else _player.global_position.y
	_foot_offset = maxf(0.02, _player.global_position.y - _plane)
	_mouse_charge = false
	flight_serial += 1
	_change_state(State.FLYING)
	launched.emit(direction, flight_speed, fraction)
	return true

## 返回 true 表示本帧的位移已由弹射接管；人物普通物理不再重复移动。
func advance(delta: float, movement: Vector3, input_blocked: bool, movement_keys := -1) -> bool:
	_travel_segments.clear()
	var was_flying := flying
	var moving := not movement.is_zero_approx()
	# 外部／摇杆输入沿用归零后重新推动；键盘按物理键分别识别新按下。
	var movement_pressed := moving and not _movement_active
	if movement_keys >= 0:
		movement_pressed = (movement_keys & ~_movement_keys) != 0
		_movement_keys = movement_keys
	# 冻结或面板占用时也吸收按键状态，恢复后不补发旧的移动请求。
	_movement_active = moving or input_blocked
	if not _enabled() or _player.current_health <= 0.0:
		cancel()
		return false
	if is_frozen():
		_press_pending = false
		_release_pending = false
		_attack_pending = false
		return flying
	_cooldown = maxf(0.0, _cooldown - delta)
	if input_blocked:
		_press_pending = false
		_release_pending = false
		_attack_pending = false
		if charging: cancel()
	if _press_pending:
		if flying: detach_from_crowd()
		else: _mouse_charge = begin_charge(movement)
		_press_pending = false
	if charging:
		if not _player.is_on_floor(): cancel()
		else:
			_charge_age += delta
			if _aim_pending: aim(cursor_direction())
			if _release_pending: release_charge()
			elif _mouse_charge and not Input.is_action_pressed(&"body_charge"): cancel()
	_aim_pending = false
	_release_pending = false
	# 发射首帧及原键持续按住不打断；飞行后的新移动按下才交回行走。
	if was_flying and flying and not input_blocked and moving and movement_pressed:
		cancel()
		return false
	if _attack_pending:
		request_normal_attack()
		_attack_pending = false
	var owns_motion := flying
	if flying:
		_advance_flight(delta)
	elif state == State.RECOVERY:
		_recovery_remaining = maxf(0.0, _recovery_remaining - delta)
		if _recovery_remaining <= 0.0: _change_state(State.IDLE)
	_update_visual_context()
	return owns_motion

## 与右键二次短按共用；外部输入可调用，不提前停止飞行或刷新攻击状态。
func detach_from_crowd() -> bool:
	if not flying or not _crowd or is_frozen() or _player.current_health <= 0.0: return false
	if get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return false
	var heading := _crowd.departure_heading(_player.global_position, direction)
	if not _crowd.detach(): return false
	direction = heading
	return true

func request_normal_attack() -> bool:
	if _player.sword: return _player.sword.request_manual(cursor_direction())
	if not _enabled() or charging or state == State.RECOVERY or is_frozen() or _player._blink.active or _player.current_health <= 0.0: return false
	if get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return false
	var heading := direction if flying else cursor_direction()
	var action: StringName = &"flight_attack" if flying else &"normal_attack"
	if not _player.action_animator.request_attack(action, heading): return false
	_player.face_world_direction(heading)
	_player.normal_attack_requested.emit(heading)
	return true

func cursor_direction() -> Vector3:
	var camera := _player.movement_camera
	if not is_instance_valid(camera): return _player.facing_direction()
	var cursor := _player.get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, _player.global_position.y)
	var point: Variant = plane.intersects_ray(camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
	if point == null: return _player.facing_direction()
	var heading: Vector3 = point - _player.global_position
	heading.y = 0.0
	return heading.normalized() if heading.length_squared() > 0.04 else _player.facing_direction()

func _advance_flight(delta: float) -> void:
	var mask := PhysicsServer3D.body_get_collision_mask(_player.get_rid())
	PhysicsServer3D.body_set_collision_mask(_player.get_rid(), mask | ProjectileCollision.MIRROR_SURFACE.COLLISION_LAYER)
	var remaining := delta
	var elapsed := 0.0
	var stalled_contacts := 0
	while flying and remaining > 0.000001:
		var step_seconds := minf(remaining, _settings.coast_seconds(flight_speed))
		if step_seconds <= 0.000001:
			_end_flight(&"speed_depleted")
			break
		var start := _player.global_position
		var distance := _settings.coast_distance(flight_speed, step_seconds)
		var curved := false
		if _crowd:
			var step := _crowd.step(start, direction, distance)
			direction = step.heading
			curved = step.distance < distance - 0.00001
			distance = step.distance
		var allowed := _ground_limit(start, distance)
		var reached_edge := allowed < distance - 0.00001
		if allowed <= 0.00001:
			_end_flight(&"ground_edge" if reached_edge else &"speed_depleted")
			break
		var group := _crowd.contact(start, start + direction * allowed, direction) if _crowd else {}
		if not group.is_empty(): allowed *= float(group.entry)
		var motion := direction * allowed
		if _path.data: motion.y = _path.ground_position(start + motion).y + _foot_offset - start.y
		var hit: KinematicCollision3D
		if allowed > 0.00001: hit = _player.move_and_collide(motion)
		var end := _player.global_position
		var travelled := TerrainPath.horizontal_distance(start, end)
		stalled_contacts = stalled_contacts + 1 if travelled <= 0.00001 else 0
		# 只终止无法产生位移的卡死接触；有真实位移就清零，不限制有效反弹。
		if stalled_contacts >= 3:
			_end_flight(&"blocked_contact")
			break
		var seconds := minf(step_seconds, _settings.coast_time_for_distance(flight_speed, travelled))
		var initial_speed := flight_speed
		flight_speed = _settings.speed_after_coast(flight_speed, seconds)
		if travelled > 0.00001:
			if _player.sword and _player.sword.enabled:
				_travel_segments.append({"start":start, "end":end, "heading":direction, "time":elapsed, "seconds":seconds, "speed":initial_speed, "deceleration":_settings.flight_deceleration})
			flight_segment_travelled.emit(start, end, direction, seconds)
			_push_segment(start, end)
		elapsed += seconds
		remaining = maxf(0.0, remaining - seconds)
		if not flying: break
		if not hit:
			if not group.is_empty() and travelled >= allowed - 0.0001:
				if not _settings.can_rebound(flight_speed, _settings.crowd_speed_retention):
					_end_flight(&"speed_depleted")
					break
				var incoming := direction
				if _crowd.begin_contact(group, end, incoming):
					crowd_deflection_count += 1
					flight_speed = _settings.rebound_speed(flight_speed, _settings.crowd_speed_retention)
					crowd_deflected.emit(end, incoming, _crowd.target_heading)
				continue
			if reached_edge: _end_flight(&"ground_edge")
			if curved and flying: continue
			break
		if _crowd: _crowd.cancel_turn(&"真实墙面／镜面／地形接触中断路线")
		var normal := ProjectileCollision.reflection_normal(hit.get_collider(), hit.get_normal(), direction)
		if normal.y > 0.65:
			if travelled <= 0.00001: _end_flight(&"ground_contact")
			continue
		var terrain_contact := is_instance_valid(_path.terrain) and hit.get_collider() is Node and _path.terrain.is_ancestor_of(hit.get_collider())
		if terrain_contact and _path.terrain.is_reflective_water_shape(hit.get_collider(), hit.get_collider_shape_index()): terrain_contact = false
		normal.y = 0.0
		normal = normal.normalized()
		if terrain_contact or normal.is_zero_approx() or direction.dot(normal) >= -0.00001:
			_end_flight(&"blocked_surface")
			break
		if not _settings.can_rebound(flight_speed, _settings.bounce_speed_retention):
			_end_flight(&"speed_depleted")
			break
		direction = direction.bounce(normal).normalized()
		bounce_count += 1
		flight_speed = _settings.rebound_speed(flight_speed, _settings.bounce_speed_retention)
		ProjectileCollision.show_reflection(hit.get_collider())
		wall_bounced.emit(hit.get_position(), normal)
		surface_bounced.emit(hit)
		if not flying: break
		_player.move_and_collide(normal * 0.003)
	PhysicsServer3D.body_set_collision_mask(_player.get_rid(), mask)
	if flying and flight_speed <= _settings.minimum_bounce_speed + 0.000001: _end_flight(&"speed_depleted")
	_player.velocity = direction * flight_speed if flying else Vector3.ZERO
	_player.face_world_direction(direction)

func _ground_limit(start: Vector3, length: float) -> float:
	return BodyPathPrediction.ground_limit(_collision, _path, _player.bounds, start, direction, length, _plane, _settings.ground_height_tolerance)

## 在 flight_segment_travelled 回调中读取本段起速与减速度，之后由消费者保存快照。
func motion_timing(seconds: float) -> Vector2:
	return Vector2(flight_speed + _settings.flight_deceleration * seconds, _settings.flight_deceleration) if flying and _settings else Vector2.ZERO

## 沿本次蓄力快照预览；输出可供其它显示方式消费，不产生位移、攻击或拨怪事件。
func predict_path(query: BodyPathPrediction, output: AimPathData, max_distance: float, preview_bounces: int, followup_distance := -1.0) -> void:
	output.clear()
	if not charging or not _settings: return
	_path.terrain = _session.terrain if is_instance_valid(_session) else null
	_path.data = _path.terrain.data if is_instance_valid(_path.terrain) else null
	var speed := lerpf(_settings.minimum_launch_speed, _settings.maximum_launch_speed, charge_fraction)
	# 短预测只查首次接触，无需为单次查询复制整份怪物空间快照。
	var view := PreviewQueryView.new(_session._spatial_index, _session) if followup_distance < 0.0 and _settings.preview_spatial_queries_enabled and _settings.crowd_deflection_enabled and is_instance_valid(_session) else null
	query.trace(_player, direction, speed,
		_settings.coast_seconds(speed), mini(preview_bounces, 1) if followup_distance >= 0.0 else preview_bounces, _settings.bounce_speed_retention,
		_path, _player.bounds, _settings.ground_height_tolerance, output, max_distance,
		PlayerCrowdDeflection.new(_settings, _session, null, view) if _settings.crowd_deflection_enabled and is_instance_valid(_session) else null, _settings, followup_distance)

func _push_segment(start: Vector3, end: Vector3) -> void:
	if not _settings.enemy_push_enabled: return
	if not is_instance_valid(_session) or not _session.combat_active() or _settings.push_initial_speed <= 0.0: return
	var length := TerrainPath.horizontal_distance(start, end)
	var candidates := _session.get_nearby_enemies((start + end) * 0.5, _settings.push_radius + length * 0.5)
	for enemy in candidates:
		if not flying or not _session.combat_active(): return
		if enemy.dead or enemy.spawn_delay > 0.0 or _already_pushed(enemy) or absf(enemy.global_position.y - start.y) > _settings.push_height_tolerance: continue
		if _player.sword and _player.sword.enabled and not _sword_contacts.has(enemy.get_instance_id()): continue
		var entry := circle_entry(start, end, enemy.global_position, _settings.push_radius)
		if entry < 0.0: continue
		var center := start.lerp(end, entry)
		var ray := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 0.45, enemy.global_position + Vector3.UP * 0.45, 1, [_player.get_rid()])
		if not _player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		var tangent := tangent_direction(enemy.global_position - center, direction, _settings.clockwise)
		if _apply_push(enemy, tangent):
			_pushed[enemy.get_instance_id()] = true
			enemy_pushed.emit(enemy, tangent)

func _apply_push(enemy: WaveEnemy, tangent: Vector3) -> bool:
	if not _push_wave or _push_wave.rules != _settings: _push_wave = EnemyPushWave.new(_settings)
	return _push_wave.push(enemy, tangent, _settings.push_initial_speed, _settings.push_seconds, _settings.push_stun_seconds)

func _already_pushed(enemy: WaveEnemy) -> bool:
	return _pushed.has(enemy.get_instance_id()) or (_push_wave != null and _push_wave.rules == _settings and _push_wave.has_target(enemy.get_instance_id()))

static func tangent_direction(radial: Vector3, incoming: Vector3, clockwise: bool) -> Vector3:
	radial.y = 0.0
	if radial.is_zero_approx():
		radial = -incoming
		radial.y = 0.0
	if radial.is_zero_approx(): radial = Vector3.RIGHT
	return radial.normalized().cross(Vector3.UP) * (1.0 if clockwise else -1.0)

## 基础剑术先结算真实伤害，再请求本次发射尚未拨动的存活怪物。
func push_after_sword_hit(enemy: WaveEnemy, center: Vector3, incoming: Vector3, contact_time := 0.0) -> bool:
	if not _settings or not _settings.enemy_push_enabled: return false
	if state not in [State.FLYING, State.RECOVERY] or not _settings or not is_instance_valid(enemy) or enemy.dead or enemy.spawn_delay > 0.0: return false
	if not is_instance_valid(_session) or not _session.combat_active() or _settings.push_initial_speed <= 0.0 or _already_pushed(enemy): return false
	_sword_contacts[enemy.get_instance_id()] = true
	# 剑锋比拨怪圈长时，保留受伤资格；同帧剩余真实折线路段和后续飞行均可接上拨怪。
	if TerrainPath.horizontal_distance(center, enemy.global_position) > _settings.push_radius:
		var found := false
		for piece in _travel_segments:
			if piece.time + piece.seconds < contact_time: continue
			var fraction := PlayerRicochetRules.segment_fraction(contact_time - piece.time, piece.seconds, piece.speed, piece.deceleration)
			var start: Vector3 = piece.start.lerp(piece.end, fraction)
			var entry := circle_entry(start, piece.end, enemy.global_position, _settings.push_radius)
			if entry < 0.0: continue
			center = start.lerp(piece.end, entry)
			incoming = piece.heading
			found = true
			break
		if not found: return false
	if absf(enemy.global_position.y - center.y) > _settings.push_height_tolerance: return false
	var ray := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 0.45, enemy.global_position + Vector3.UP * 0.45, 1, [_player.get_rid()])
	if not _player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	var tangent := tangent_direction(enemy.global_position - center, incoming, _settings.clockwise)
	if not _apply_push(enemy, tangent): return false
	_pushed[enemy.get_instance_id()] = true
	enemy_pushed.emit(enemy, tangent)
	return true

## 圆心沿线段移动，返回首次覆盖怪物中心的 0～1 进度；低帧率也不漏过怪群。
static func circle_entry(start: Vector3, end: Vector3, point: Vector3, radius: float) -> float:
	var offset := Vector2(point.x - start.x, point.z - start.z)
	if offset.length_squared() <= radius * radius: return 0.0
	var motion := Vector2(end.x - start.x, end.z - start.z)
	var squared := motion.length_squared()
	if squared <= 0.00000001: return -1.0
	var projection := offset.dot(motion) / squared
	var perpendicular := offset.length_squared() - projection * projection * squared
	if perpendicular > radius * radius: return -1.0
	var entry := projection - sqrt(maxf(0.0, radius * radius - perpendicular) / squared)
	return entry if entry >= 0.0 and entry <= 1.0 else -1.0

func _update_visual_context() -> void:
	var action: StringName = &""
	var progress := -1.0
	match state:
		State.CHARGING:
			action = &"charge"
			progress = charge_fraction
			_player.face_world_direction(direction)
		State.FLYING: action = &"flight"
		State.RECOVERY:
			action = &"recovery"
			progress = 1.0 - _recovery_remaining / maxf(_settings.recovery_seconds, 0.00001)
	_player.action_animator.set_context(action, direction, progress)
	var visuals := _player.action_visuals
	if visuals != null and charging and visuals.show_charge_effect:
		if not is_instance_valid(_charge_effect):
			_charge_effect = PlayerChargeEffect.new()
			_charge_effect.name = "ChargeEffect"
			_player.add_child(_charge_effect)
		_charge_effect.coalesce_preview_updates = visuals.coalesce_charge_preview
		_charge_effect.display(_player, self, visuals)
	elif is_instance_valid(_charge_effect): _charge_effect.stop()
	var show_ring := visuals != null and flying and _settings.enemy_push_enabled and visuals.show_push_ring
	if show_ring:
		if not is_instance_valid(_guide):
			_guide = EnemyTelegraph.new()
			_player.add_child(_guide)
		var point := _path.ground_position(_player.global_position) if _path.data else _player.global_position
		_guide.ring(point, _settings.push_radius)
		_guide.set_tint(Color(0.35, 0.85, 1.0))
		_guide.set_opacity(0.35)
	elif is_instance_valid(_guide): _guide.hide()

func _change_state(value: State) -> void:
	state = value
	_update_visual_context()
	state_changed.emit(state)

func _end_flight(reason: StringName) -> void:
	_collision.center_certificate_enabled = false
	if orbit_debug_enabled and _crowd: orbit_debug_last = _crowd.debug_snapshot()
	_crowd = null
	flight_speed = 0.0
	_player.velocity = Vector3.ZERO
	_player.action_animator.cancel_attack()
	_recovery_remaining = _settings.recovery_seconds
	_change_state(State.RECOVERY if _recovery_remaining > 0.0 else State.IDLE)
	finished.emit(reason)

func cancel(reset_cooldown := false) -> void:
	_collision.center_certificate_enabled = false
	if orbit_debug_enabled and _crowd: orbit_debug_last = _crowd.debug_snapshot()
	var was_active := state != State.IDLE
	if flying: _player.velocity = Vector3.ZERO
	flight_speed = 0.0
	_mouse_charge = false
	_press_pending = false
	_release_pending = false
	_attack_pending = false
	_aim_pending = false
	_pushed.clear()
	_push_wave = null
	_sword_contacts.clear()
	_travel_segments.clear()
	_crowd = null
	if reset_cooldown: _cooldown = 0.0
	if _player.action_animator:
		_player.action_animator.cancel_attack()
		if was_active: _change_state(State.IDLE)
	if was_active: finished.emit(&"cancelled")

func _on_phase_changed(phase: WavePrototype.Phase) -> void:
	if phase != WavePrototype.Phase.BATTLE: cancel(true)
