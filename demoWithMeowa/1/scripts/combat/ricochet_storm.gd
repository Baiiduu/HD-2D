class_name RicochetStorm
extends Node3D

## 本体弹射专属技能；每次放电分层同时命中，完整批次先选定传播路径。
signal discharge_started(point: Vector3)
signal patch_landed(layer: int, count: int)
signal hit_landed(enemy: WaveEnemy, damage: float)

@export_group("战斗连接")
@export var session: WavePrototype
@export var skill_definition: CombatSkillDefinition
@export var effect_scene: PackedScene
@export var enabled := true:
	set(value):
		enabled = value
		if is_node_ready():
			if not value: cancel_current()
			_refresh_processing()
@export_group("雷电伤害与覆盖")
@export_range(1.0, 1000.0, 1.0) var damage := 7.0
## 每轮冷却跨弹射保留；普通战斗中继续计时，空场不积攒施放次数。
@export_range(0.1, 3.0, 0.01, "suffix:s") var attack_interval := 0.9
@export_range(0.5, 10.0, 0.1, "suffix:m") var trigger_radius := 1.25
@export_range(0.5, 10.0, 0.1, "suffix:m") var spread_radius := 1.5
## 距本次放电触发点的最大水平距离；共享范围增益不扩大这一边界。
@export_range(0.5, 10.0, 0.1, "suffix:m") var max_propagation_radius := 3.6
@export_range(1, 8, 1) var spread_layers := 2
@export_range(1, 24, 1) var targets_per_layer := 3
@export_range(0.02, 0.5, 0.01, "suffix:s") var layer_interval := 0.085
@export_range(0.1, 2.0, 0.05, "suffix:m") var height_tolerance := 0.55
@export_range(0.1, 1.5, 0.05, "suffix:m") var contact_height := 0.45
@export_group("公共战斗声音")
@export var audio_enabled := true
@export var hit_sounds: Array[AudioStream] = []
@export var propagation_sounds: Array[AudioStream] = []
@export_range(-40.0, 6.0, 0.5) var hit_volume_db := -19.0
@export_range(-12.0, 0.0, 0.5) var propagation_layer_gain_db := -3.0

var skill_level := 0
var _body: PlayerRicochet
var _effect: RicochetStormEffect
var _flight_stats := {}
var _until_pulse := 0.0
## 本帧真实飞行已占用的时间；剩余部分按普通战斗时间推进冷却与在途雷潮。
var _frame_flight_seconds := 0.0
var _segments: Array[Dictionary] = []
var _bursts: Array[Dictionary] = []
var _collision := ProjectileCollision.new()
var _trail_point := Vector3.ZERO
var _trail_heading := Vector3.ZERO

func _ready() -> void:
	process_physics_priority = 30
	session.register_combat_node(self)
	session.phase_changed.connect(_phase_changed)
	_bind_body.call_deferred()
	_refresh_processing()

func _bind_body() -> void:
	if not is_instance_valid(session.player): return
	_body = session.player.body_ricochet
	if not _body: return
	_body.state_changed.connect(_body_state_changed)
	_body.launched.connect(_launched)
	_body.flight_segment_travelled.connect(_travelled)
	_body.finished.connect(_flight_finished)

func get_skill_definition() -> CombatSkillDefinition:
	return skill_definition

func apply_skill_level(level: int) -> bool:
	if not skill_definition or (level != 0 and not skill_definition.level_data(level)): return false
	skill_level = level
	if level == 0: cancel_current()
	if is_node_ready(): _refresh_processing()
	return true

func get_attack_stats(level := -1, modifiers: RunCombatModifiers = null) -> Dictionary:
	if level < 0: level = skill_level
	var data := skill_definition.level_data(level) if skill_definition else null
	var values: Dictionary = data.parameters if data else {}
	if not modifiers and session: modifiers = session.combat_modifiers
	var reach := modifiers.range_multiplier() if modifiers else 1.0
	return {"damage": damage * values.get("damage_multiplier", 1.0) * (modifiers.damage_multiplier() if modifiers else 1.0),
		"interval": maxf(0.08, attack_interval * values.get("interval_multiplier", 1.0) * (modifiers.interval_multiplier() if modifiers else 1.0)),
		"range": minf(max_propagation_radius, trigger_radius * values.get("range_multiplier", 1.0) * reach),
		"spread": minf(max_propagation_radius, spread_radius * values.get("range_multiplier", 1.0) * reach),
		"max_radius": max_propagation_radius,
		"layers": maxi(1, spread_layers + int(values.get("extra_layers", 0.0))),
		"targets": maxi(1, targets_per_layer + int(values.get("extra_targets", 0.0))),
		"layer_interval": maxf(0.02, layer_interval)}

func get_combat_stats(modifiers: RunCombatModifiers = null) -> Dictionary:
	if not enabled or skill_level <= 0: return {}
	var stats := get_attack_stats(skill_level, modifiers)
	return {"name": "奔雷涌潮", "damage": stats.damage, "interval": stats.interval, "range": stats.range}

func describe_skill_upgrade(from_level: int, to_level: int) -> String:
	var after := get_attack_stats(to_level)
	if from_level == 0:
		return "弹射中周期引发雷潮\n每片最多 %d 只 · 扩散 %d 层\n每只伤害 %.1f · 间隔 %.2f 秒\n切入 %.2f 米 · 传导 %.1f 米\n最远 %.1f 米 · 每轮每怪一次\n下一轮可再次命中" % [after.targets, after.layers, after.damage, after.interval, after.range, after.spread, after.max_radius]
	var before := get_attack_stats(from_level)
	return "雷伤 %.1f → %.1f\n每片 %d → %d 只\n扩散 %d → %d 层\n间隔 %.2f → %.2f 秒\n%s" % [before.damage, after.damage, before.targets, after.targets, before.layers, after.layers, before.interval, after.interval, skill_definition.level_data(to_level).description]

func _active() -> bool:
	return enabled and skill_level > 0 and session._path_ready and session.combat_active()

func _refresh_processing() -> void:
	set_physics_process(enabled and skill_level > 0 and (_until_pulse > 0.0 or not _segments.is_empty() or not _bursts.is_empty()))

func _phase_changed(_phase: int) -> void:
	cancel_current()

func _body_state_changed(state: PlayerRicochet.State) -> void:
	if state == PlayerRicochet.State.CHARGING:
		_flight_stats = get_attack_stats() if _active() else {}

func _launched(_direction: Vector3, _speed: float, _charge: float) -> void:
	if not _active() or _flight_stats.is_empty(): return
	_segments.clear()
	_frame_flight_seconds = 0.0
	_trail_point = session.player.global_position
	_trail_heading = Vector3.ZERO

func _travelled(start: Vector3, end: Vector3, heading: Vector3, seconds: float) -> void:
	if not _active() or _flight_stats.is_empty(): return
	var timing := _body.motion_timing(seconds)
	_segments.append({"start": start, "end": end, "heading": heading, "seconds": seconds, "speed": timing.x, "deceleration": timing.y})
	_frame_flight_seconds += seconds
	_refresh_processing()

func _flight_finished(reason: StringName) -> void:
	if reason == &"cancelled":
		_segments.clear()
		_frame_flight_seconds = 0.0
		_flight_stats.clear()
		_refresh_processing()

func _physics_process(delta: float) -> void:
	if session.combat_frozen: return
	if not _active(): cancel_current(); return
	# 飞行与落地时间排在同一条时间线上，避免同一帧重复扣冷却或延后新雷潮的传播。
	var idle := maxf(0.0, delta - _frame_flight_seconds)
	_frame_flight_seconds = 0.0
	if idle > 0.0 and (_until_pulse > 0.0 or not _segments.is_empty() or not _bursts.is_empty()):
		_segments.append({"idle": true, "seconds": idle})
	_advance_time(0.0)
	while not _segments.is_empty():
		if not _active(): return
		var piece := _segments[0]
		if piece.get("idle", false):
			piece.elapsed = float(piece.get("elapsed", 0.0)) + _advance_time(float(piece.seconds) - float(piece.get("elapsed", 0.0)))
			if not _active(): return
		elif not _trace_piece(piece): return
		_segments.pop_front()
	_refresh_processing()

## 推进实际经过的战斗时间；传播中触发升级时返回已消费部分，余量留在原路段。
func _advance_time(seconds: float) -> float:
	var used := 0.0
	while _active():
		var step := maxf(0.0, seconds - used)
		for burst in _bursts: step = minf(step, maxf(0.0, float(burst.wait)))
		_until_pulse = maxf(0.0, _until_pulse - step)
		for burst in _bursts: burst.wait -= step
		used += step
		for burst in _bursts.duplicate():
			if float(burst.wait) > 0.000001: continue
			_deliver_layer(burst)
			if not _active(): return used
			if burst in _bursts: burst.wait += float(burst.stats.layer_interval)
		if used >= seconds - 0.000001: break
	return used

func _trace_piece(piece: Dictionary) -> bool:
	var start: Vector3 = piece.start
	var end: Vector3 = piece.end
	var seconds: float = piece.seconds
	var elapsed: float = piece.get("elapsed", 0.0)
	while elapsed <= seconds:
		var wait := minf(_until_pulse, seconds - elapsed)
		elapsed += _advance_time(wait)
		piece.elapsed = elapsed
		if not _active(): return false
		if _until_pulse > 0.000001: break
		var fraction := PlayerRicochetRules.segment_fraction(elapsed, seconds, piece.get("speed", 0.0), piece.get("deceleration", 0.0))
		var point := start.lerp(end, fraction)
		var entry := _first_contact(point, end, float(_flight_stats.range))
		if entry < 0.0:
			piece.elapsed = elapsed + _advance_time(seconds - elapsed)
			if not _active(): return false
			break
		var contact_time := PlayerRicochetRules.segment_time(lerpf(fraction, 1.0, entry), seconds, piece.get("speed", 0.0), piece.get("deceleration", 0.0))
		elapsed += _advance_time(maxf(0.0, contact_time - elapsed))
		piece.elapsed = elapsed
		if not _active(): return false
		point = point.lerp(end, entry)
		_until_pulse = float(_flight_stats.interval)
		if not discharge(point, _flight_stats): _until_pulse = 0.0
		if not _active(): return false
		if elapsed >= seconds: break
	# 电痕来自真实折线路段，不跨过转角画一条直线，也不产生额外伤害。
	if _trail_heading != Vector3.ZERO and _trail_heading.dot(piece.heading) < 0.99:
		_effects().show_link(_trail_point + Vector3.UP * contact_height, start + Vector3.UP * contact_height, 0.45, RicochetStormEffect.Kind.TRAIL)
		_trail_point = start
	_trail_heading = piece.heading
	if _trail_point.distance_to(end) >= 0.55:
		_effects().show_link(_trail_point + Vector3.UP * contact_height, end + Vector3.UP * contact_height, 0.45, RicochetStormEffect.Kind.TRAIL)
		_trail_point = end
	return true

func _first_contact(start: Vector3, end: Vector3, radius: float) -> float:
	var length := TerrainPath.horizontal_distance(start, end)
	var contacts: Array[Dictionary] = []
	for enemy in session.get_nearby_enemies((start + end) * 0.5, radius + length * 0.5):
		if not _eligible(enemy) or absf(enemy.global_position.y - start.y) > height_tolerance: continue
		var entry := PlayerRicochet.circle_entry(start, end, enemy.global_position, radius)
		if entry >= 0.0: contacts.append({"enemy": enemy, "entry": entry})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary): return a.entry < b.entry)
	for contact in contacts:
		if _clear_path(start.lerp(end, contact.entry), contact.enemy.global_position): return contact.entry
	return -1.0

func _eligible(enemy: WaveEnemy) -> bool:
	return is_instance_valid(enemy) and not enemy.dead and enemy.spawn_delay <= 0.0

func _clear_path(from: Vector3, to: Vector3) -> bool:
	if absf(from.y - to.y) > height_tolerance: return false
	var offset := to - from
	offset.y = 0.0
	var distance := offset.length()
	if distance < 0.0001: return true
	var direction := offset / distance
	if _collision.ground_limit(session._path, from, direction, distance, from.y, height_tolerance) < distance - 0.01: return false
	var ray := PhysicsRayQueryParameters3D.create(from + Vector3.UP * contact_height, to + Vector3.UP * contact_height, 1, [session.player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _within_propagation(origin: Vector3, from: Vector3, to: Vector3, radius: float, limit: float, outward: bool) -> bool:
	var distance := TerrainPath.horizontal_distance(origin, to)
	if distance > limit + 0.0001 or TerrainPath.horizontal_distance(from, to) > radius + 0.0001: return false
	return not outward or distance > TerrainPath.horizontal_distance(origin, from) + 0.001

func _plan_layer(frontier: Array[Dictionary], radius: float, seen: Dictionary, count: int, origin: Vector3, limit: float) -> Array[Dictionary]:
	var candidates := {}
	for source in frontier:
		for enemy in session.get_nearby_enemies(source.point, radius + 0.0001):
			if not _eligible(enemy) or seen.has(enemy.get_instance_id()): continue
			var point := enemy.global_position
			if absf(point.y - float(source.point.y)) > height_tolerance: continue
			var distance := TerrainPath.horizontal_distance(source.point, point)
			if not _within_propagation(origin, source.point, point, radius, limit, source.id != 0): continue
			var id := enemy.get_instance_id()
			if not candidates.has(id): candidates[id] = {"enemy": weakref(enemy), "id": id, "point": point, "sources": []}
			candidates[id].sources.append({"id": source.id, "point": source.point, "distance": distance})
	var ordered: Array = candidates.values()
	for candidate in ordered:
		candidate.sources.sort_custom(func(a: Dictionary, b: Dictionary): return a.distance < b.distance)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return a.sources[0].distance < b.sources[0].distance if not is_equal_approx(a.sources[0].distance, b.sources[0].distance) else a.id < b.id)
	var result: Array[Dictionary] = []
	for candidate in ordered:
		for source in candidate.sources:
			if not _clear_path(source.point, candidate.point): continue
			result.append({"enemy": candidate.enemy, "id": candidate.id, "point": candidate.point, "parent": source.id, "from": source.point})
			seen[candidate.id] = 0
			break
		if result.size() >= count: break
	return result

## 每轮独立预留与去重；跨轮可再次命中，不与旧雷潮共享记录。飞行调度负责冷却。
func discharge(origin: Vector3, stats: Dictionary = {}) -> bool:
	if not _active(): return false
	if stats.is_empty(): stats = get_attack_stats()
	var seen := {}
	var frontier: Array[Dictionary] = [{"id": 0, "point": origin}]
	var layers: Array = []
	for index in int(stats.layers):
		var layer := _plan_layer(frontier, float(stats.range if index == 0 else stats.spread), seen, int(stats.targets), origin, float(stats.max_radius))
		if layer.is_empty(): break
		layers.append(layer)
		frontier = layer
	if layers.is_empty(): return false
	var burst := {"layers": layers, "next": 0, "wait": 0.0, "stats": stats.duplicate(), "generation": session._generation, "landed": {0: origin}, "blocked": {}, "seen": seen}
	_bursts.append(burst)
	discharge_started.emit(origin)
	_deliver_layer(burst)
	if _active() and burst in _bursts: burst.wait = float(burst.stats.layer_interval)
	_refresh_processing()
	return true

func _finish_burst(burst: Dictionary) -> void:
	_bursts.erase(burst)

func _contact_reachable(burst: Dictionary, contact: Dictionary, from: Vector3, to: Vector3) -> bool:
	var radius := float(burst.stats.range if burst.next == 0 else burst.stats.spread)
	return _within_propagation(burst.landed[0], from, to, radius, float(burst.stats.max_radius), contact.parent != 0) and _clear_path(from, to)

func _deliver_layer(burst: Dictionary) -> void:
	if not _active() or burst.generation != session._generation:
		_finish_burst(burst)
		return
	if not burst.has("current"):
		burst.current = []
		burst.cursor = 0
		burst.patch_points = PackedVector3Array()
		# 同片资格全部锁定后才扣血；冻结发生在死亡回调中也不重复已扣伤害。
		for contact in burst.layers[burst.next]:
			var enemy := contact.enemy.get_ref() as WaveEnemy
			if burst.blocked.has(contact.parent):
				burst.blocked[contact.id] = true
				continue
			var from: Vector3 = burst.landed.get(contact.parent, contact.from)
			var to: Vector3 = enemy.global_position if _eligible(enemy) else contact.point
			if not _contact_reachable(burst, contact, from, to):
				burst.blocked[contact.id] = true
				continue
			if not _eligible(enemy):
				burst.landed[contact.id] = to
				continue
			burst.current.append({"enemy": contact.enemy, "from": from, "point": to, "id": contact.id, "parent": contact.parent})
	var confirmed: Array = burst.current
	var effects := _effects()
	while burst.cursor < confirmed.size():
		if not _active() or burst.generation != session._generation or burst not in _bursts: return
		var index := int(burst.cursor)
		var contact: Dictionary = confirmed[index]
		burst.cursor += 1
		var enemy := contact.enemy.get_ref() as WaveEnemy
		if not _eligible(enemy): continue
		if not _contact_reachable(burst, contact, contact.from, enemy.global_position):
			burst.blocked[contact.id] = true
			continue
		contact.point = enemy.global_position
		burst.landed[contact.id] = contact.point
		# 首片是就地引雷；只有已有怪物向后续怪物传导时才显示连接。
		if contact.parent != 0:
			effects.show_link(contact.from + Vector3.UP * contact_height, contact.point + Vector3.UP * contact_height)
		effects.show_hit(contact.point, index == 0 or (confirmed.size() >= 4 and index == confirmed.size() - 1))
		burst.patch_points.append(contact.point)
		var before := enemy.health
		burst.seen[contact.id] = 1
		enemy.take_damage(float(burst.stats.damage), {"source": &"ricochet_storm", "style": &"lightning", "direction": enemy.global_position - contact.from})
		var dealt := before - enemy.health
		if dealt > 0.0 or session.combat_modifiers.damage_disabled: hit_landed.emit(enemy, dealt)
	if not _active(): return
	# 只把本片实际落雷的位置组成电涌面；不补目标、不扩大伤害或生成假传播线。
	effects.show_patch(burst.patch_points)
	if not confirmed.is_empty():
		_play_patch_sound(confirmed[0].point, int(burst.next))
		patch_landed.emit(int(burst.next), confirmed.size())
	burst.next += 1
	burst.erase("current")
	if burst.next >= burst.layers.size(): _finish_burst(burst)

func _effects() -> RicochetStormEffect:
	if not is_instance_valid(_effect):
		_effect = effect_scene.instantiate() as RicochetStormEffect
		add_child(_effect)
	return _effect

func _play_patch_sound(point: Vector3, layer := 0) -> void:
	if not audio_enabled: return
	var clips := propagation_sounds if layer > 0 and not propagation_sounds.is_empty() else hit_sounds
	if clips.is_empty(): return
	var manager := get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	if manager: manager.request({"cue": &"ricochet_storm_start" if layer == 0 else &"ricochet_storm_chain", "source": self,
		"kind": GameAudio.Kind.ATTACK if layer == 0 else GameAudio.Kind.HIT, "clips": clips,
		"position": point, "volume_db": hit_volume_db + propagation_layer_gain_db * layer})

func cancel_current() -> void:
	_segments.clear()
	_bursts.clear()
	_flight_stats.clear()
	_until_pulse = 0.0
	_frame_flight_seconds = 0.0
	if is_instance_valid(_effect): _effect.stop()
	if is_inside_tree():
		var manager := get_tree().get_first_node_in_group(&"game_audio") as GameAudio
		if manager: manager.stop_source(self)
	set_physics_process(false)
