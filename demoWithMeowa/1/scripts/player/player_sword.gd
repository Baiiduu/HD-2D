class_name PlayerSword
extends Node3D

signal strike_started(direction: Vector3, flying: bool, reverse: bool)
signal hit_landed(enemy: WaveEnemy, damage: float, flying: bool)

var player: Player
var session: WavePrototype
var rules: PlayerSwordRules
var enabled: bool:
	get: return _enabled()
var swinging: bool:
	get: return _age >= 0.0
var _age := -1.0
var _since_strike := 1000.0
var _reverse := false
var _next_reverse := false
var _flight_swing := false
var _heading := Vector3.RIGHT
var _stats := {}
var _settings: PlayerSwordRules
var _hits: Dictionary[int, bool] = {}
var _pending_hits: Array[Dictionary] = []
var _pending_pushes: Array[Dictionary] = []
var _motion: Array[Dictionary] = []
var _last_position := Vector3.ZERO
var _manual_held := false
var _tap := false
var _requested_heading := Vector3.ZERO
var _path := TerrainPath.new()
var _surface: RefCounted
var _collision := ProjectileCollision.new()
var _effect: GroundSlashEffect
var _tail_pool: Array[Dictionary] = []
var _frame_seconds := 0.0
var _audio: GameAudio
var _hit_sounds := 0
var _piece_time := 0.0
var _score: RunScore
var _strike_index := 0
var _strike_total := 1

func _ready() -> void:
	player = get_parent() as Player
	rules = player.sword_rules
	session = player.get_parent().get_node_or_null("WavePrototype") as WavePrototype
	_last_position = player.global_position
	_effect = GroundSlashEffect.new()
	_effect.name = "SwordSlash"
	add_child(_effect)
	_effect.top_level = true
	if session:
		_score = session.get_node_or_null("RunScore") as RunScore
		session.register_combat_node(self)
		_surface = session.get_attack_surface_query()
		session.phase_changed.connect(_on_phase)
		session.combat_frozen_changed.connect(_on_freeze)
		_path.terrain = session.terrain
		_path.data = session.terrain.data if session.terrain else null
	player.body_ricochet.flight_segment_travelled.connect(_on_flight_segment)
	player.body_ricochet.state_changed.connect(_on_body_state)
	player.blink_travelled.connect(_on_blink)

func prepare_feedback() -> void:
	if not rules: return
	while _tail_pool.size() < 4:
		var effect := GroundSlashEffect.new()
		effect.name = "SwordResidue%d" % _tail_pool.size()
		add_child(effect)
		effect.top_level = true
		_tail_pool.append({"effect": effect, "age": -1.0})
	for flying in [false, true]:
		var settings := rules.duplicate() as PlayerSwordRules
		if flying and rules.flight_ribbon_visual:
			settings.effect_mode = PlayerSwordRules.SlashVisual.NATIVE_RIBBON
			settings.ribbon_visual = rules.flight_ribbon_visual
		var stats := get_stats(flying)
		_effect.prepare_feedback(settings, stats.range, stats.angle)
		for tail in _tail_pool: tail.effect.prepare_feedback(settings, stats.range, stats.angle)

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled() or _blocked(): return
	if event.is_action_pressed(&"normal_attack"):
		_manual_held = true
		_tap = not player.body_ricochet.flying
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"normal_attack"):
		_manual_held = false
		get_viewport().set_input_as_handled()

## 供既有人物输入接口或后续触控按钮调用；真实出手仍受同一时钟控制。
func request_manual(heading: Vector3) -> bool:
	if not _enabled() or _blocked() or player.body_ricochet.charging or player._blink.active or player.current_health <= 0.0: return false
	if player.body_ricochet.flying: return false
	if session and session.combat_frozen: return false
	if swinging or _since_strike + 0.00001 < get_stats(player.body_ricochet.flying).interval: return false
	_requested_heading = heading
	_tap = true
	return true

## 人物移动之前读取，包含本物理步内即将开始的按住连击，避免先走一步再起刀。
func blocks_normal_movement(delta := 0.0) -> bool:
	if not _enabled() or player.current_health <= 0.0 or player.body_ricochet.charging or player.body_ricochet.flying or player._blink.active: return false
	if swinging:
		return not _flight_swing and _settings.normal_stationary_enabled and _age < _settings.windup_seconds + _settings.sweep_seconds - 0.000001
	if not rules.normal_stationary_enabled: return false
	var requested := _tap or (_manual_held and Input.is_action_pressed(&"normal_attack"))
	if not requested or _blocked() or player.body_ricochet.state == PlayerRicochet.State.RECOVERY or not rules.validation_error().is_empty(): return false
	return _since_strike + maxf(delta, 0.0) + 0.00001 >= get_stats(false).interval

## 仅站定普攻让位给闪身；保留已消耗的攻击间隔，不清除其它自动攻击。
func interrupt_normal_attack() -> void:
	if swinging and (_flight_swing or not _settings.normal_stationary_enabled): return
	if not swinging and not rules.normal_stationary_enabled: return
	cancel(false)
	player.action_animator.cancel_normal_attack()

func get_stats(flying := false, modifiers: RunCombatModifiers = null) -> Dictionary:
	var result := {"damage": rules.damage, "range": rules.flight_range if flying else rules.normal_range,
		"angle": rules.flight_angle if flying else rules.normal_angle,
		"interval": rules.flight_interval if flying else rules.normal_interval}
	var interval_scale := 1.0
	if not modifiers and session: modifiers = session.combat_modifiers
	if modifiers:
		result.damage *= modifiers.damage_multiplier()
		result.range *= modifiers.range_multiplier()
		interval_scale = modifiers.interval_multiplier()
	# 最短间隔同时约束完整动作，不截断上一刀，也不改变基础资源。
	var motion_duration := rules.windup_for(flying) + rules.sweep_seconds + rules.fade_seconds
	var base_interval: float = maxf(result.interval, motion_duration)
	result.interval = maxf(base_interval * interval_scale, rules.minimum_attack_interval)
	result.motion_scale = float(result.interval) / base_interval
	return result

func get_combat_stats(modifiers: RunCombatModifiers = null) -> Dictionary:
	if not _enabled(): return {}
	var result := get_stats(false, modifiers)
	result.name = "基础剑术"
	return result

## 成长资格同时检查两种模式，避免飞行间隔封底时误删仍能强化普攻的卡。
func get_combat_stat_variants(modifiers: RunCombatModifiers = null) -> Array[Dictionary]:
	var normal := get_combat_stats(modifiers)
	if normal.is_empty(): return []
	var flight := get_stats(true, modifiers)
	flight.name = "弹射挥剑"
	return [normal, flight]

func _blocked() -> bool:
	return get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null

func _enabled() -> bool:
	if not rules: return false
	return rules.enabled

func _physics_process(delta: float) -> void:
	if player.hit_stop_active: return
	if not _enabled() or not rules.validation_error().is_empty() or player.current_health <= 0.0:
		cancel()
		_last_position = player.global_position
		_motion.clear()
		return
	if session and session.combat_frozen: return
	if _blocked():
		_manual_held = false
		_tap = false
	if _manual_held and not Input.is_action_pressed(&"normal_attack"): _manual_held = false
	_drain_hits()
	if session and session.combat_frozen: return
	if session and session.terrain:
		_path.terrain = session.terrain
		_path.data = session.terrain.data
	_frame_seconds = delta
	_advance_tails(delta)
	var used := 0.0
	var cursor := _last_position
	for piece in _motion:
		if piece.seconds <= 0.000001: continue
		_piece_time = used
		_simulate(piece.start, piece.end, piece.seconds, true, piece.heading, piece.get("speed", 0.0), piece.get("deceleration", 0.0), piece.get("orbiting", false), piece.get("energy_speed", -1.0), piece.get("energy_deceleration", 0.0))
		used += piece.seconds
		cursor = piece.end
	if used < delta - 0.000001:
		_piece_time = used
		_simulate(cursor, player.global_position, delta - used, player.body_ricochet.flying, player.body_ricochet.direction, 0.0, 0.0, player.body_ricochet.orbiting)
	_motion.clear()
	_last_position = player.global_position
	# 先记录本帧真实运动中的全部刀锋接触，再扣血；升级中断时保留未结算接触。
	_drain_hits()
	_sync_normal_animation()
	_update_effect()

func _simulate(start: Vector3, end: Vector3, seconds: float, flying: bool, heading: Vector3, speed := 0.0, deceleration := 0.0, orbiting := false, energy_speed := -1.0, energy_deceleration := 0.0) -> void:
	var time := 0.0
	while time < seconds - 0.000001:
		var fraction := PlayerRicochetRules.segment_fraction(time, seconds, speed, deceleration)
		var position := start.lerp(end, fraction)
		var remaining := seconds - time
		if not swinging:
			var stats := get_stats(flying)
			var wait := maxf(0.0, float(stats.interval) - _since_strike)
			if wait > 0.000001:
				var step := minf(wait, remaining)
				_since_strike += step
				time += step
				continue
			var can_start := not player.body_ricochet.charging and not player._blink.active
			if flying and can_start:
				var target := _first_target(position, end, heading, stats, orbiting)
				if float(target.entry) < 0.0:
					_since_strike += remaining
					return
				var delay := maxf(0.0, PlayerRicochetRules.segment_time(lerpf(fraction, 1.0, float(target.entry)), seconds, speed, deceleration) - time)
				time += delay
				_since_strike += delay
				_begin(target.heading, true, maxf(0.0, energy_speed - energy_deceleration * time) if energy_speed >= 0.0 else -1.0)
			elif can_start and player.body_ricochet.state != PlayerRicochet.State.RECOVERY and not _blocked() and (_tap or _manual_held):
				var aim := _requested_heading if not _requested_heading.is_zero_approx() else player.body_ricochet.cursor_direction()
				_begin(aim, false)
			else:
				_since_strike += remaining
				return
			continue
		var boundary := _settings.duration()
		if _age < _settings.windup_seconds - 0.000001: boundary = _settings.windup_seconds
		elif _age < _settings.windup_seconds + _settings.sweep_seconds - 0.000001: boundary = _settings.windup_seconds + _settings.sweep_seconds
		var step := minf(remaining, maxf(boundary - _age, 0.000001))
		if _age >= _settings.windup_seconds - 0.000001 and _age < _settings.windup_seconds + _settings.sweep_seconds - 0.000001:
			var from := start.lerp(end, fraction)
			var to := start.lerp(end, PlayerRicochetRules.segment_fraction(time + step, seconds, speed, deceleration))
			_collect_hits(from, to, (_age - _settings.windup_seconds) / _settings.sweep_seconds, (_age + step - _settings.windup_seconds) / _settings.sweep_seconds, flying, _piece_time + time, step, maxf(0.0, speed - deceleration * time), deceleration)
			if _age + step >= _settings.windup_seconds + _settings.sweep_seconds - 0.000001:
				_start_tail(to, maxf(0.0, _frame_seconds - _piece_time - time - step))
		_age += step
		_since_strike += step
		time += step
		if _age >= _settings.duration() - 0.000001:
			_strike_index += 1
			if _strike_index < _strike_total:
				# 同一次出手内连续完整扫击；逐刀去重与挡墙，频率仍按根出手计算。
				_age = 0.0
				_hits.clear()
				if not (_settings.ribbon_visual and _settings.ribbon_visual.ribbon_orbit_enabled): _reverse = not _reverse
				strike_started.emit(_heading, _flight_swing, _reverse)
			else: _age = -1.0
			_effect.hide()

func _begin(heading: Vector3, flying: bool, remaining_speed := -1.0) -> void:
	_settings = rules.duplicate()
	if flying and rules.flight_ribbon_visual:
		_settings.effect_mode = PlayerSwordRules.SlashVisual.NATIVE_RIBBON
		_settings.ribbon_visual = rules.flight_ribbon_visual
	if _settings.ribbon_visual: _settings.ribbon_visual = _settings.ribbon_visual.duplicate()
	if flying and player.action_visuals and player.action_visuals.combat_readability_enabled and _settings.meowa_body_opacity > 0.0:
		_settings.meowa_body_opacity = maxf(_settings.meowa_body_opacity, player.action_visuals.combat_sword_body_opacity)
	_stats = get_stats(flying)
	var snapshot := session.attack_snapshot(flying, remaining_speed) if session else CombatAttackSnapshot.new()
	_stats.attack_snapshot = snapshot
	_stats.damage *= snapshot.speed_damage_multiplier
	_strike_total = snapshot.strikes
	_strike_index = 0
	_stats.score_batch = _score.begin_attack() if is_instance_valid(_score) else null
	var motion_scale := float(_stats.motion_scale) / _strike_total
	_settings.windup_seconds = rules.windup_for(flying) * motion_scale
	_settings.sweep_seconds *= motion_scale
	_settings.fade_seconds *= motion_scale
	_heading = heading.normalized()
	_heading.y = 0.0
	if _heading.is_zero_approx(): _heading = player.facing_direction()
	_flight_swing = flying
	_reverse = _next_reverse
	if not flying and _settings.normal_slash_alignment_enabled:
		var right := player.movement_camera.global_basis.x if player.movement_camera else Vector3.RIGHT
		right.y = 0.0
		_reverse = _heading.dot(right.normalized()) < -0.0001
	if flying and _settings.ribbon_visual and _settings.ribbon_visual.ribbon_orbit_enabled: _reverse = false
	_next_reverse = not _next_reverse
	_age = 0.0
	_since_strike = 0.0
	_hits.clear()
	_hit_sounds = 0
	_tap = false
	_requested_heading = Vector3.ZERO
	player.face_world_direction(_heading)
	player.action_animator.play_attack(&"flight_attack" if flying else &"normal_attack", _heading, _settings.duration() * _strike_total)
	_sync_normal_animation()
	player.normal_attack_requested.emit(_heading)
	strike_started.emit(_heading, flying, _reverse)
	_play_sound(false, player.global_position)

func _sync_normal_animation() -> void:
	if _flight_swing or not _settings or not _settings.normal_slash_alignment_enabled: return
	player.action_animator.sync_normal_attack(_age, Vector3(_settings.windup_seconds, _settings.sweep_seconds, _settings.fade_seconds), _settings.normal_attack_frame_breaks, _reverse)

func _combat_active() -> bool:
	return is_instance_valid(session) and session.combat_active() and _path.data != null

func _eligible(enemy: WaveEnemy) -> bool:
	return is_instance_valid(enemy) and not enemy.dead and enemy.spawn_delay <= 0.0

func _can_reach(origin: Vector3, enemy: WaveEnemy) -> bool:
	var height := _settings.height_tolerance if swinging else rules.height_tolerance
	if not _eligible(enemy): return false
	var point := _path.ground_position(origin)
	var target := _path.ground_position(enemy.global_position)
	if absf(point.y - target.y) > height or absf(enemy.global_position.y - point.y) > height: return false
	var length := TerrainPath.horizontal_distance(point, target)
	var direction := (target - point).normalized()
	if _collision.ground_limit(_path, point, direction, length, point.y, height) < length - 0.00001: return false
	return _path.terrain.ray_clear(point + Vector3.UP * 0.45, target + Vector3.UP * 0.45, 1, [player.get_rid()])

func _first_target(start: Vector3, end: Vector3, heading: Vector3, stats: Dictionary, auto_aim := false) -> Dictionary:
	var result := {"entry": -1.0, "heading": heading}
	if not _combat_active(): return result
	var best := INF
	var nearest := INF
	for enemy in session.get_nearby_enemies((start + end) * 0.5, stats.range + TerrainPath.horizontal_distance(start, end) * 0.5):
		var entry := _target_entry(enemy, start, end, heading, stats, best + (0.000001 if auto_aim else 0.0), auto_aim)
		if entry < 0.0: continue
		var offset := enemy.global_position - start.lerp(end, entry)
		offset.y = 0.0
		var distance := offset.length_squared()
		if auto_aim and is_equal_approx(entry, best) and distance >= nearest: continue
		best = entry
		nearest = distance
		result = {"entry": entry, "heading": offset.normalized() if auto_aim and not offset.is_zero_approx() else heading}
	return result

func _target_entry(enemy: WaveEnemy, start: Vector3, end: Vector3, heading: Vector3, stats: Dictionary, best: float, auto_aim := false) -> float:
	if not _eligible(enemy): return -1.0
	var entry := PlayerRicochet.circle_entry(start, end, enemy.global_position, stats.range)
	if entry < 0.0 or entry >= best: return -1.0
	var origin := start.lerp(end, entry)
	var offset := enemy.global_position - origin
	offset.y = 0.0
	if not auto_aim and absf(heading.signed_angle_to(offset, Vector3.UP)) > deg_to_rad(stats.angle * 0.5) + 0.00001: return -1.0
	if not _can_reach(origin, enemy): return -1.0
	return entry

## 当前怪物位置下首个可触及目标；复用真实挥剑资格，不结算伤害或修改出手时钟。
func preview_target(route: AimPathData) -> WaveEnemy:
	if not _enabled() or not rules.validation_error().is_empty() or not _combat_active(): return null
	var stats := get_stats(true)
	for piece in route.segments:
		var best := INF
		var target: WaveEnemy
		for enemy in session.get_nearby_enemies((piece.start + piece.end) * 0.5, stats.range + TerrainPath.horizontal_distance(piece.start, piece.end) * 0.5):
			var entry := _target_entry(enemy, piece.start, piece.end, piece.heading, stats, best, piece.get("orbiting", false))
			if entry >= 0.0:
				best = entry
				target = enemy
		if target: return target
	return null

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

func _drain_hits() -> void:
	while not _pending_pushes.is_empty() and _combat_active():
		var push: Dictionary = _pending_pushes.pop_front()
		if _eligible(push.enemy): player.body_ricochet.push_after_sword_hit(push.enemy, push.origin, push.heading)
	while not _pending_hits.is_empty() and _combat_active():
		var hit: Dictionary = _pending_hits.pop_front()
		var enemy: WaveEnemy = hit.enemy
		if not _eligible(enemy): continue
		var before := enemy.health
		enemy.take_damage(hit.damage, {"source": &"flight_sword" if hit.flying else &"basic_sword", "direction": hit.heading, "flight_id": hit.get("flight_id", 0), "motion_velocity": hit.get("motion_velocity", Vector3.ZERO), "contact_distance": hit.get("contact_distance", TerrainPath.horizontal_distance(hit.origin, enemy.global_position)), "slash_direction": hit.get("slash_direction", Vector3.ZERO), "score_batch": hit.get("score_batch"), "attack_snapshot": hit.get("attack_snapshot")})
		if not is_instance_valid(enemy): continue
		var dealt := before - enemy.health
		if dealt <= 0.0 and not session.combat_modifiers.damage_disabled: continue
		if hit.flying and not enemy.dead: _show_melee_contact(enemy, hit.heading, hit.origin)
		_play_sound(true, enemy.global_position)
		if hit.flying and not enemy.dead:
			if session.combat_frozen: _pending_pushes.append(hit)
			else: player.body_ricochet.push_after_sword_hit(enemy, hit.origin, hit.heading, hit.time)
		hit_landed.emit(enemy, dealt, hit.flying)

func _show_melee_contact(enemy: WaveEnemy, heading: Vector3, origin: Vector3) -> void:
	var visuals := player.action_visuals
	if not visuals or not visuals.combat_readability_enabled or not is_instance_valid(session._attack_root): return
	var feedback := session._attack_root.get_node_or_null("EnemyFeedbackPool") as EnemyFeedbackPool
	if not feedback:
		feedback = EnemyFeedbackPool.new()
		feedback.name = "EnemyFeedbackPool"
		session._attack_root.add_child(feedback)
	feedback.melee_contact(enemy.get_contact_feedback_position(origin), player.sprite.pixel_size * player.sprite.global_basis.x.length(), heading, visuals)

func _update_effect() -> void:
	_update_tails()
	if not swinging or _age < _settings.windup_seconds or not _path.data or not _surface:
		_effect.hide()
		return
	if _settings.has_world_tail() and _age >= _settings.windup_seconds + _settings.sweep_seconds - 0.000001:
		_effect.hide()
		return
	_effect.display(_path.ground_position(player.global_position), _heading, _stats.range, _stats.angle, _reverse,
		_settings.frames, _age - _settings.windup_seconds, _settings, _path, _surface, [player.get_rid()])

func _start_tail(point: Vector3, elapsed: float) -> void:
	if not _settings.has_world_tail() or not _path.data or not _surface or elapsed >= _settings.tail_seconds(): return
	if _settings.effect_mode == PlayerSwordRules.SlashVisual.MEOWA_ARC and not _settings.frames: return
	var slot: Dictionary
	for tail in _tail_pool:
		if tail.age < 0.0:
			slot = tail
			break
	if slot.is_empty():
		var effect := GroundSlashEffect.new()
		effect.name = "SwordResidue%d" % _tail_pool.size()
		add_child(effect)
		effect.top_level = true
		slot = {"effect": effect}
		_tail_pool.append(slot)
	slot.merge({"age": elapsed, "origin": _path.ground_position(point), "heading": _heading,
		"radius": _stats.range, "angle": _stats.angle, "reverse": _reverse, "settings": _settings, "flying": _flight_swing, "fresh": true}, true)

func _advance_tails(delta: float) -> void:
	for tail in _tail_pool:
		if tail.age < 0.0: continue
		tail.age += delta
		if tail.age >= tail.settings.tail_seconds() - 0.000001:
			tail.age = -1.0
			tail.effect.hide()

func _update_tails() -> void:
	if not _path.data or not _surface: return
	var excluded: Array[RID] = [player.get_rid()]
	for tail in _tail_pool:
		if tail.age < 0.0: continue
		var settings: PlayerSwordRules = tail.settings
		var effect: GroundSlashEffect = tail.effect
		var opacity := 1.0
		if tail.get("flying", false) and player.action_visuals and player.action_visuals.combat_readability_enabled:
			opacity = lerpf(1.0, player.action_visuals.combat_residue_opacity, smoothstep(0.0, 0.16, tail.age))
		effect.display(tail.origin, tail.heading, tail.radius, tail.angle, tail.reverse, settings.frames,
			settings.sweep_seconds + tail.age, settings, _path, _surface, excluded, opacity)
		if tail.fresh:
			effect.reset_physics_interpolation()
			tail.fresh = false

func _play_sound(hit: bool, point: Vector3) -> void:
	if not rules.audio_enabled or (hit and _hit_sounds >= 2): return
	var clips: Array[AudioStream] = rules.hit_sounds if hit else rules.sweep_sounds
	if clips.is_empty(): return
	if not is_instance_valid(_audio): _audio = get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	if not _audio: return
	if hit: _hit_sounds += 1
	_audio.request({"source": self, "cue": &"basic_sword_hit" if hit else &"basic_sword_swing", "clips": clips,
		"kind": GameAudio.Kind.HIT if hit else GameAudio.Kind.ATTACK, "position": point,
		"volume_db": rules.audio_volume_db - (4.0 if hit else 0.0), "pitch": randf_range(0.97, 1.03)})

func _on_flight_segment(start: Vector3, end: Vector3, heading: Vector3, seconds: float) -> void:
	var timing := player.body_ricochet.motion_timing(seconds)
	var energy := player.body_ricochet.energy_timing()
	_motion.append({"start": start, "end": end, "heading": heading, "seconds": seconds, "speed": timing.x, "deceleration": timing.y, "orbiting": player.body_ricochet.orbiting, "energy_speed": energy.x, "energy_deceleration": energy.y})

func _on_blink(_start: Vector3, end: Vector3) -> void:
	_motion.clear()
	_last_position = end
	_update_effect()
	_effect.reset_physics_interpolation()

func _on_body_state(state: PlayerRicochet.State) -> void:
	if state == PlayerRicochet.State.CHARGING:
		var held := _manual_held
		cancel(false)
		_manual_held = held

func _on_phase(_phase: int) -> void:
	cancel()
	_motion.clear()
	_last_position = player.global_position
	if is_instance_valid(_audio): _audio.stop_source(self)

func _on_freeze(frozen: bool) -> void:
	if frozen:
		_manual_held = false
		_tap = false

func cancel(reset_clock := true) -> void:
	if not _flight_swing and _settings and _settings.normal_slash_alignment_enabled:
		player.action_animator.cancel_normal_attack()
	_age = -1.0
	_strike_total = 1
	_strike_index = 0
	_pending_hits.clear()
	_stats.erase("score_batch")
	_stats.erase("attack_snapshot")
	_pending_pushes.clear()
	_hits.clear()
	_manual_held = false
	_tap = false
	_requested_heading = Vector3.ZERO
	if reset_clock:
		_since_strike = 1000.0
		_next_reverse = false
		for tail in _tail_pool:
			tail.age = -1.0
			tail.effect.hide()
	if is_instance_valid(_effect): _effect.hide()
