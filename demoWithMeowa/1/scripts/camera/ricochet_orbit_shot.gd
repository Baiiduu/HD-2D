extends RefCounted

## 持续近景独立于限频的进出弧线，只消费真实环绕，不查询怪群。
var distance_offset := 0.0
var magnification := 1.0
var focus_offset := Vector3.ZERO
var pitch_offset := 0.0
var active: bool:
	get: return accent_active or _zoom_orbiting or not is_equal_approx(magnification, 1.0)
var accent_active: bool:
	get: return _running and _age < _seconds
var _orbiting := false
var _orbit_age := 0.0
var _age := 0.0
var _seconds := 0.0
var _cooldown := 0.0
var _running := false
var _entering := false
var _heading := Vector3.FORWARD
var _inward := Vector3.RIGHT
var _first := Vector3.ZERO
var _second := Vector3.ZERO
var _zoom_orbiting := false
var _zoom_age := 0.0
var _zoom_from := 1.0
var _entry_peak := false
var _hold_target := 1.4
var _exit_hold := 0.0

func clear(keep_interval := false) -> void:
	distance_offset = 0.0
	magnification = 1.0
	_zoom_orbiting = false
	_zoom_age = 0.0
	_zoom_from = 1.0
	_entry_peak = false
	_exit_hold = 0.0
	focus_offset = Vector3.ZERO
	pitch_offset = 0.0
	_running = false
	_orbiting = false
	_orbit_age = 0.0
	_age = 0.0
	_seconds = 0.0
	_heading = Vector3.FORWARD
	_inward = Vector3.RIGHT
	if not keep_interval: _cooldown = 0.0

func suppress(orbiting: bool) -> void:
	# 接管时同步实际状态，交还镜头后不补播旧边沿。
	_orbiting = orbiting
	_orbit_age = 0.0
	_running = false
	focus_offset = Vector3.ZERO
	pitch_offset = 0.0

func observe(orbiting: bool, settings: RicochetCameraSettings, heading := Vector3.ZERO, inward := Vector3.ZERO, accent_allowed := true) -> void:
	var travel := Vector3(heading.x, 0.0, heading.z)
	if not travel.is_zero_approx(): _heading = travel.normalized()
	var toward := Vector3(inward.x, 0.0, inward.z)
	if orbiting and not toward.is_zero_approx(): _inward = toward.normalized()
	if orbiting == _orbiting: return
	var held := _orbit_age
	_orbiting = orbiting
	_orbit_age = 0.0
	if not settings.orbit_shot_enabled or not accent_allowed or accent_active or _cooldown > 0.0: return
	if not orbiting and held < settings.orbit_exit_minimum_seconds: return
	_entering = orbiting
	_running = true
	# 拍摄方向在真实进出边沿固定；续段与 Q/E 不重新选择弧线或翻边。
	var side := Vector3.UP.cross(_heading)
	if side.dot(_inward) < 0.0: side = -side
	_first = _heading * 1.3
	_second = (_inward * 0.75 + side * 0.65).normalized() * 1.3 if orbiting else (_heading * 0.85 - _inward * 0.35).normalized() * 1.1
	_seconds = maxf(settings.orbit_shot_seconds, 0.001)
	_age = 0.0
	_cooldown = maxf(settings.orbit_shot_interval, _seconds)

func advance(delta: float, orbiting: bool, settings: RicochetCameraSettings, blocked := false, heading := Vector3.ZERO, inward := Vector3.ZERO, closeup_blocked := false) -> void:
	delta = maxf(delta, 0.0)
	_cooldown = maxf(0.0, _cooldown - delta)
	if blocked or not settings.orbit_shot_enabled:
		suppress(orbiting)
	else:
		observe(orbiting, settings, heading, inward)
	_advance_closeup(delta, orbiting and settings.orbit_shot_enabled and not closeup_blocked, settings, blocked, closeup_blocked or not settings.orbit_shot_enabled)
	distance_offset = 1.0 / magnification - 1.0
	if orbiting: _orbit_age += delta
	_age += delta
	if not accent_active:
		_running = false
		focus_offset = Vector3.ZERO
		pitch_offset = 0.0
		return
	var phase := clampf(_age / _seconds, 0.0, 1.0)
	# 前段轻推，后段较慢归位；首尾及峰值速度为零。
	var weight := smoothstep(0.0, 0.28, phase) if phase < 0.28 else 1.0 - smoothstep(0.28, 1.0, phase)
	pitch_offset = settings.orbit_shot_pitch_degrees * (-1.0 if _entering else 0.5) * weight
	# 零端点三次曲线：先接住来向，再弯向怪群／出口，首尾零速度。
	var t := smoothstep(0.0, 1.0, phase)
	var arc := 3.0 * (1.0 - t) * t * ((1.0 - t) * _first + t * _second)
	focus_offset = arc.limit_length(1.0) * minf(settings.orbit_shot_offset_ratio, settings.max_offset_ratio)

func _advance_closeup(delta: float, orbiting: bool, settings: RicochetCameraSettings, blocked: bool, skip_exit_hold: bool) -> void:
	var hold := maxf(1.0, settings.orbit_hold_magnification)
	if orbiting != _zoom_orbiting:
		_zoom_orbiting = orbiting
		_zoom_from = magnification
		_zoom_age = 0.0
		_exit_hold = maxf(0.0, settings.orbit_closeup_exit_hold_seconds) if not orbiting and not skip_exit_hold else 0.0
		_entry_peak = orbiting and accent_active and _entering and is_zero_approx(_age) and not blocked
		_hold_target = hold
	elif blocked and _entry_peak:
		# 群杀只让短入圈重音退到稳定近景，不把整段环绕踢回远景。
		_entry_peak = false
		_zoom_from = magnification
		_zoom_age = 0.0
	if not orbiting and skip_exit_hold and _exit_hold > 0.0:
		# 高优先级接管跳过等待，已进入归位时仍保留原有曲线进度。
		_zoom_age = maxf(0.0, _zoom_age - _exit_hold)
		_exit_hold = 0.0
	if orbiting and not is_equal_approx(hold, _hold_target):
		# Inspector 调参也从当前距离接续，不重新播放入圈峰值。
		_hold_target = hold
		_zoom_from = magnification
		_zoom_age = 0.0
		_entry_peak = false
	_zoom_age += delta
	if not orbiting:
		magnification = lerpf(_zoom_from, 1.0, smoothstep(0.0, maxf(settings.orbit_closeup_exit_seconds, 0.001), maxf(0.0, _zoom_age - _exit_hold)))
		return
	var enter := maxf(settings.orbit_closeup_enter_seconds, 0.001)
	var settle := maxf(settings.orbit_shot_seconds, enter + 0.001)
	var peak := maxf(1.0, settings.orbit_enter_magnification)
	if _entry_peak:
		magnification = lerpf(_zoom_from, peak, smoothstep(0.0, enter, _zoom_age)) if _zoom_age <= enter else lerpf(peak, hold, smoothstep(enter, settle, _zoom_age))
	else:
		magnification = lerpf(_zoom_from, hold, smoothstep(0.0, enter, _zoom_age))
