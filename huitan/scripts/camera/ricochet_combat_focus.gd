extends RefCounted

## 只消费真实环绕和已命中事件，不查询怪群、不改变运动或伤害时钟。
var orbit_weight := 0.0
var focus_offset := Vector3.ZERO
var recoil := Vector3.ZERO
var pulse := 0.0
var age := 10.0
var beat_count := 0
var _serial := 0
var _sword_id := -1
var _sword_hits := 0
var _sword_kills := 0
var _sword_heading := Vector3.ZERO
var _sword_point := Vector3.ZERO
var _pending_id := -1
var _pending_strength := 0.0
var _pending_kills := 0
var _pending_heading := Vector3.ZERO
var _pending_point := Vector3.ZERO
var _merged_ids: Dictionary[int, bool] = {}
var _strength := 0.0
var _heading := Vector3.ZERO
var _point := Vector3.ZERO
var _cooldown := 0.0
var _lead_retention := 0.25

func reset() -> void:
	orbit_weight = 0.0
	focus_offset = Vector3.ZERO
	recoil = Vector3.ZERO
	pulse = 0.0
	age = 10.0
	beat_count = 0
	_sword_id = -1
	_pending_id = -1
	_pending_strength = 0.0
	_pending_kills = 0
	_merged_ids.clear()
	_cooldown = 0.0

func begin_sword(heading: Vector3, flying: bool) -> void:
	_serial += 1
	_sword_id = _serial if flying else -1
	_sword_hits = 0
	_sword_kills = 0
	_sword_heading = heading
	_sword_point = Vector3.ZERO

func sword_hit(point: Vector3, killed: bool) -> void:
	if _sword_id < 0: return
	_sword_hits += 1
	_sword_kills += int(killed)
	_sword_point += point
	_queue(_sword_id, _sword_point / _sword_hits, _sword_heading, _sword_hits, _sword_kills)

func storm_patch(point: Vector3, hits: int, kills: int, origin := Vector3.ZERO) -> void:
	if hits <= 0: return
	_serial += 1
	_queue(_serial, point, point - origin, hits, kills)

func _queue(id: int, point: Vector3, heading: Vector3, hits: int, kills: int) -> void:
	var strength := clampf(0.15 + mini(hits, 4) * 0.1 + mini(kills, 3) * 0.15, 0.0, 1.0)
	if strength < _pending_strength: return
	_pending_id = id
	_pending_strength = strength
	_pending_kills = kills
	_pending_heading = Vector3(heading.x, 0, heading.z).normalized()
	_pending_point = point

func advance(delta: float, orbiting: bool, point: Vector3, center: Vector3, settings: RicochetCameraSettings) -> void:
	_lead_retention = settings.orbit_lead_retention
	_cooldown = maxf(0.0, _cooldown - delta)
	var keep_pending := false
	if settings.combat_beat_enabled and _pending_id >= 0:
		if _merged_ids.has(_pending_id):
			_strength = maxf(_strength, _pending_strength)
		elif _cooldown <= 0.0:
			_merged_ids.clear()
			_merged_ids[_pending_id] = true
			_strength = _pending_strength
			_heading = _pending_heading
			_point = _pending_point
			age = 0.0
			_cooldown = settings.combat_beat_interval
			beat_count += 1
		elif _pending_kills >= 3 and _pending_strength > _strength:
			if age < settings.combat_beat_seconds * 0.5:
				# 群杀只增强同一下，保留当前方向、时钟与剩余间隔。
				_strength = _pending_strength
				_merged_ids[_pending_id] = true
			else:
				# 回稳末段不再加一记小抖，只保留最强群杀到原间隔结束。
				keep_pending = true
	if not keep_pending:
		_pending_id = -1
		_pending_strength = 0.0
		_pending_kills = 0
	age += maxf(delta, 0.0)
	var phase := clampf(age / maxf(settings.combat_beat_seconds, 0.001), 0.0, 1.0)
	pulse = sin(PI * phase) * (1.0 - phase) * _strength if settings.combat_beat_enabled and phase < 1.0 else 0.0
	recoil = -_heading * pulse
	var weight := 1.0 - exp(-maxf(delta, 0.0) / maxf(settings.orbit_settle_seconds, 0.001))
	var goal := 1.0 if orbiting and settings.orbit_focus_enabled else 0.0
	orbit_weight = lerpf(orbit_weight, goal, weight)
	var offset := (center - point).limit_length(settings.orbit_focus_max_distance) * settings.orbit_focus_weight * orbit_weight
	offset += (_point - point).limit_length(1.0) * pulse * 0.12 * orbit_weight
	offset.y = 0.0
	focus_offset = focus_offset.lerp(offset, weight)

func lead_goal(base: Vector2, view: Basis, span: float) -> Vector2:
	return base * lerpf(1.0, _lead_retention, orbit_weight) + Vector2(focus_offset.dot(view.x), focus_offset.dot(view.y)) / maxf(span, 0.001)
