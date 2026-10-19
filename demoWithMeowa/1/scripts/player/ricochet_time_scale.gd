extends RefCounted
## 满蓄和持续环绕共用一个时间所有者，不订阅命中或修改战斗数值。

var active: bool:
	get: return _owned_scale >= 0.0
var ratio: float:
	get: return _owned_scale / _saved_scale if active and _saved_scale > 0.0 else 1.0
var _orbit_weight := 0.0
var _saved_scale := 1.0
var _owned_scale := -1.0
var _yielded := false

func advance(real_delta: float, orbiting: bool, orbit_scale: float, enter_seconds: float, exit_seconds: float, full_scale := 1.0) -> void:
	var seconds := enter_seconds if orbiting else exit_seconds
	_orbit_weight = move_toward(_orbit_weight, 1.0 if orbiting else 0.0, maxf(0.0, real_delta) / maxf(seconds, 0.001))
	var ratio := minf(lerpf(1.0, clampf(orbit_scale, 0.5, 1.0), smoothstep(0.0, 1.0, _orbit_weight)), clampf(full_scale, 0.5, 1.0))
	if active and not is_equal_approx(Engine.time_scale, _owned_scale):
		# 本段让出后不再争抢；下一段才可重新保存外部基准。
		_owned_scale = -1.0
		_yielded = true
	if is_equal_approx(ratio, 1.0):
		_release()
		if not orbiting and _orbit_weight == 0.0: _yielded = false
		return
	if _yielded: return
	if not active: _saved_scale = Engine.time_scale
	_owned_scale = _saved_scale * ratio
	Engine.time_scale = _owned_scale

func _release() -> void:
	if active and is_equal_approx(Engine.time_scale, _owned_scale): Engine.time_scale = _saved_scale
	_owned_scale = -1.0

func reset() -> void:
	_release()
	_orbit_weight = 0.0
	_yielded = false
