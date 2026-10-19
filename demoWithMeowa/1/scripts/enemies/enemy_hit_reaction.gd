extends RefCounted

## 仅保存身体倾斜；解析衰减不占用怪物的移动、动画或攻击时钟。
var lean := Vector3.ZERO
var active: bool:
	get: return _remaining > 0.0
var _velocity := Vector3.ZERO
var _remaining := 0.0
var _seconds := 0.26
var _limit := 0.0

func strike(direction: Vector3, degrees: float, seconds: float) -> void:
	if not direction.is_finite() or not is_finite(degrees) or not is_finite(seconds) or degrees <= 0.0 or seconds <= 0.0: return
	direction.y = 0.0
	if direction.is_zero_approx(): return
	_limit = deg_to_rad(clampf(degrees, 0.0, 20.0))
	_seconds = maxf(seconds, 0.05)
	_remaining = _seconds
	var damping := 4.2 / _seconds
	var frequency := 8.5 / _seconds
	var peak_time := atan(frequency / damping) / frequency
	var peak := exp(-damping * peak_time) * sin(frequency * peak_time) / frequency
	var impulse := _limit / peak
	# 连击接续当前角度，仅补有上限的角速度，不归零或无限堆积。
	_velocity = (_velocity + Vector3.UP.cross(direction.normalized()) * impulse).limit_length(impulse)

func advance(delta: float) -> void:
	if not active or not is_finite(delta) or delta <= 0.0: return
	var step := minf(delta, _remaining)
	var damping := 4.2 / _seconds
	var frequency := 8.5 / _seconds
	var a := lean
	var b := (_velocity + a * damping) / frequency
	var decay := exp(-damping * step)
	var sine := sin(frequency * step)
	var cosine := cos(frequency * step)
	lean = decay * (a * cosine + b * sine)
	_velocity = decay * ((b * frequency - a * damping) * cosine - (a * frequency + b * damping) * sine)
	if lean.length() > _limit:
		lean = lean.limit_length(_limit)
		var outward := lean.normalized()
		_velocity -= outward * maxf(0.0, _velocity.dot(outward))
	_remaining = maxf(0.0, _remaining - step)
	if _remaining <= 0.000001: clear()

func clear() -> void:
	lean = Vector3.ZERO
	_velocity = Vector3.ZERO
	_remaining = 0.0
